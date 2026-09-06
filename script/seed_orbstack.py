#!/usr/bin/env python3
"""创建并保留本机 OrbStack 仿真数据库；重复执行只校验已有数据，不覆盖。"""
import json
import os
from pathlib import Path
import secrets
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.build/orbstack-e2e'
STATE = OUT / 'connections.json'
TABLES = ['customers', 'orders', 'products', 'payments', 'shipments',
          'inventory', 'events', 'tickets', 'reviews', 'sessions']


def docker(*args, **kwargs):
    return subprocess.check_output(['docker', '--context', 'orbstack', *args],
                                   text=True, **kwargs).strip()


def pg(state, sql):
    return docker('exec', '-i', state['pg_container'], 'psql', '-U', 'postgres',
                  '-d', 'tableviewer_test', '-v', 'ON_ERROR_STOP=1', '-At', input=sql)


def mongo(state, js):
    env = os.environ | {'MONGO_TEST_PASSWORD': state['mongo_password']}
    return docker('exec', '-i', '-e', 'MONGO_TEST_PASSWORD', state['mongo_container'],
                  'mongosh', '--quiet', '--nodb', '--file', '/dev/stdin', env=env,
                  input='const c = new Mongo("mongodb://tableviewer:" + process.env.MONGO_TEST_PASSWORD + "@127.0.0.1/?authSource=admin"); const db = c.getDB("tableviewer_test");\n' + js)


def verify(state):
    counts = {'postgresql': {}, 'mongodb': {}}
    for table in TABLES:
        counts['postgresql'][table] = int(pg(state, f'SELECT count(*) FROM "{table}";'))
    counts['mongodb'] = json.loads(mongo(state, 'print(JSON.stringify(Object.fromEntries(' +
        json.dumps(TABLES) + '.map(n => [n, db.getCollection(n).countDocuments({})]))));'))
    assert all(n == 50000 for database in counts.values() for n in database.values()), counts
    assert int(pg(state, "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")) == 10
    assert int(mongo(state, 'print(db.getCollectionNames().length);')) == 10
    (OUT / 'row-counts.json').write_text(json.dumps(counts, indent=2) + '\n')
    print('已验证 PostgreSQL 10 × 50,000 行；MongoDB 10 × 50,000 文档。', flush=True)
    return counts


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if STATE.exists():
        state = json.loads(STATE.read_text())
        if state.get('seeded'):
            verify(state)
            return
        seed(state)
        return
    suffix = time.strftime('%Y%m%d-%H%M%S')
    state = {'pg_container': 'tableviewer-e2e-pg-' + suffix,
             'mongo_container': 'tableviewer-e2e-mongo-' + suffix,
             'pg_password': secrets.token_hex(20), 'mongo_password': secrets.token_hex(20),
             'database': 'tableviewer_test', 'tables': TABLES, 'rows_per_table': 50000}
    env = os.environ | {'POSTGRES_PASSWORD': state['pg_password'],
                        'MONGO_INITDB_ROOT_PASSWORD': state['mongo_password']}
    # 独立命名卷；不清理其他容器或数据。失败时保留资源便于诊断。
    docker('run', '-d', '--name', state['pg_container'], '--label', 'app=tableviewer-e2e',
           '-p', '127.0.0.1::5432', '-v', state['pg_container'] + ':/var/lib/postgresql',
           '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_DB=tableviewer_test',
           'postgres:18.4-alpine3.23', env=env)
    docker('run', '-d', '--name', state['mongo_container'], '--label', 'app=tableviewer-e2e',
           '-p', '127.0.0.1::27017', '-v', state['mongo_container'] + ':/data/db',
           '-e', 'MONGO_INITDB_ROOT_PASSWORD', '-e', 'MONGO_INITDB_ROOT_USERNAME=tableviewer',
           'mongo:7.0', env=env)
    state['pg_port'] = docker('port', state['pg_container'], '5432/tcp').rsplit(':', 1)[1]
    state['mongo_port'] = docker('port', state['mongo_container'], '27017/tcp').rsplit(':', 1)[1]
    with open(STATE, 'x', opener=lambda p, f: os.open(p, f, 0o600)) as stream:
        json.dump(state, stream, indent=2)
    seed(state)


def seed(state):
    for _ in range(90):
        try:
            if 'init process complete' not in docker('logs', state['mongo_container'], stderr=subprocess.DEVNULL):
                time.sleep(1)
                continue
            pg(state, 'SELECT 1;')
            mongo(state, 'print(db.runCommand({ping:1}).ok);')
            break
        except subprocess.CalledProcessError:
            time.sleep(1)
    else:
        raise RuntimeError('数据库未在 90 秒内就绪；保留容器和连接文件供诊断。')
    for table in TABLES:
        pg(state, f'''BEGIN;
CREATE TABLE "{table}" (id integer PRIMARY KEY, name text NOT NULL, status text NOT NULL,
 amount numeric(12,2), enabled boolean, created_at timestamptz,
 metadata jsonb, note text, payload bytea, external_id bigint);
INSERT INTO "{table}"
SELECT i, '{table}-模拟-' || i, (ARRAY['pending','active','complete','cancelled'])[1+floor(random()*4)::int],
 round((random()*10000)::numeric,2), random()>0.3,
 now() - random()*interval '365 days',
 jsonb_build_object('region',(ARRAY['上海','北京','深圳'])[1+floor(random()*3)::int], 'tags',jsonb_build_array('仿真','{table}'), 'score',floor(random()*100)),
 CASE WHEN i%3=0 THEN NULL WHEN i%3=1 THEN '' ELSE 'O''Reilly · 测试 ✓' END,
 decode(lpad(to_hex(i),8,'0'),'hex'), 9007199254740991::bigint+i
FROM generate_series(1,50000) i;
COMMIT;
ANALYZE "{table}";''')
        print('PostgreSQL: ' + table + ' 50,000', flush=True)
    mongo(state, '''
for (const name of ''' + json.dumps(TABLES) + ''') {
  const col = db.getCollection(name);
  col.createIndex({id:1}, {unique:true});
  for (let start=1; start<=50000; start+=1000) {
    const docs=[];
    for (let i=start; i<start+1000; i++) {
      const doc={_id:i,id:i,name:name+'-模拟-'+i,
        status:['pending','active','complete','cancelled'][Math.floor(Math.random()*4)],
        amount:Decimal128((Math.random()*10000).toFixed(2)),enabled:Math.random()>0.3,
        created_at:new Date(Date.now()-Math.random()*365*86400000),
        metadata:{region:['上海','北京','深圳'][Math.floor(Math.random()*3)],tags:['仿真',name],score:Math.floor(Math.random()*100)},
        note:i%3===0?null:i%3===1?'':"O'Reilly · 测试 ✓",
        payload:BinData(0,'AAH/'),external_id:Long('9007199254740991').add(i)};
      if (i%7===0) doc.optional={nested:[1,true,null,'中文']};
      docs.push(doc);
    }
    col.insertMany(docs);
  }
  print('MongoDB: '+name+' 50,000');
}
''')
    verify(state)
    state['seeded'] = True
    STATE.write_text(json.dumps(state, indent=2))
    print('连接信息保存在 ' + str(STATE) + '（权限 0600，Git 忽略）。')


if __name__ == '__main__':
    main()
