# 右侧栏开合性能修复

2026-09-08，macOS 27 beta / Xcode 27 beta，本机 Debug App。

## 原因与最终实现

原生 inspector 会连续改变工作区的宽度，触发长 Markdown 回答的反复折行、TextKit 布局与 SwiftUI 布局。仅缓存解析、将消息列表换成 LazyVStack，不能解决这条路径。

- 记录详情和 Agent 最近会话共用独立的 NSHostingView；Agent 阅读列也由独立 NSHostingView 承载，避免整体移动时更新所有离屏代码块和表格。侧栏宽度在动画期间固定，AppKit 通过图层承载的 frame 动画完成 220 毫秒的开合。
- 主内容区的尺寸调整不进入动画事务。Agent 的阅读列宽根据窗口和侧栏宽度计算，开合侧栏不会改变阅读列宽；窗口或分隔线实际调整大小时才重新折行。
- Debug 构建通过 signpost 标记两个原生动画从开始到完成的真实区间，区分动画和后续辅助功能扫描；Release 不记录这些标记。
- 侧栏保留 260–380 点的宽度拖动范围；隐藏后禁用控件并从辅助功能树中隐藏。系统减弱动态效果开启时不播放位移动画。
- 最近会话显示固定日期时间，避免十个相对时间标签逐秒刷新。
- 保留 Markdown 解析缓存。撤回消息及字段的懒布局实验：在本机系统中，Markdown 的辅助功能滚动动作触发了 SwiftUI 内部断言，不能作为交付方案。

## 验证方式

使用实际构建的 App，通过 CUA 操作；使用 Instruments `Animation Hitches` 采集应用进程。后续压力测试使用独立 bundle identifier `local.yuna.TableViewer.SidebarQA`，单独的本地存储和钥匙串命名空间，内容为 30,057 字符、80 节的合成 Markdown（标题、列表、代码块和表格）及十个本地会话，无外部 API 或数据库请求。

最初使用原生 inspector 的长会话采样检测到最长 733.33 毫秒的 hitch。不同阶段的录制有不同内容、交互节奏和录制时长，因此不把事件总数或不同场景的最大值计算为严格的百分比性能提升。hitch 表包含多个表面事件，不等同于丢帧数或 FPS。

原始 trace 包含本机诊断上下文，仅保留在本机临时目录，不作为公开附件。指标含义参照 [Apple 的 hitch 说明](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)。

## 内容与状态回归

- Agent 导航与历史排序相关测试通过。
- Agent Experience 测试通过，包括 Markdown、输入法、流式消息与本地模拟 HTTP 流程。
- Markdown 缓存对文本替换、流式追加和清空的回归通过；解析耗时不作为动画帧率证据。
- 合成回答可以滚动到第 80 节，末尾表格与代码完整显示。
- 两种侧栏各八次完整开合，状态交替正确；Agent 未发送草稿保留。
- 记录详情的字段草稿在隐藏再展开后保留，撤销恢复原值；未提交数据库编辑。
- 原生承载视图内 API 设置弹窗正常打开和取消；强调色保持一致。
- 最终 Debug 构建与 `git diff --check` 通过。

## 最终动画采样结果

最终 Debug 构建在 2026-09-08 12:02 的同一次录制中完成 16 次开合：Agent 最近会话 8 次、记录详情 8 次。使用 `Animation Hitches` 加 `Points of Interest`，按应用进程过滤，去重 signpost，并将 hitch 与原生动画开始至完成的区间求交；即使 hitch 只部分重叠，也计入它的完整延迟。

| 场景 | 完整开合次数 | 动画区间最大 hitch |
| --- | ---: | ---: |
| Agent：30,057 字符、80 节 Markdown | 8 | 33.333 ms |
| Studio 项目记录详情 | 8 | 8.333 ms |

16 次侧栏开合对应 16 个 Sidebar 区间，Agent 同时产生 8 个阅读列移动区间，共 24 个原生区间；不能把它们算成 24 次交互。侧栏从开始到完成回调为 235.840–257.710 ms（设定动画时长 220 ms）。本次实际开合未出现超过 50 ms 的 hitch；这证明所测场景已消除明显的动画长停顿，但不等同于恒定 60/120 FPS 或所有设备零掉帧。

整段录制仍有三个发生在动画区间之外的长 hitch：12.630 秒处 108.333 ms、18.355 秒处 758.337 ms、19.171 秒处 175.000 ms。后两处在 Agent 最后一次动画结束之后、记录详情首次动画之前的页面切换阶段；第一处在首次动画完成之后。此次没有把这些事件归入开合动画，也没有把整段录制描述为零卡顿。仅凭此采样不能将它们进一步归因于辅助功能扫描或某个具体视图。

脱敏后的逐区间结果见 [sidebar-animation-measurements.json](sidebar-animation-measurements.json)。原始本地录制为 `/tmp/tableviewer-sidebar-acceptance.trace`；本机最终构建位于 `.build/Xcode/Build/Products/Debug/TableViewer.app`。实际验证使用该构建的独立 QA 副本；没有替换 `/Applications/TableViewer.app`，也没有退出用户正在使用的主窗口。
