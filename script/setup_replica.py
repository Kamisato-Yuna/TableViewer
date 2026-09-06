#!/usr/bin/env python3
"""OrbStack 三节点认证副本集，保留实例与卷，仅读取上一轮单实例 fixture。"""
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.build/replica-e2e'
STATE = OUT / 'connections.json'

def docker(*args, **kw):
    return subprocess.check_output(['docker','--context','orbstack',*args],text=True,**kw).strip()

def js(s, index, code):
    prefix='const c=new Mongo("mongodb://tableviewer:"+process.env.RS_PASSWORD+"@127.0.0.1:'+s['ports'][index]+'/?directConnection=true&authSource=admin");const db=c.getDB("admin");\n'
    return docker('exec','-i','-e','RS_PASSWORD',s['nodes'][index],'mongosh','--quiet','--nodb','--file','/dev/stdin',input=prefix+code,env=os.environ|{'RS_PASSWORD':s['password']},stderr=subprocess.PIPE)

def wait_for(action, limit=90):
    deadline=time.monotonic()+limit
    last=None
    while time.monotonic()<deadline:
        try:
            result=action()
            if result: return result
        except (subprocess.CalledProcessError,ValueError,OSError) as error:
            last=str(error)
        time.sleep(1)
    raise RuntimeError('等待超时: '+str(last))

def status(s):
    for i in range(3):
        try:
            value=json.loads(js(s,i,'print(JSON.stringify(db.adminCommand({replSetGetStatus:1})));'))
            if value.get('myState')==1: return value
        except subprocess.CalledProcessError: pass
    return None

def healthy(s):
    v=status(s)
    return v if v and len(v.get('members',[]))==3 and sum(m['stateStr']=='PRIMARY' for m in v['members'])==1 and sum(m['stateStr']=='SECONDARY' for m in v['members'])==2 and all(m['health']==1 for m in v['members']) else None

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    if STATE.exists():
        s=json.loads(STATE.read_text())
        print(json.dumps({'nodes':s['nodes'],'healthy':bool(healthy(s))},ensure_ascii=False))
        return
    suffix=time.strftime('%Y%m%d-%H%M%S')
    s={'set':'tableviewer_rs','database':'tableviewer_replica_test','password':secrets.token_hex(20),
       'nodes':['tableviewer-rs-local-'+suffix+'-'+str(i) for i in range(3)]}
    s['ports']=[]
    reservations=[]
    for _ in range(3):
        sock=socket.socket();sock.bind(('127.0.0.1',0));reservations.append(sock)
        s['ports'].append(str(sock.getsockname()[1]))
    s['hosts']=['localhost:'+port for port in s['ports']]
    for sock in reservations: sock.close()
    with open(STATE,'x',opener=lambda p,f:os.open(p,f,0o600)) as f: json.dump(s,f,indent=2)
    key=OUT/'keyfile'
    with open(key,'x',opener=lambda p,f:os.open(p,f,0o600)) as f: f.write(secrets.token_urlsafe(500).replace('-','A').replace('_','B'))
    for i,node in enumerate(s['nodes']):
        docker('run','-d','--name',node,'--label','app=tableviewer-replica-e2e',
               '--network','host','-v',node+':/data/db','-v',str(key)+':/run/rs-keyfile:ro',
               '-e','MONGO_INITDB_ROOT_PASSWORD','-e','MONGO_INITDB_ROOT_USERNAME=tableviewer',
               '--entrypoint','bash','mongo:7.0','-c',
               'cp /run/rs-keyfile /tmp/rs-keyfile && chmod 400 /tmp/rs-keyfile && chown mongodb:mongodb /tmp/rs-keyfile && exec docker-entrypoint.sh mongod --replSet tableviewer_rs --keyFile /tmp/rs-keyfile --bind_ip 127.0.0.1 --port '+s['ports'][i],
               env=os.environ|{'MONGO_INITDB_ROOT_PASSWORD':s['password']})
        wait_for(lambda: 'init process complete' in docker('logs',node,stderr=subprocess.DEVNULL) and js(s,i,'print(db.adminCommand({ping:1}).ok);')=='1')
        print('创建 '+node,flush=True)
    STATE.write_text(json.dumps(s,indent=2))
    for i in range(3):
        wait_for(lambda: 'init process complete' in docker('logs',s['nodes'][i],stderr=subprocess.DEVNULL) and js(s,i,'print(db.adminCommand({ping:1}).ok);')=='1')
        host=s['hosts'][i].rsplit(':',1)[0]
        with socket.create_connection((host,int(s['ports'][i])),timeout=5): pass
        print('主机可达 '+s['hosts'][i],flush=True)
    config={'_id':s['set'],'members':[{'_id':i,'host':h,'priority':1} for i,h in enumerate(s['hosts'])]}
    print(js(s,0,'print(JSON.stringify(rs.initiate('+json.dumps(config)+')));'),flush=True)
    snapshot=wait_for(lambda:healthy(s))
    (OUT/'initial-status.json').write_text(json.dumps(snapshot,indent=2))
    # 只读取此前已建立的单实例测试库，复制到副本集独立命名空间。
    source=json.loads((ROOT/'.build/orbstack-e2e/connections.json').read_text())
    archive=OUT/'fixture.archive'
    with archive.open('wb') as f:
        subprocess.run(['docker','--context','orbstack','exec','-e','SOURCE_PASSWORD',source['mongo_container'],
            'bash','-c','exec mongodump --uri="mongodb://tableviewer:$SOURCE_PASSWORD@127.0.0.1/?authSource=admin" --db=tableviewer_test --archive'],
            env=os.environ|{'SOURCE_PASSWORD':source['mongo_password']},stdout=f,stderr=(OUT/'dump.log').open('w'),check=True)
    primary=next(m['name'] for m in snapshot['members'] if m['stateStr']=='PRIMARY')
    idx=s['hosts'].index(primary)
    with archive.open('rb') as f, (OUT/'restore.log').open('w') as log:
        subprocess.run(['docker','--context','orbstack','exec','-i','-e','RS_PASSWORD',s['nodes'][idx],
            'bash','-c','exec mongorestore --uri="mongodb://tableviewer:$RS_PASSWORD@127.0.0.1:'+s['ports'][idx]+'/?authSource=admin" --archive --nsFrom="tableviewer_test.*" --nsTo="tableviewer_replica_test.*"'],
            env=os.environ|{'RS_PASSWORD':s['password']},stdin=f,stdout=log,stderr=log,check=True)
    wait_for(lambda:healthy(s))
    s['seeded']=True
    STATE.write_text(json.dumps(s,indent=2))
    print('三节点副本集就绪，已复制 10 个集合 / 500,000 文档。',flush=True)

if __name__=='__main__': main()
