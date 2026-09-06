# Keychain 拒绝读取导致闪退的修复与验证

日期：2026-09-06。修复起于恢复的 Agent 工作树（44c966b），现已安全整合到当前项目 `/Users/yuna/ToolsProject-Local/TableViewer`，保留完整 Agent、全局会话实现和原目录已有未提交改动。

**状态：当前项目已重新编译并重启，真实凭据读取取消后的恢复、重试连接和全局会话保留已通过原生界面验收。47 条 Keychain 回归、22 条 Agent 跨库/恢复回归、198 条 Agent 问答回归及 424 条双语文案检查通过。系统弹窗“拒绝”按钮未直接捕获，未授权状态由受控测试覆盖。**

## 根因与证据

已读取三份真实崩溃报告：

- `/Users/yuna/Library/Logs/DiagnosticReports/TableViewer-2026-09-06-165330.ips`：EXC_BREAKPOINT / SIGTRAP，`Index out of range`，`InspectorView.field(index:column:original:)` 文本 Binding getter，旧第 68 行。
- 同目录 `TableViewer-2026-09-06-165214.ips`：相同异常与文本 Binding getter 调用栈。
- 同目录 `TableViewer-2026-09-06-134206.ips`：相同数组越界，NULL Binding getter，旧第 76 行。

Keychain 读取错误本身已经被抛出。旧 `WorkspaceStore.connect` 在读取凭据前清空查询/终端状态，读取失败又进入数据库连接失败共用的 catch，断开旧驱动并清空 active/result/draft。SwiftUI 仍可持有上一条记录的 Binding，其 getter/setter 直接访问 `draft[index]`，从而越界；即使索引仍存在，也可能误写新行或其他表的草稿。

## 改动

1. 只整合原目录 `/Users/yuna/ToolsProject-Local/TableViewer` 已有、与本崩溃直接相关的 `fieldBinding` / `documentBinding` 和 InspectorView 修复。绑定捕获原连接、表和行，字段访问还检查数组范围及字段名；过期 getter 返回原记录值，setter 忽略过期、busy、只读、主键及 BLOB 写入。TextField、NULL、文档编辑器都使用受保护绑定，构建字段视图前检查 row.cells 与 draft 范围。
2. 在停止 shell、清空页面、重连数据库前完成凭据读取。拒绝、取消或其他凭据错误单独报告并返回，`defer` 释放 busy，保留旧驱动、事务、记录、查询、页面与 Agent 会话。用户可重试或选择其他数据库；成功重试清除旧错误。
3. 凭据读取成功后若数据库驱动连接失败，仍采用既有断开并清空不可用工作台的行为。没有把网络/驱动失败假装成“原数据库仍连接”。全局 Agent 历史和原连接归属仍保留。
4. 为 `WorkspaceStore` 增加默认使用 `ConnectionVault.read` 的凭据读取注入点，用受控错误验证拒绝路径。生产仍调用原有 SecItemCopyMatching；新增取消、未授权的中英文说明，其他错误保留状态码。

本次崩溃补丁没有改动 AgentLibrary、AgentToolExecutor 或批准/分享机制。整合回当前项目时保留原有 ReplicaSet、OrbStack、绑定保护和外观改动，没有覆盖或回退。没有删除钥匙串条目、更改 ACL、改变签名配置、禁止系统提示、硬编码真实 secret 或发送 MiniMax 请求。

## 验证

自动测试只覆盖本次连接错误、绑定安全和必要的 Agent 回归。自动测试中的数据库与历史文件使用临时独立 fixture；不读取真实凭据，不写用户配置或业务记录。下文原生界面验收另行使用应用正常连接流程。

| 检查 | 结果 |
| --- | --- |
| `./script/test_keychain_denial.sh` | **47 条通过**。[日志](../.build/keychain-validation/keychain-tests.log)。验证 errSecAuthFailed、errSecUserCanceled、errSecInteractionNotAllowed；旧连接、选中行、草稿、查询结果与历史、分页排序筛选、shell 状态、Agent 消息与待批准状态保留；busy 释放、重复读取可重试。 |
| 原驱动保留 | 在临时 SQLite 开启事务并写入未提交值；每次拒绝后仍能读取未提交值，证明原驱动没有被断开/重连。测试结束回滚。 |
| 保留的 inspector 绑定 | 验证文本/NULL/文档绑定，切行、字段重排、切表、宽表切窄表、空结果、暂时截短 draft、同一行 ID 下切换连接、busy/主键写入防护。异步驱动失败清空状态后访问旧绑定也不越界、不误写。 |
| 失败恢复及 Agent | 拒绝后切 B 正常，A 绑定与待批准操作不转绑 B，不附带 B schema；A 迟到工具结果仍留原会话且未自动分享。模拟凭据成功但 Mongo URI 解析失败，验证驱动错误清空与释放，随后可重连 A，未保存编辑仍在读凭据前阻止导航。固定无效 URI 只作本地解析失败 fixture，没有访问远程数据库。 |
| `./script/test_agent_workspace.sh` | **22 条通过**。[日志](../.build/keychain-validation/workspace-tests.log)。原有真实 SQLite A/B 异步归属、会话持久化、拒绝/等待批准/未分享状态、重启不重放等回归保持通过。 |
| `./script/test_agent.sh` | **198 条通过**。[日志](../.build/keychain-validation/agent-tests.log)。流式、停止保留、重试、结构化澄清、协议及会话保存等相关回归通过；仅使用本地 HTTP fixture。 |
| `python3 script/check_localizations.py` | **424 条双语文案通过**，英文与简体中文格式参数一致。 |
| `./script/build_and_run.sh --build` | macOS arm64 Debug 成功。[首次构建日志](../.build/keychain-validation/build.log)、[用户要求重启后的重新构建日志](../.build/keychain-validation/rebuild.log)。随后正常退出旧应用并启动当前项目产物。 |
| `git diff --check` | 通过。 |

## 当前项目实机验收

开发产物：[TableViewer.app](/Users/yuna/ToolsProject-Local/TableViewer/.build/Xcode/Build/Products/Debug/TableViewer.app)。本轮在当前项目重新构建，之后归档实施任务不会移除该源码或产物。

用户明确要求重新编译并重启后，完成正常退出和重新启动。进程路径核对为当前项目的上述产物，不再运行独立工作树中的旧版本。

1. Studio 显示 projects 表，选中 Aperture 行并展示六个字段。在侧栏切到 PostgreSQL E2E，应用收到真实凭据读取取消，显示“未能读取连接凭据，尚未切换数据库”和“已取消读取钥匙串凭据”，没有退出。[错误提示截图](../.build/keychain-validation/ui/01-keychain-cancelled.png)。
2. 关闭错误提示后，Studio 原行、六个字段和页面仍在，保存/撤销按钮均不可用，Agent 待处理数量保留。[恢复后页面](../.build/keychain-validation/ui/02-workspace-preserved.png)、[完整界面文本](../.build/keychain-validation/ui/02-workspace-preserved-ax.txt)。
3. 再次点击 PostgreSQL E2E，连接成功，显示合成 customers 测试数据；随后切回 Studio 也成功。[重试成功截图](../.build/keychain-validation/ui/03-retry-connected.png)、[完整界面文本](../.build/keychain-validation/ui/03-retry-connected-ax.txt)。本轮没有写入远程数据库或发送模型请求。
4. 打开“所有会话”，重启前四个会话和原数据库归属仍在，保留“等待你确认发送结果”状态，没有自动回传或重新执行。[全局历史截图](../.build/keychain-validation/ui/04-history-after-recovery.png)、[界面文本](../.build/keychain-validation/ui/04-history-after-recovery-ax.txt)。

实测边界：直接观察到的是生产 Keychain 读取返回取消后，应用错误提示及恢复行为；没有直接捕获或操作系统弹窗的“拒绝”按钮，不能将此表述为系统 errSecAuthFailed 的直接验收。errSecAuthFailed 和 errSecInteractionNotAllowed 的保留与恢复仍以受控错误测试为证。没有执行真实远程长查询、远程事务或运行中崩溃恢复实验。

源码、当前构建和本轮证据均保留在当前项目；独立实施任务可按用户要求归档，不影响运行中的当前项目应用。

改动文件：`TableViewer/Models/WorkspaceStore.swift`、`TableViewer/Views/InspectorView.swift`、`TableViewer/Services/ConnectionVault.swift`、`TableViewer/Resources/Localizable.xcstrings`；新增 `Tests/KeychainDenialTests.swift`、`script/test_keychain_denial.sh` 和本报告。源码保持未提交、可审查；未发布或推送。
