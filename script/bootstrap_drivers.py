#!/usr/bin/env python3
"""Prepare native drivers locally; never installs or changes Homebrew packages."""
import json
import pathlib
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / '.build'
MONGO_VERSION = '2.5.2'
MONGO = BUILD / 'drivers' / 'mongo-c-driver' / MONGO_VERSION

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def prepare():
    prefix = pathlib.Path(run('brew', '--prefix'))
    if not MONGO.exists():
        info = json.loads(run('brew', 'info', '--json=v2', 'mongo-c-driver'))['formulae'][0]
        if info['versions']['stable'] != MONGO_VERSION:
            raise SystemExit('MongoDB bottle version changed. Update MONGO_VERSION and header paths together.')
        bottle = info['bottle']['stable']['files']['arm64_tahoe']['url']
        token = json.load(urllib.request.urlopen('https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/mongo-c-driver:pull'))['token']
        request = urllib.request.Request(bottle, headers={'Authorization': 'Bearer ' + token})
        archive = BUILD / 'drivers' / 'mongo.tar.gz'
        archive.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(request) as response, archive.open('wb') as stream:
            shutil.copyfileobj(response, stream)
        with tarfile.open(archive) as source:
            source.extractall(archive.parent, filter='data')
    include = BUILD / 'include'
    include.mkdir(parents=True, exist_ok=True)
    for source in (MONGO / 'include' / ('mongoc-' + MONGO_VERSION), MONGO / 'include' / ('bson-' + MONGO_VERSION)):
        shutil.copytree(source, include, dirs_exist_ok=True)
    pq = pathlib.Path(run('brew', '--prefix', 'libpq'))
    shutil.copytree(pq / 'include', include / 'postgresql', dirs_exist_ok=True)
    lib = BUILD / 'lib'
    lib.mkdir(parents=True, exist_ok=True)
    copied = set()

    def library(source):
        name = source.name
        if name in copied:
            return
        copied.add(name)
        target = lib / name
        shutil.copy2(source.resolve(), target)
        target.chmod(0o755)
        subprocess.run(['codesign', '--remove-signature', str(target)], capture_output=True)
        subprocess.check_call(['install_name_tool', '-id', '@rpath/' + name, str(target)])
        for line in run('otool', '-L', str(source)).splitlines()[2:]:
            dependency = line.strip().split(' (')[0]
            if dependency.startswith('/System/') or dependency.startswith('/usr/lib/'):
                continue
            if dependency.startswith('@rpath/'):
                resolved = MONGO / 'lib' / pathlib.Path(dependency).name
            else:
                resolved = pathlib.Path(dependency.replace('@@HOMEBREW_PREFIX@@', str(prefix)))
            library(resolved)
            subprocess.check_call(['install_name_tool', '-change', dependency, '@rpath/' + resolved.name, str(target)])
        subprocess.check_call(['codesign', '--force', '--sign', '-', str(target)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    library(pq / 'lib' / 'libpq.5.dylib')
    library(MONGO / 'lib' / 'libmongoc2.2.dylib')
    library(MONGO / 'lib' / 'libbson2.2.dylib')
    for short, name in [('libpq.dylib', 'libpq.5.dylib'), ('libmongoc2.dylib', 'libmongoc2.2.dylib'), ('libbson2.dylib', 'libbson2.2.dylib')]:
        link = lib / short
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to(name)
    print('Native drivers ready:', ', '.join(sorted(copied)))

if __name__ == '__main__':
    prepare()
