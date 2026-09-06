#!/usr/bin/env python3
"""Create isolated authenticated database containers and remove only those containers."""
import os
import pathlib
import secrets
import socket
import subprocess
import time

root = pathlib.Path(__file__).resolve().parent.parent
environment = os.environ.copy()
containers = []

def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, env=environment, **kwargs).strip()

def start(image, port, options):
    identifier = run('docker', 'run', '-d', '-p', f'127.0.0.1::{port}', *options, image)
    containers.append(identifier)
    host_port = run('docker', 'port', identifier, f'{port}/tcp').rsplit(':', 1)[1]
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        try:
            if image.startswith('mongo:') and 'MongoDB init process complete' not in run('docker', 'logs', identifier, stderr=subprocess.DEVNULL):
                time.sleep(1)
                continue
            with socket.create_connection(('127.0.0.1', int(host_port)), timeout=1):
                return host_port
        except OSError:
            time.sleep(1)
    raise RuntimeError(f'{image} did not become ready')

try:
    environment['POSTGRES_PASSWORD'] = secrets.token_hex(20)
    environment['MONGO_INITDB_ROOT_PASSWORD'] = secrets.token_hex(20)
    environment['TABLEVIEWER_TEST_PG_PASSWORD'] = environment['POSTGRES_PASSWORD']
    environment['TABLEVIEWER_TEST_MONGO_PASSWORD'] = environment['MONGO_INITDB_ROOT_PASSWORD']
    environment['TABLEVIEWER_TEST_PG_PORT'] = start('postgres:18.4-alpine3.23', 5432, ['-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_DB=tableviewer_test'])
    environment['TABLEVIEWER_TEST_MONGO_PORT'] = start('mongo:7.0', 27017, ['-e', 'MONGO_INITDB_ROOT_PASSWORD', '-e', 'MONGO_INITDB_ROOT_USERNAME=tableviewer'])
    subprocess.run([str(root / 'script/test_databases.sh')], cwd=root, env=environment, check=True)
finally:
    for identifier in reversed(containers):
        subprocess.run(['docker', 'rm', '-fv', identifier], check=True, stdout=subprocess.DEVNULL)
