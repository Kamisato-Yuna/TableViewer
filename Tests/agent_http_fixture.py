"""Loopback-only synthetic Chat Completions fixture. Never reads real app configuration."""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.headers['Authorization'] == 'Bearer fixture-key'
        assert {tool['function']['name'] for tool in body['tools']} == {'inspect_schema', 'execute_query', 'ask_user'}
        model = body['model']
        question_schema = next(tool['function']['parameters'] for tool in body['tools'] if tool['function']['name'] == 'ask_user')
        assert question_schema['properties']['options']['maxItems'] == 12
        assert question_schema['required'] == ['question']
        if model == 'unauthorized':
            self.send_response(401)
            self.end_headers()
            self.wfile.write(json.dumps({'error': {'message': 'bad fixture-key'}}).encode())
            return
        self.send_response(200)
        self.send_header('Content-Type', 'application/json' if model == 'plain' else 'text/event-stream')
        self.end_headers()
        if model == 'plain':
            self.wfile.write(json.dumps({'choices': [{'message': {'content': '<think>PRIVATE</think># SQLite\n\n```sql\nSELECT 1;\n```', 'reasoning_content': 'PRIVATE_FIELD'}, 'finish_reason': 'stop'}]}).encode())
            return
        def send(delta, finish=None):
            self.wfile.write(('data: ' + json.dumps({'choices': [{'delta': delta, 'finish_reason': finish}]}) + '\n\n').encode())
            self.wfile.flush()
        if model in ('five-options', 'freeform-question', 'malformed-question'):
            results = [message for message in body['messages'] if message['role'] == 'tool']
            if results and results[-1]['content'] == 'projects':
                send({'content': '已选择 projects'}, 'stop')
            else:
                question = {'question': '当前数据库有 5 个表，你想查看哪个表的数据？', 'options': ['active_projects', 'activity', 'members', 'notes', 'projects']}
                if model == 'freeform-question':
                    question.pop('options')
                if model == 'malformed-question' and not results:
                    question['options'] = 'wrong type'
                arguments = json.dumps(question, ensure_ascii=False)
                send({'tool_calls': [{'index': 0, 'id': f'question-{len(results)}', 'type': 'function', 'function': {'name': 'ask_user', 'arguments': ''}}]})
                for offset in range(0, len(arguments), 7):
                    send({'tool_calls': [{'index': 0, 'function': {'arguments': arguments[offset:offset + 7]}}]})
                send({}, 'tool_calls')
            self.wfile.write(b'data: [DONE]\n\n')
            return
        for part in ['<thi', 'nk>PRIVATE', '</th', 'ink>', '# SQLite\n', '\n```sql\nSELECT 1;\n```']:
            send({'content': part, 'reasoning_content': 'PRIVATE_FIELD'})
        if model in ('truncated', 'length'):
            if model == 'length':
                send({'content': '\n最后文字', 'tool_calls': [{'index': 0, 'id': 'incomplete', 'function': {'name': 'execute_query', 'arguments': '{'}}]}, 'length')
                self.wfile.write(b'data: [DONE]\n\n')
            return
        if model == 'tools':
            send({'tool_calls': [{'index': 0, 'id': 'question-1', 'type': 'function', 'function': {'name': 'ask_user', 'arguments': '{"question":"Which '}}]})
            send({'tool_calls': [{'index': 0, 'function': {'arguments': 'pagination?","options":["Offset","Cursor"]}'}}]}, 'tool_calls')
        else:
            send({}, 'stop')
        self.wfile.write(b'data: [DONE]\n\n')

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
