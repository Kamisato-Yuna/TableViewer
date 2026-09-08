# 0.5.1 体验修复实现与验收

2026-09-08，Issue #25。需求来源是用户提供并已逐页核对的三页体验反馈；原始私人 PDF 和聊天截图不进入仓库。测试只覆盖本轮改动。

## 交付范围

1. 执行前规模预估改为原生 sheet，宽度按宿主窗口计算并最多 840 点，高度最多 620 点。摘要、等宽计划、固定底部取消/执行分区；长计划完整保留，双向滚动，不再截取前 900 字。独立固定尺寸承载避免计划参与无限内在尺寸计算，保留原审批规则。
2. 结果确认区增加默认关闭的“本会话自动发送结果”。用户勾选并主动发送后，后续已完成/已拒绝的整批结果自动继续；没有回答的问题、待审批/执行中操作以及失败/不确定结果不会自动发送。失败/不确定结果仍允许明确手动发送。授权绑定该会话配置，可撤销，停止/归档/配置修改会撤销；旧存档和新会话默认无授权。API 设置保存会撤销全部旧会话授权并创建新会话。复用 shared 与 running 状态防重复，数据库执行审批独立。
3. 对象概览增加当前数据库“继续会话”菜单，优先显示运行/待处理会话，复用已有会话与时间线；查看不会创建空会话或更改历史排序。
4. DDL/集合定义增加复制完整原文按钮和两秒反馈，空定义禁用，不执行定义、不关闭 sheet。
5. 新建/历史/分栏统一原生 controlSize、图标尺寸和玻璃按钮样式，历史保留原生菜单指示。脚本列表继续横向滚动。
6. 集成编辑器 safe-area/窄空间分栏/选区可见性修复，以及示例数据库隐藏建议、手动恢复与最后一个用户连接移除后自动恢复。

## 集成与来源保护

独立集成目录 `/tmp/tableviewer-051-integration`，分支 `codex/feedback-051`。从已发布 0.5.0 提交 `3387569d639285e337ac8f688b5b31ffd55a698e` 开始，快进纳入 Pages 已合并提交 `ea4541b3aeac848bcfaaa1abd7f8093ee8063373`。原 7bae 及用户来源工作树的带入修改均保留，没有 reset、clean、stash 或覆盖。

仅应用 2ab4 的 `editor-viewport-fix.patch` 与 d4c8 的 `demo-visibility.patch`，未复制混合工作区或整个 .build。原任务的独立验收详见 `editor-viewport-regression.md` 与 `demo-visibility-regression.md`；本报告补充最终集成验收。

## 实际 .app 验收

最终普通构建：`.build/Xcode/Build/Products/Debug/TableViewer.app`。实际运行副本：`.build/FeedbackQA/TableViewerFeedbackQA.app`，独立 bundle `local.yuna.TableViewer.Feedback051QA`，对应独立 Application Support 和 Keychain 命名空间。使用该应用自动创建的 Studio SQLite、合成脚本与 127.0.0.1 模拟 API，未操作用户真实数据库/连接/凭据，未退出主应用。

- 预估 sheet：实际 SQLite 26 表别名扫描计划；深浅色、常规窗口和原生左半屏窗口；纵向滚到底部；英文 350 字符以上别名产生的超长行通过原生水平滚动条到达末端，摘要和底部按钮保持固定。Escape 返回待审批，没有执行；Return 和按钮确认执行均成功。
- 自动发送：第一轮实际 SQLite 结果保留本机，勾选前复选框为 0；勾选并点击发送后第二轮仍等待执行审批及预估确认。第二轮执行结束自动发送并收到模拟 API 的结束回复。第一组三次 HTTP 请求中的工具结果数为 0、1、2，无重复发送。撤销按钮移除授权状态；新会话首轮结果继续停留本机，复选框重新为 0。改为另一个 loopback API 后创建无授权的新会话；英文提示正确。
- 会话入口：概览菜单显示当前数据库已有会话；点击恢复原消息、两轮操作和结果，没有新建空会话。历史排序/连接隔离另由真实 WorkspaceStore 集成测试验证。
- DDL：复制 projects 原始定义，再粘贴回合成脚本，内容完整且包含中文默认值 `'进行中'`；显示“已复制”，Escape 可关闭。未执行复制出的 CREATE TABLE。最终英文复核修正动态按钮的本地化与缺失资源，实际显示 Copy / Copied。
- 工具栏：常规和半屏窄窗口、双侧栏、中英文及深浅外观；三个操作保持相同可见高度与可点击区域，历史保留菜单箭头。半屏空间不足时查询自动上下排列，脚本标签没有挤掉操作。
- 编辑器：最终集成 .app 中输入 160 行合成 SQL，末行 `SELECT 80;` 可见且选区运行返回真实结果 80；双侧栏打开后仍可见。鼠标实际拖动分隔线后 AX 位置由 422 变为 497.5，补齐原编辑器任务未可靠验证的鼠标拖动环节。
- 重新启动最终构建，已保存脚本、原会话及撤销后的授权状态保留。浅色和英文通过该独立 .app 的进程启动参数验证；CUA 在原生外观弹出菜单选择时不稳定，未将那些未生效的点击宣称为通过。

本机截图在 `output/feedback-051/`（忽略目录、未公开上传）：`overview-light.jpg`、`estimate-light.jpg`、`estimate-horizontal-en.jpg`、`estimate-horizontal-end-en.jpg`、`result-consent-light.jpg`、`narrow-editor-dark.jpg`、`editor-final-light.jpg`、`divider-drag-light.jpg`、`toolbar-dark.jpg`、`ddl-final-en.jpg`。

## 自动验证

- `./script/build_and_run.sh --build`：最终构建成功。最初沙箱禁止 SwiftPM 缓存写入/宏插件启动，使用获准的构建权限后通过，非产品故障。
- `./script/test_agent.sh`：全部通过；新增整批只发一次、默认关闭、待回答/执行审批不越过、撤销、失败保留本机、配置修改/停止/归档撤销、旧存档兼容及持久化断言；原本地 HTTP 协议回归通过。
- `./script/test_agent_workspace.sh`：全部通过，包括异步结果所属会话、连接隔离、排序、存储保护和未保存修改保护。旧测试假定 connect 自动创建会话而触发 nil；修正为明确断言连接不新建，再显式创建测试会话，产品行为未因此改变。
- `bash script/test_demo_visibility.sh`：全部通过；真实 WorkspaceStore、隔离 bundle/合成 SQLite 覆盖隐藏、保留、不重复提示、重启、部分删除、最后连接删除恢复、失败连接不提示。
- `bash script/test_editor_viewport.sh`：通过；实际 TextKit/SwiftUI 承载、尺寸变化、重新挂载、选区保持、脚本 A/B/A 与撤销重做隔离。
- `git diff --check`：通过。

## 验收结论与发布边界

本轮体验修复验收通过，可交接独立 0.5.1 发布任务。当前应用版本号仍为 0.5.0；发布任务负责更新至 0.5.1、正式构建、Developer ID 签名、Apple 公证、staple、Gatekeeper、DMG、appcast/Release 和公开下载验证，保留既有 0.5.0 标签及附件。

本轮运行环境为 macOS 27 / Xcode 27 beta；没有重复外部 PostgreSQL/MongoDB 服务矩阵或 macOS 26 GUI，也没有把 Debug 应用视为正式发行包验收。预估展示是共享 QueryEstimate 路径，实际长计划来源为合成 SQLite；两种外部引擎与正式包的发行检查由后续发布验证报告分别说明。未发现阻止本轮交接的产品失败。
