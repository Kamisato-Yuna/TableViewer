# MongoDB 三实例副本集 E2E

本轮范围：OrbStack 上三个独立 MongoDB 7.0 容器、独立数据卷、密码认证和节点间 keyfile 认证。复制上一轮单实例测试库的 10 个业务集合、500,000 个文档到 `tableviewer_replica_test`，原库保持不变。主机名采用 `localhost` 加三个不同端口；应用使用含三个种子的 `replicaSet=tableviewer_rs` URI 自动发现拓扑，不使用 directConnection 冒充故障切换。

这里采用 [OrbStack host networking](https://docs.orbstack.dev/docker/network)；mongod 仅绑定 `127.0.0.1`。host 网络用于让 macOS 与三个节点看到相同的 localhost 地址。它们是同一台主机上的进程级故障测试，不能证明跨主机容灾、网络分区、异地延迟或 TLS。

## 执行方式

1. 前置：已运行 `python3 script/seed_orbstack.py`，本机驱动和 Debug 应用已构建。
2. `python3 script/setup_replica.py` 创建并初始化副本集，复制仿真数据；已存在的环境只检查状态。
3. `script/test_replica.sh` 编译真实 DatabaseEngine 测试，使用由生产 Shell worker 代码编译的测试进程，执行下列 18 项场景。该脚本会终止并重启连接文件中列明的本轮测试节点。
4. TableViewer 原生界面另外验收连接、拓扑、主节点故障、恢复和终端。界面结果不会由脚本自动标记通过。

连接文件在 `.build/replica-e2e/connections.json`，权限 0600；认证 keyfile 也为 0600，均被 Git 忽略。容器及命名卷保留。增删改使用额外的 `replica_receipts` 集合，每次运行使用不同主键区分已确认写入，不修改业务集合。

## 自动化场景（固定 18 项）

| ID | 验收条件 |
| --- | --- |
| RS01 | 三种子 URI 连接并发现业务集合 |
| RS02 | 正确副本集名称，1 PRIMARY + 2 SECONDARY，全部健康，多数派 2，复制延迟有值 |
| RS03 | 每个节点均有 10 × 50,000 个业务文档，customers 的 sum(id)=1250025000 |
| RS04 | majority 插入获得确认，三个节点均可读取 |
| RS05 | majority 更新复制到三个节点 |
| RS06 | majority 删除复制到三个节点 |
| RS07 | 生产 Shell worker 读取 rs.status() 和 50000 文档计数；签名内嵌 helper 单独进行 UI05 验收 |
| RS08 | 主动 stepDown 后主节点变化且任期递增，等待同一连接 hello.isWritablePrimary=true |
| RS09 | 同一个 DatabaseEngine 不重连，继续 majority 写入并复制 |
| RS10 | 终止当前主节点后自动选主，状态显示故障节点且离线复制延迟为未知，仍可读取 50000 文档 |
| RS11 | 同一连接故障切换后 majority 写入成功，之前已确认写入仍存在 |
| RS12 | 旧主重启作为 SECONDARY 加入，追平故障期间写入 |
| RS13 | 从节点终止后仍可 majority 写入，拓扑准确标示异常 |
| RS14 | 从节点重启并追平，所有节点恢复健康 |
| RS15 | 停止两个节点，剩余节点失去可写主角色，写入错误可见 |
| RS16 | 恢复多数派后原连接恢复，失败请求未产生记录，新的 majority 写入成功 |
| RS17 | 原 Shell 会话在多次故障切换后继续查询 |
| RS18 | 三节点最终业务数据计数一致，所有阶段已确认写入均存在 |

驱动测试会在正常失败退出时恢复本轮已停止节点，再写出 `results.json`。如果进程被外部强制终止，请根据连接文件中的精确节点名称恢复容器，并核验健康状态。不会操作此前 PostgreSQL 或 MongoDB 单实例。

## 原生界面场景（固定 5 项）

- UI01：三种子连接表单测试并保存连接，显示真实业务数据。
- UI02：副本集视图显示三成员、1 主 2 从、健康、多数派和原始状态。
- UI03：当前主节点退出后，同一应用连接刷新发现新主节点和故障节点，查询仍可用。
- UI04：原节点恢复后，刷新显示 1 主 2 从全部在线，计数仍为 50000。
- UI05：应用终端执行副本集状态及集合计数。

## 本轮发现与修复

- 已修复 `ReplicaSnapshot.parse` 的离线延迟显示：离线节点的 optimeDate 为 Unix epoch 0 时，原界面显示约 17 亿秒复制延迟。现在仅在主节点与目标成员均健康且操作时间有效时计算延迟，其他情况显示未知（—）。RS02 覆盖离线及在线但无有效 optime 的回归，RS10 覆盖真实节点退出。
- 切换并非零中断：初轮 stepDown 后立即写入曾返回 `not primary`；最终验收先以只读 hello 检查原连接已找到可写主节点，再执行新的 majority 写入。没有加入透明写入重试，没有把失败写入直接重放。
- 已知显示限制：多种子 URI 的侧栏地址摘要退回 `MongoDB:27017`，而真实连接与副本集面板显示正确的三个端口。原因为连接表单用 URLComponents 解析多主机 URI 失败；本轮没有修改这个摘要逻辑。
- 初次 `.orb.local` 环境容器内健康，但 macOS 部分节点名解析到 198.18.*，实际握手失败。改用 localhost host 网络后验证通过，全局 DNS／代理未改动。原尝试的三个容器保持停止，故障证据保留。
- 签名 Shell helper 带 sandbox inherit，不能直接从普通命令行测试宿主启动；命令行测试使用生产 worker 源码，原生界面另外运行实际内嵌 helper。

切换测试使用原有 `mongoc_client_command_simple`，本轮没有改变其执行方式。[MongoDB C Driver 文档](https://mongoc.org/libmongoc/current/mongoc_client_command_simple.html)说明该接口不是可重试读取，并且不替调用者检查 write concern 错误；测试显式检查 `writeErrors` / `writeConcernError`。

## 执行结果（2026-09-06）

**18 项自动化 + 5 项原生界面验收通过，共 23 / 23 项。** 固定场景清单覆盖率 100%，不代表全应用代码行覆盖，也不包含跨主机容灾。已知侧栏摘要显示限制如上，未作为已修复问题。

副本集 `tableviewer_rs`，MongoDB **7.0.40**；数据库 `tableviewer_replica_test`，用户 `tableviewer`，authSource=`admin`。三节点均保留运行：

| 成员地址 | 容器 | 最终角色 |
| --- | --- | --- |
| localhost:63439 | tableviewer-rs-local-20260906-151208-0 | SECONDARY |
| localhost:63440 | tableviewer-rs-local-20260906-151208-1 | PRIMARY |
| localhost:63441 | tableviewer-rs-local-20260906-151208-2 | SECONDARY |

每个节点均再次逐集合精确核验 **10 × 50,000 = 500,000 文档**，三个副本一致；原单实例库没有改动。另保留 `replica_receipts` 集合作为各阶段 majority 写入证据。原 TableViewer 中已保存连接 **OrbStack MongoDB 三实例副本集**。

本轮测得的场景耗时（包括只读轮询、进程操作和校验；不是服务端选举时间或 SLA）：

| 场景 | 秒 |
| --- | ---: |
| stepDown 至原客户端确认可写新主（RS08） | 60.39 |
| 主节点退出至选主及查询恢复（RS10） | 10.92 |
| 旧主重启并追平（RS12） | 2.23 |
| 多数派恢复至连接恢复及写入核验（RS16） | 10.39 |

界面初验使用原 Debug 应用；检测到窗口有用户并发操作后，最终故障及修复复验使用同一构建的独立应用副本 `.build/replica-e2e/TableViewerReplicaE2E.app`，bundle ID 为 `local.yuna.TableViewer.ReplicaE2E`。App Sandbox 与内嵌 helper 保留，副本签名校验通过。UI 验证了旧主 63441 离线、新主 63440 接管、异常节点延迟显示“—”、降级期间查询 50000、重启后一主两从和真实内嵌 Shell 输出。没有用命令行测试代替界面结论。

原始证据（本机 `.build/` 下，不提交凭据和运行产物）：

- [自动化逐场景结果及阶段原始副本集状态](../.build/replica-e2e/results.json)
- [自动化日志](../.build/replica-e2e/test.log)
- [功能场景及 UI 验收结果](../.build/replica-e2e/acceptance.json)
- [最终三节点健康状态与逐集合计数](../.build/replica-e2e/final-verification.json)
- [修复后 UI 故障注入与恢复记录](../.build/replica-e2e/ui-failover-fixed.json)
- [构建日志](../.build/replica-e2e/build.log) / [启动验证](../.build/replica-e2e/launch.log)
- 初轮环境及断言失败日志保存在同目录 `test-orb-domain-failed.log`、`test-assertion-failed.log`、`test-sandbox-parent-failed.log`、`test-election-transition.log`；失败没有计入最终通过结果。

本轮产品代码修改仅限 `ReplicaSetModels.swift` 的健康与有效 optime 检查。未改动数据库连接、写入重试、安全措施、发布配置或用户已有修改；测试只覆盖本轮副本集功能及此显示修复。
