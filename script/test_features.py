#!/usr/bin/env python3
"""Independent three-member replica set and local HTTP protocol fixture; no real AI service."""
import http.server
import json
import os
import pathlib
import subprocess
import sys
import threading
import time
import uuid

root = pathlib.Path(__file__).resolve().parent.parent
identifiers = []
network = 'tableviewer-feature-' + uuid.uuid4().hex[:8]
ports = []
ui_mode = '--ui' in sys.argv

def command(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, code, value):
        body = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not ui_mode and self.headers.get('Authorization') != 'Bearer fixture-key':
            return self.respond(401, {'error': {'message': 'Missing fixture key'}})
        self.respond(200, {'data': [{'id': 'stream-tools'}, {'id': 'plain'}]})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        model = body['model']
        if ui_mode:
            returned = any(message['role'] == 'tool' for message in body['messages'])
            print('UI API: tool results received' if returned else 'UI API: proposal requested', flush=True)
            message = {'role': 'assistant', 'content': '已完成：当前项目共有 12 条记录。'} if returned else {'role': 'assistant', 'content': '我会统计当前项目数量。请确认下面的只读查询。', 'tool_calls': [{'id': 'ui_count', 'type': 'function', 'function': {'name': 'execute_query', 'arguments': json.dumps({'query': 'SELECT COUNT(*) AS total FROM projects', 'reason': '只读统计项目数量，不修改数据。'})}}]}
            return self.respond(200, {'choices': [{'message': message, 'finish_reason': 'stop' if returned else 'tool_calls'}]})
        if model == 'unauthorized':
            return self.respond(401, {'error': {'message': 'Bad API key fixture-key'}})
        if model == 'redirect':
            self.send_response(307)
            self.send_header('Location', f'http://127.0.0.1:{self.server.server_port}/unexpected-target')
            self.end_headers()
            return
        if model == 'plain':
            return self.respond(200, {'choices': [{'message': {'role': 'assistant', 'content': '兼容接口连接正常'}, 'finish_reason': 'stop'}]})
        assert body['tools'][0]['function']['name'] == 'inspect_schema'
        assert body['messages'][0]['role'] == 'system'
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        events = [
            {'choices': [{'delta': {'content': '我会先'}, 'finish_reason': None}]},
            {'choices': [{'delta': {'content': '检查结构。', 'tool_calls': [{'index': 0, 'id': 'call_schema', 'type': 'function', 'function': {'name': 'inspect_schema', 'arguments': '{'}}]}, 'finish_reason': None}]},
            {'choices': [{'delta': {'tool_calls': [{'index': 0, 'function': {'arguments': '}'}}]}, 'finish_reason': 'tool_calls'}]}
        ]
        for event in events[:1] if model == 'truncated' else events:
            self.wfile.write(('data: ' + json.dumps(event, ensure_ascii=False) + '\n\n').encode())
            self.wfile.flush()
        if model != 'truncated':
            self.wfile.write(b'data: [DONE]\n\n')

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    command('docker', 'network', 'create', network)
    for index in range(3):
        identifier = command('docker', 'run', '-d', '--network', network, '--network-alias', f'node{index}', '-p', '127.0.0.1::27017', 'mongo:7.0', '--replSet', 'tvrs', '--bind_ip_all')
        identifiers.append(identifier)
        ports.append(command('docker', 'port', identifier, '27017/tcp').rsplit(':', 1)[1])
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            for identifier in identifiers:
                command('docker', 'exec', identifier, 'mongosh', '--quiet', '--eval', 'db.adminCommand({ping:1}).ok')
            break
        except subprocess.CalledProcessError:
            time.sleep(1)
    configuration = {'_id': 'tvrs', 'members': [{'_id': i, 'host': f'node{i}:27017', 'priority': 2 if i == 0 else 1} for i in range(3)]}
    command('docker', 'exec', identifiers[0], 'mongosh', '--quiet', '--eval', 'rs.initiate(' + json.dumps(configuration) + ')')
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            status = json.loads(command('docker', 'exec', identifiers[0], 'mongosh', '--quiet', '--eval', 'JSON.stringify(rs.status().members.map(m=>m.stateStr))'))
            if status[0] == 'PRIMARY' and status.count('SECONDARY') == 2:
                break
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            pass
        time.sleep(1)
    else:
        raise RuntimeError('Replica set did not elect a primary and two secondaries')
    environment = os.environ.copy()
    environment['TABLEVIEWER_REPLICA_PORT'] = ports[0]
    environment['TABLEVIEWER_MOCK_API'] = f'http://127.0.0.1:{server.server_port}/v1'
    if ui_mode:
        command('docker', 'exec', identifiers[0], 'mongosh', '--quiet', '--eval', "db.getSiblingDB('studio').projects.insertMany([{name:'Aperture',status:'active'},{name:'Quiet Hours',status:'complete'}])")
        print(json.dumps({'mongoURI': f'mongodb://127.0.0.1:{ports[0]}/?directConnection=true', 'database': 'studio', 'api': environment['TABLEVIEWER_MOCK_API']}) , flush=True)
        input('Press Return to clean up UI fixtures.\n')
    else:
        runner = 'test_sandbox.sh' if '--sandbox' in sys.argv else 'test_features.sh'
        subprocess.run([str(root / 'script' / runner)], cwd=root, env=environment, check=True)
finally:
    server.shutdown()
    for identifier in reversed(identifiers):
        subprocess.run(['docker', 'rm', '-fv', identifier], stdout=subprocess.DEVNULL, check=True)
    subprocess.run(['docker', 'network', 'rm', network], stdout=subprocess.DEVNULL, check=True)
