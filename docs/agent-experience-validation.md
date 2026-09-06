# Agent 问答与全局会话验证

日期：2026-09-06。工作树：`/Users/yuna/.codex/worktrees/c76f/TableViewer`；起点：`435a81c`。

本轮实现、定向测试、macOS 开发构建及真实 MiniMax / 原生界面主要流程已完成。下文区分实际窗口证据、可控测试及未覆盖边界。代码未提交、未推送、未发布。

## 范围与实现

依据父任务的 [原始审计](/private/tmp/tableviewer-agent-audit-20260906/audit.md) 修复 Agent 问答，并按追加范围实现独立于当前数据库的全局会话管理。仅在本工作树修改 Agent 及直接调用处；原目录 `/Users/yuna/ToolsProject-Local/TableViewer` 的未提交数据库、ReplicaSet、OrbStack 工作未混入本次改动。原目录仅只读检查及复制被忽略的本地构建依赖。

- 回复按标题、段落、列表、引用和代码块排版，支持整条回复和代码复制。代码块保留换行、语言提示和水平滚动。行内 Markdown 使用系统 AttributedString；表格等未实现的高级 Markdown 仍以文字显示。
- 协议层忽略独立 reasoning 字段，并过滤正文中的 think 标签及转义形式；跨 chunk 前缀先暂存，未闭合思考段不会闪入正文。沿用既有响应大小、URL 和凭据脱敏措施。
- 固定消息 ID 保留停止、失败和退出前的部分正文。请求序号隔离迟到结果；重新生成替换原回复并复用请求快照；继续回复明确追加一轮；生成中补充明确停止旧请求再携带可见历史请求。
- 原生 NSTextView 在生成和等待批准时仍可写草稿；Return 换行、⌘Return 发送，组合态不发送。滚动在跟随状态下追随正文，上滚阅读时提供“回到底部”；停止不删除回复，也不主动把阅读位置拉到底部。
- 工具卡片保留在原 assistant 消息内，记录批准、执行、完成、失败、拒绝和是否分享。每次执行独立批准，结果另行批准回传；拒绝不呈现为成功。轻量 ask_user 支持短问题、选项及自由回答，回答先保存在本机。
- `AgentLibrary` 全局拥有多个会话，侧栏和工具栏均可进入历史。支持新建、切换、重命名、标题或数据库搜索、归档和恢复；没有当前连接时仍能查看历史。切换和删除连接不再 reset 会话；归档不取消正在进行的任务。
- 每个会话保留最初的数据库 ID、名称与类型。请求、批准、澄清、草稿和异步结果均绑定原会话。当前连接为 B 时，A 会话不能附带 B 的结构或批准到 B 执行。原连接已删除时显示不可用提示，保留历史。
- `AgentToolExecutor` 为会话维护独立数据库驱动连接，执行前捕获原连接与所选对象；导航不会重连这条驱动连接，也不会用结果覆盖当前数据库工作台。界面明确提示不继承查询工作台事务；原有未保存编辑保护保留。
- 消息、部分回复、操作状态、回答草稿、分享标记、标题和归档状态保存为本机 `LocalWorkspace.directory/agent-conversations.json`。沿用原子文件写入，文件权限 0600；不序列化 ConnectionProfile、数据库 URI、密码或 API Key。用户自行输入的对话和已批准的结果属于会话正文，会按预期留在本机。
- 重启将生成状态恢复为“已中断”，执行状态恢复为“结果待核实”，不自动请求、重放数据库操作或分享结果。读取失败保留原文件并显示错误。API 配置变更后，历史保留，旧会话不能自动使用新配置发送历史。

## 自动验证

测试只覆盖本轮 Agent 改动，没有扩展到原目录的数据库可靠性验收。

| 检查 | 结果 |
| --- | --- |
| `./script/test_agent.sh` | **198 条检查通过**。含全部 think 分片边界、Markdown、原生输入组件、停止/重试/继续/补充、迟到输出、一次执行、拒绝、重复 provider ID、澄清、分享状态及本地序列化。[日志](../.build/agent-validation/tests.log) |
| 实际 URLSession + 本地 HTTP fixture | 测试 JSON/SSE、分片工具参数、提前 EOF、length 结尾正文、不完整工具拒绝、401 凭据脱敏。仅绑定 127.0.0.1，使用固定测试 key；测试结束关闭 fixture。这部分不能算作 MiniMax 证据。 |
| `./script/test_agent_workspace.sh` | **22 条检查通过**。使用临时 SQLite A/B 和受控异步时序，实际执行 A 的查询后结果只回到 A；验证 B 的结构、查询结果和选中会话不受污染。覆盖连接切换、删除、生成中归档、恢复、未分享结果、拒绝、等待批准、回答草稿、异常读取保护和原有未保存编辑保护。[日志](../.build/agent-validation/workspace-tests.log) |
| 重启状态测试 | 将真实序列化快照重新加载，验证生成变 interrupted、执行变 uncertain、消息 ID 与分享标记保留、不能重复执行。执行时序使用可控挂起，不宣称是进程崩溃中的远程数据库验收。 |
| `./script/build_and_run.sh --build` | macOS arm64 Debug 构建通过；[日志](../.build/agent-validation/build.log)、[开发产物](../.build/Xcode/Build/Products/Debug/TableViewer.app)。未修改签名或钥匙串 ACL。 |
| `python3 script/check_localizations.py` | **421 条双语文案通过**，格式参数一致；另核对 Agent 编译提取键与实际英文、简体中文资源。[日志](../.build/agent-validation/localizations.log) |
| `git diff --check` | 通过。 |

Swift 宏和 Icon Composer 在受限沙箱内无法正常构建；相同脚本经自动审批获得正常构建权限后通过，没有关闭沙箱配置或删除图标来回避。

## 真实 MiniMax 与原生界面

解锁后使用本工作树完整应用路径，沿用现有 `MiniMax-M2.7 / api.minimax.cn` 配置，通过应用正常读取 Keychain。没有输出、复制或保存真实 key。发送内容仅含通用 SQLite 教学、虚构 users 示例、澄清回答和明确批准的纯数字查询结果；全程未勾选分享结构，未向模型发送用户业务记录。

| 实测 | 证据及结论 |
| --- | --- |
| 回复显示与复制 | [01](../.build/agent-validation/ui/01-minimax-markdown.png)：真实回复的标题、列表、SQL 代码块可见，think 不可见；复制整条与 SQL 后回贴核对正确。[复制 AX](../.build/agent-validation/ui/copy-reply-ax.txt) |
| 草稿、生成、停止 | [02](../.build/agent-validation/ui/02-streaming-draft.png)、[03](../.build/agent-validation/ui/03-stopped.png)：长回复流式显示时可编辑草稿，Return 换行和 ⌘Return 提交可用；停止保留部分回复和窗口正文。 |
| 澄清与独立分享 | [05](../.build/agent-validation/ui/05-clarification-local.png)：A 的问题在 B 当前连接下仍可回答，回答先留本机；单独点击发送才继续模型请求，历史卡片保留。 |
| 原连接批准与拒绝 | [06](../.build/agent-validation/ui/06-connection-bound-approval.png)：查看 B 的 SELECT 1 请求而连接为 A 时，确认执行不可用。[07](../.build/agent-validation/ui/07-tool-rejected.png)：拒绝显示未执行、未分享。 |
| 真实本地查询与恢复 | 在专用 B fixture 批准一次纯数字递归求和，得到 `200000010000000`；重开、重命名、搜索、归档和恢复后仍保留原 B 结果且尚未发送。[09](../.build/agent-validation/ui/09-restored-local-result.png)。之后单独批准回传，原卡片更新为已发送。 |
| 生成中跨库和归档 | [10](../.build/agent-validation/ui/10-generating-across-databases.png)：A 正在生成时切到 B，历史仍显示 A 正在生成；归档中继续生成，恢复后保留并继续增长。[11](../.build/agent-validation/ui/11-restored-running-session.png) |
| 生成中补充与正常退出 | 真正生成时提交“改写为索引教程”的补充，旧回复停止，新轮开始；随即正常退出并确认提示。重开后原会话标记中断，[13](../.build/agent-validation/ui/13-restart-interrupted.png)，已有索引教程保留，[14](../.build/agent-validation/ui/14-partial-recovered.png)；没有自动重发。 |

实际测试创建的连接为 **Agent UI Fixture B**，文件为当前工作树 `.build/agent-validation/Agent-UI-B.sqlite`；只含人工构造的一条 marker 数据。该连接及本机测试会话保留以便复核，没有清理用户的其他连接或历史。

## 验收边界

- 原生 NSTextView 的 setMarkedText / unmarkText 和键盘事件已直接验证组合态不提交、提交后的中文可发送及 Return 换行。CUA 的输入快捷切换未唤出系统中文候选窗口，因此不宣称完成真实候选窗口验收。CUA 的 typeText / paste 也曾丢字或回贴旧剪贴板，精确测试提示改用 setValue 并读回核对。
- B 的原生数字查询完成较快，首次观察就已完成；`08-tool-executing-ax.txt` 的文件名不能作为“执行中切换”的证据。执行中跨 A/B 的归属和污染检查以受控时序加真实 SQLite 测试为准；没有新测 PostgreSQL/MongoDB 长查询或执行中进程崩溃。
- 已在真实模型中使用继续回复及生成中补充；重新生成的请求快照和无重复轮次以定向测试为证。提示要求每次回复自行闭合代码块，但无法保证模型输出始终有效或内容准确。
- 中文主要原生布局已查看，英文为资源和编译检查；没有逐屏切换英文做视觉验收。超长历史的 CUA accessibility 树有时不返回正文，截图与滚动仍正常；不把 AX 抽取缺失误报为正文丢失。
- 实测发现原生菜单弹出后 CUA 无法继续操作；会话管理改为直接的打开、重命名、归档按钮，并重新完成这些流程。

## 交付文件

主要新增 `AgentLibrary.swift`、`AgentToolExecutor.swift`、`AgentHistoryView.swift`、`AgentMessageContent.swift`；修改 AgentModels、AgentSession、OpenAICompatibleClient、WorkspaceStore、WorkspaceView、AgentView 和应用退出保存入口。项目文件注册新源文件；文案目录、新测试脚本与本报告随源码留在当前工作树。

构建、测试日志及实测截图保存在被忽略的 `.build/agent-validation` 和 `.build/Xcode`，未加入版本控制。当前结果可直接审查；正式提交、发布及其他数据库的验收不在本轮交付中。

## 后续整合说明（2026-09-06）

上述记录是独立工作树中的原轮次验收。归档曾自动清理该工作树和被忽略的构建产物；源码由 Codex 归档快照保留。处理 Keychain 拒绝闪退时已恢复该快照，将 Agent / 全局会话改进和相关崩溃修复整合回 `/Users/yuna/ToolsProject-Local/TableViewer`，保留该目录既有未提交改动。当前项目已重新通过 198 条 Agent、22 条 workspace、47 条 Keychain 回归和开发构建，详见 [本轮验证](keychain-denial-validation.md)。原报告指向工作树 `.build/agent-validation` 的截图及日志属于历史证据，归档清理后文件未保留；不将其当作当前项目的新实机验收。

当前项目重新编译并重启后，另行实测 Keychain 读取取消、页面保留、连接重试及切回 Studio；“所有会话”仍显示四个原会话、数据库归属和等待确认发送结果状态。[当前项目历史截图](../.build/keychain-validation/ui/04-history-after-recovery.png)保存在当前项目内，详情和验收边界见上述本轮报告。
