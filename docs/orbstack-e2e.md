# OrbStack PostgreSQL / MongoDB 功能验收

口径：PostgreSQL / MongoDB 功能场景覆盖率 ≥95%，经用户确认。每库 20 个真实驱动自动化场景和 4 个原生界面场景，共 48 项；未执行、失败、阻塞都不计入已通过覆盖。功能覆盖率 = 已执行且通过的不同场景 / 48。自动化驱动测试不等同于界面测试；代码行覆盖另报，不用测试文件覆盖率替代产品覆盖率。

范围：本机直连、密码认证的 PostgreSQL 和 MongoDB 独立实例，以及应用的连接、目录、数据浏览、查询和编辑功能。SQLite、远程 TLS/SRV、副本集管理、AI、发布不在该 48 项分母中，不能据此声称全应用功能覆盖率达到 95%。

## 数据与复现

运行 `python3 script/seed_orbstack.py`，然后运行 `script/test_orbstack.sh`。

- Docker context 显式为 `orbstack`；镜像使用本机 PostgreSQL `18.4-alpine3.23`、MongoDB `7.0`。
- 每库 10 个表／集合，每个 50,000 条，共 1,000,000 条仿真记录。
- 业务名称：customers、orders、products、payments、shipments、inventory、events、tickets、reviews、sessions。
- 数据包含随机状态、金额、时间、地区、嵌套 JSON、Unicode、空串、NULL、二进制、超过 JavaScript 安全整数范围的 int64；MongoDB 还含可选嵌套字段。
- 独立容器和命名卷，端口仅绑定 `127.0.0.1`。不会自动删除，重复运行已完成的 seed 只核验数量。
- 连接配置和随机密码：`.build/orbstack-e2e/connections.json`，文件权限 0600，Git 忽略。报告不得包含密码。
- 自动化增删改仅针对 customers 的 50001 号测试记录，成功结束后逐表精确复核每表仍为 50,000 行。测试中途失败时先检查该测试记录；不得盲目重复写入。

## 固定场景清单

以下编号分别加 `PG` 和 `MG` 前缀，各形成 20 项自动化场景。断言数量、表数量和重复运行次数不增加分母。

| 编号 | 场景与验收 |
| --- | --- |
| 01 | 正确凭据通过应用 DatabaseEngine 连接真实数据库 |
| 02 | 错误密码被拒绝，随后正确凭据恢复连接 |
| 03 | 目录恰好包含预期 10 个表／集合 |
| 04 | 全部 10 个表／集合各有 50,000 条记录 |
| 05 | 主键元数据；PG JSONB 元数据 / Mongo BSON int64、decimal、date、binary |
| 06 | 全部对象首页 200 行，ID 1–200，存在下一页 |
| 07 | 全部对象中间页 ID 24801–25000，存在下一页 |
| 08 | 全部对象末页 ID 49801–50000，无下一页 |
| 09 | 越界分页返回空结果且无下一页 |
| 10 | 降序浏览 ID 50000–49801 |
| 11 | 条件查询返回指定记录及正确 Unicode 名称 |
| 12 | 全量聚合 count=50000、sum(id)=1250025000 |
| 13 | 大查询显示 1000 行并标识尚有更多结果 |
| 14 | 空串、Unicode/引号、NULL 往返正确 |
| 15 | 参数绑定 / JSON 插入后真实读取 |
| 16 | 编辑保存后真实读取；Mongo int64 保真 |
| 17 | 过期编辑拒绝且保留已保存值 |
| 18 | 重复主键拒绝且不增加行数 |
| 19 | 删除新增测试行并核验已消失 |
| 20 | 无效命令失败后恢复浏览、断开和重连 |

原生界面各库再加 4 项，编号 `PGUI01–04`、`MGUI01–04`：

| 编号 | 场景与验收 |
| --- | --- |
| UI01 | 新建连接表单测试连接，发现 10 个表／集合 |
| UI02 | 保存并连接，侧栏目录和真实数据表格显示 |
| UI03 | 下一页与返回，页码及记录边界正确 |
| UI04 | 查询编辑器实际执行全表 count，显示 50000 |

原生界面用 CUA 操作与读取 AX/截图，结果单独写入本次报告；自动化脚本不会虚构 UI 通过结果。

## 本次执行结果（2026-09-06）

**48 / 48 项通过，固定功能场景清单覆盖率 100%，达成 ≥95% 目标。** 其中 40 项为应用真实 DatabaseEngine 到数据库的自动化测试，8 项为原生应用界面操作验收；没有跳过项。该百分比不代表整个应用代码行覆盖率。

| 数据库 | 服务端实际版本 | 本机地址 | 数据库 / 用户 | 数据量 |
| --- | --- | --- | --- | --- |
| PostgreSQL | 18.4 | `127.0.0.1:32844` | `tableviewer_test` / `postgres` | 10 × 50,000 行 |
| MongoDB | 7.0.40 | `127.0.0.1:32846` | `tableviewer_test` / `tableviewer`，authSource=`admin` | 10 × 50,000 文档 |

容器和命名卷保留，凭据已由应用存入钥匙串。TableViewer 侧栏连接名称为 **OrbStack PostgreSQL E2E** 和 **OrbStack MongoDB E2E**。测试后通过 PostgreSQL `count(*)`、MongoDB `countDocuments({})` 逐表复核，每个对象仍恰好有 50,000 条，总计 1,000,000 条。

界面验收使用本工作区构建并启动的 `.build/Xcode/Build/Products/Debug/TableViewer.app`：

- PostgreSQL：连接测试发现 10 张表；目录及首页显示 `customers-模拟-1`、200 条记录；下一页从 `customers-模拟-201` 开始，返回首页正确；SQL `SELECT COUNT(*) AS total FROM customers;` 显示 50000。重启本轮构建后再次验证已保存连接、认证测试及上述流程。
- MongoDB：连接测试发现 10 个集合；目录及首页显示真实数据；下一页、返回的记录边界同 PostgreSQL；`{"count":"customers"}` 返回 `n=50000`，`{"aggregate":"customers","pipeline":[{"$count":"total"}],"cursor":{}}` 在表格显示 50000。
- CUA 同时读取 AX 结果并检查两个数据库查询结果截图。界面操作未冒充可无人值守重放的自动化脚本。

独立的 LLVM 代码行覆盖：**DatabaseEngine.swift 69.11%（434 / 628）**。统计为 LLVM 报告中的映射行，包含本次未测试的 SQLite 路径和其他错误分支；没有宣称代码覆盖率达到 95%，没有使用测试文件本身的覆盖率替代产品代码覆盖。

本地原始证据（`.build/` 不提交，包含本机运行信息）：

- [固定场景执行结果与覆盖率](../.build/orbstack-e2e/functional-coverage.json)
- [自动化逐场景结果](../.build/orbstack-e2e/scenarios.json) 与 [原始输出](../.build/orbstack-e2e/test-output.log)
- [原生界面验收记录](../.build/orbstack-e2e/ui-scenarios.json)
- [运行环境与逐表精确计数](../.build/orbstack-e2e/environment.json)
- [代码行覆盖报告](../.build/orbstack-e2e/line-coverage.txt) 及同目录 `database.profraw`、`database.profdata`
- [应用构建日志](../.build/orbstack-e2e/build.log) 与 [启动验证](../.build/orbstack-e2e/launch.log)

环境处理：初始 MongoDB 8 镜像因当前 OrbStack Linux 内核兼容性错误退出，故使用已安装的 MongoDB 7.0 镜像完成测试；原失败容器保持停止状态，日志见 `.build/orbstack-e2e/mongo8-startup-failure.log`。Xcode 首次在文件沙箱内无法访问图标编译服务，获准使用主机构建服务后，构建及启动验证成功。未修改产品源码、既有安全措施或发布配置。
