# 查询编辑器可视范围修复与验收

2026-09-08；macOS 27 beta / Xcode 27 beta。只覆盖本轮查询编辑器布局、选区可见性及相关输入回归。

## 已证实原因

在来源 SidebarQA（可执行文件构建于 12:01）和本工作树未修复的新 Debug `.app` 均复现：SQL 标签、行号、语句开头、底部快捷键文字落在左侧栏下方，160 行合成 SQL 滚到末尾仍看不到语句开头和光标。

对独立 SidebarQA 的 LLDB 只读视图诊断显示：导航详情可见区域 `x=240,width=1200`，嵌套 `SystemSplitView` 相对该区域的 frame 却为 `x=-240,width=1440`。原生分栏扩入了 NavigationSplitView 的侧栏安全区，外层裁剪使输入区左端不可见。单独承载 CodeEditor 的尺寸探针没有该扩展，不能归因于 SQL 内容或文本容器本身。

另外，宽 1000 点的窗口同时展开两个侧栏时，查询区不足两个 260 点分栏的最小宽度；显示结果后左右布局也会超出可见边界。宽度变化导致长行重新折行，以及分栏方向变化导致保留的编辑器重新挂载，还可能让原本可见的选区离屏。

## 修复

- QuerySplitContainer 使用小型 NSHostingView 边界，`safeAreaRegions = []`，按父查询区尺寸承载原有 HSplitView/VSplitView。
- 查询区不足 521 点时自动上下排列；保留左右布局偏好，空间恢复后恢复左右排列。
- 保留的 QueryTextView 真正重新挂到窗口后恢复选区可见性；宽度变化时仅对原本可见且正在编辑的选区跟随折行，避免覆盖用户主动滚动位置。
- 不改查询语义、脚本绑定、撤销栈、连接、凭据或已有安全措施。

## 实际 GUI 验证

使用本工作树新构建的独立 `local.yuna.TableViewer.EditorFixedQA` 应用，其数据和 Keychain 命名空间独立。仅使用该应用新建的 Studio SQLite 示例及 `Viewport fixed QA` 合成脚本；没有连接真实数据库，没有安装更新，也没有替换或退出用户的主 TableViewer。

- 常规 1440 点窗口、约 1000 点窄窗口以及系统缩放大窗口。
- 80 条 SELECT、160 行 SQL，长注释自动折行；首行、末行和追加内容完整可访问，行号正常。
- 上下滚动、首尾跳转、跨屏选择、末尾编辑；左右滚动手势不产生隐藏列，编辑器保留原有自动折行方式，没有新增横向滚动模式。
- 上下与左右布局切换、左右侧栏开合、窄空间自动上下排列及恢复左右排列；最终构建的第 160 行选区保持可见。
- 运行 `SELECT 80;` 选区，真实 SQLite 结果为 80；结果出现后不再裁剪输入区。
- 末尾粘贴 `-- FINAL_EDIT`，⌘Z 移除、⇧⌘Z 恢复，已通过辅助功能文本核实。
- 分隔线通过原生辅助功能值从 242 调至 300，观察到位置变化。CUA 像素拖拽未可靠改变分隔线，因此不把鼠标拖拽本身宣称为通过。

截图（本机保留，未公开上传）：

- `output/editor-viewport/before-clipping.png`：本工作树未修复应用的左边界裁剪。
- `output/editor-viewport/final-small-results.png`：最终构建，窄窗口、双侧栏、末行选区和真实结果。
- `output/editor-viewport/final-large-results.png`：大窗口左右布局。
- `output/editor-viewport/final-large-editor.png`：最终构建大窗口上下布局、末尾追加文本。

## 自动回归与构建

`./script/test_editor_viewport.sh` 通过。直接提取实际 CodeEditor/QuerySplitContainer 代码，验证 900 → 430 → 900 点宽度变化、重新挂载后选区可见，文本/选区不变，主动滚动位置不被重置；同时复用 EditorUndoLifecycleTests 验证 A/B/A 脚本切换和过期委托回调隔离。测试不访问真实连接或通用剪贴板，临时产物保留。

`./script/build_and_run.sh --build` 和 `git diff --check` 通过。最终 Debug 构建代码时间为 13:25:49，后续仅增加测试中的重新挂载断言及本记录，应用源代码未再变化。

最终普通构建：`.build/Xcode/Build/Products/Debug/TableViewer.app`

实际 GUI 验收副本：`.build/EditorFixedQA/TableViewerEditorFixedQA.app`

本轮未验证 macOS 26、外部 PostgreSQL/MongoDB、签名公证或安装包；构建通过不代表正式发布验收。

## 发布交接

本工作树最初 QueryEditorView.swift 与本地 v0.5.0 标签对应文件逐字相同；已核实标签保留上述受影响分栏路径。因此本补丁适用于后续修复版本，不能把已发布 v0.5.0 视为已包含本修复。来源任务已确认 v0.5.0 发布并知悉此状态；未覆盖标签、附件或自行发布。

Pages 任务已确认其更新未使用查询工作台截图。历史相关 Issue #12（分栏）、#15（编辑器排版）均已关闭，本次没有将修复冒充为已完成的旧 Issue，也没有新建远端 Issue 或提交。

本任务保留了全部带入修改；交接补丁只包含本轮 QueryEditorView 增量、本轮测试及本记录。
