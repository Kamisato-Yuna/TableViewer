# Agent 示例与选项调用深入验收

日期：2026-09-06。当前项目已构建并重启最终修复版。选项误判已在原会话恢复，查看表数据、分页查询及索引查询的操作流程已完成真实 MiniMax 验证；最终版本的分页文案复核与索引只读查询计划验证均已完成。

## 已确认的问题与改动

### 五个表选项被误判

截图中的失败调用在原历史中保留了问题“请选择你想查看的表”和五个有效选项：`active_projects - 活跃项目`、`activity - 活动记录`、`members - 成员信息`、`notes - 笔记`、`projects - 项目`。旧版解析器、工具 schema 和提示限制最多三项，导致正常的五表选择变成“澄清问题格式无效”。

- 保持简短提问建议，选择具体对象时允许最多十二个选项，工具 schema 与本地解析一致。
- 缺省或 null 的 options 支持自由回答；空白项和重复项规范化。错误类型、超长文字及超过十二项仍保留校验并显示具体原因。
- 已保存但尚未发送的有效问题可点击“恢复问题选项”，直接恢复原选项；没有重新调用模型、改写已发送结果或执行数据库操作。
- 真正无效的问题显示“问题需要重试”。单独一个失败问题可以点击“让模型重新提问”；存在其他未发送操作结果时，不通过该入口附带发送这些结果。

### 示例分析的两处误导

深入跑通示例后，还观察到模型把 SQLite 未列出独立索引解释为可能缺少主键索引，以及把第二页返回两行写成整表只有两行。

- `inspect_schema` 在已有元数据上补充字段 `primaryKey` 和对象 `isView`，不额外读取记录。
- SQLite 上下文说明 INTEGER PRIMARY KEY 通常为 rowid 别名、视图没有独立索引；需要查询计划才能判断具体查询使用什么索引，索引列表不能证明使用率。对应 SQLite 官方的 [查询规划说明](https://www.sqlite.org/queryplanner.html) 与 [EXPLAIN QUERY PLAN](https://www.sqlite.org/eqp.html)。
- 上下文明确 rows 只是本次查询返回值，LIMIT/OFFSET 结果不能直接当作全表总量；确认总量须有实际统计证据。

上述提示是减少已观察误判的改进，不能保证模型每次都给出正确的 SQL 或分析。最终文案复测的状态见下文。

## 自动检查

测试只覆盖本轮问题恢复、工具交互、元数据及必要的 Agent/跨库回归。

| 检查 | 结果 |
| --- | --- |
| `./script/test_agent.sh` | **246 项通过**。[日志](../.build/agent-scenario-validation/tests.log)。包含五项/十二项、自由回答、无效格式、历史恢复、已发送结果不改写、分片 HTTP 工具参数、重新提问、连续回答及不自动执行。 |
| `./script/test_agent_workspace.sh` | **24 项通过**。[日志](../.build/agent-scenario-validation/workspace-tests.log)。包含真实临时 SQLite 主键元数据，以及 index_list 为空但查询计划仍使用 INTEGER PRIMARY KEY 的实例。原跨库归属、迟到结果、批准、草稿和重启回归通过。 |
| 本地 HTTP 失败恢复 | 模拟无效选项类型→只发送该失败工具结果→模型返回五选项→确认并回传答案→正常完成；没有追加重复用户消息或附带其他操作结果。 |
| `python3 script/check_localizations.py` | **437 条双语文案通过**。 |
| `./script/build_and_run.sh --build` | macOS arm64 Debug 构建成功。[日志](../.build/agent-scenario-validation/build.log)。 |
| `git diff --check` | 通过。 |

## 真实应用案例

使用当前项目构建、应用既有 `MiniMax-M2.7 / api.minimax.cn` 和 Studio 自带合成示例。没有读取或输出密钥，没有修改连接配置，没有对数据库执行写入。发送的数据限于示例结构、索引元数据、统计及已核对的自带 projects 示例记录，没有发送用户其他数据库记录。

| 案例 | 操作与结果 |
| --- | --- |
| 原“帮我了解当前数据库”→“查看某个表的数据” | 在原会话恢复五选项，选择 projects 并确认回传；模型提出 `SELECT * FROM projects LIMIT 20`。单独批准后返回十二条原生示例记录，再确认回传并得到结果表格。[恢复五选项](../.build/agent-scenario-validation/01-original-question-restored.png)、[完整选项文本](../.build/agent-scenario-validation/01-original-question-restored-ax.txt)、[本机查询结果](../.build/agent-scenario-validation/03-projects-query-local-ax.txt)。 |
| “写一个分页查询”欢迎入口 | 点击原按钮并发送原提示；批准结构检查后连续回答“projects 每页十条，id 降序”和“第二页”。模型提出 `SELECT * FROM projects ORDER BY id DESC LIMIT 10 OFFSET 10;`，单独批准后准确返回 id 2、1 两条记录，回传后完成。[结果](../.build/agent-scenario-validation/04-pagination-two-questions-result-ax.txt)、[首轮完成截图](../.build/agent-scenario-validation/05-pagination-complete.png)。首轮文案错误地将这两行称为整表总量，故增加上文改进并发起最终复核。 |
| “检查索引使用情况”欢迎入口 | 点击原按钮并发送原提示，结构检查成功。模型首条复杂元数据 SQL 返回 `near "AS": syntax error`，应用保留错误并允许回传。模型随后改用五条 `PRAGMA index_list`，逐条批准后全部成功；追加 COUNT 联合查询及 members 字段元数据查询成功，最后生成报告。未批准或执行任何 CREATE INDEX。首轮主键分析存在上述误导，已补充元数据与上下文。[真实 SQL 错误与恢复起点](../.build/agent-scenario-validation/02-index-query-model-error-ax.txt)。 |

三个流程均保持独立历史，切换应用会话不会使后台进度或待批准项丢失。完成这些操作后，只剩本轮之前已有的一条待处理会话。

## 最终文案复核状态

在最终构建的保留会话中发送“请复核上面的结论，只保留实际查询支持的内容，并指出尚未验证的部分。不要进行写入；先用简短说明回答。”，确认完整答复与结束状态。

- 分页复核明确撤回“该表目前仅有 2 条记录”，指出 `LIMIT 10 OFFSET 10` 只证明本次返回两行，没有 COUNT 证据不能推断全表总量。[最终答复](../.build/agent-scenario-validation/07-pagination-review-ax.txt)、[截图](../.build/agent-scenario-validation/07-pagination-review.png)。
- 索引第一轮复核补充 INTEGER PRIMARY KEY 不出现在 `index_list` 并不代表缺少索引，承认建索引建议未经具体查询验证。不过摘要仍把空列表简称“无索引”，不能将这段文案当作完整、准确的最终报告。[第一轮复核](../.build/agent-scenario-validation/08-index-review-ax.txt)。
- 因此继续提出具体只读检查，逐条批准 `PRAGMA table_info('projects')`、查询 `sqlite_master` 的对象类型，以及 `EXPLAIN QUERY PLAN SELECT * FROM projects WHERE id = 1`。实际结果分别为 `id / INTEGER / pk=1`、`active_projects / view`、`SEARCH projects USING INTEGER PRIMARY KEY (rowid=?)`。核对后才回传给 MiniMax，最终答复确认主键存在、对象为视图，并区分索引列表和这个查询实际采用的主键查找。[最终结果与答复](../.build/agent-scenario-validation/10-index-plan-complete-ax.txt)、[截图](../.build/agent-scenario-validation/10-index-plan-complete.png)。

本次验证证明修复后的选项流程、错误恢复以及上述具体复核能够完成；追加上下文和提示不能保证未来每次模型输出都正确。最终索引回复的三项实测结论正确，但概念比较表仍将 `index_list` 简称为“仅列出显式创建的索引”，这不够准确：它也会列出 UNIQUE 等约束产生的独立索引，本会话的 members 自动索引就是实例。因此没有将模型整段报告标记为完全正确。索引结论仅覆盖实际检查的查询计划，不代表持续运行的索引使用率统计。未执行写入或新增索引，也未处理原先其他会话的待批准操作。

所有源码仍未提交，可审查；未发布或推送。实机截图和日志存于当前项目的 `.build/agent-scenario-validation`，该目录被 Git 忽略。
