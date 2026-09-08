# MongoDB 执行前估算命令修复

2026-09-08。

## 原因与改动

`mongoCommand` 已保证外层命令名为第一个 BSON 字段，但 explain 内层仍由
`jsonText` 的 `sortedKeys` 序列化，产生 `filter` 在 `find` 前面的命令，
MongoDB 因此返回 `Explain failed due to unknown command: filter`。

估算入口现显式传递内层命令名 `find`，发送时将其放在内层文档首位。
其他普通 JSON 文档序列化不变，保留 queryPlanner 模式和扫描风险提示。
参见 [MongoDB explain 文档](https://www.mongodb.com/docs/manual/reference/command/explain/)。

## 定向验证

```sh
TV040_MONGO_PORT=<专用 acceptance040 实例端口> ./script/test_workbench040.sh --mongo-estimates-only
./script/build_and_run.sh --build
```

实际使用本机专用 acceptance040 MongoDB 实例执行，临时集合在测试后删除。
六项检查通过：全表查询取得 COLLSCAN、索引筛选和排序取得 IXSCAN，
两个响应均有 queryPlanner 且没有 executionStats，扫描告警保留，文档数量不变。
Debug 应用构建通过，`git diff --check` 通过。

原生界面复验尚未完成：重启后点击现有 MongoDB E2E 连接，主线程阻塞在
`ConnectionVault.readKeychain` → `SecItemCopyMatching`，等待系统凭据访问授权。
不能将驱动测试视为该次界面验收。未修改 Keychain 权限或替换系统安装版。
