# 0.5.3 工作台扩展验收

关联 Issue：#34。基础提交：f3c809574c93fac6b2f2f39622ea0be30f24d5e3；分支：codex/053-workbench-extensions。旧组合包与旧公证不作为本轮发行证据。

| 项目 | 最终行为 | 已有证据 |
| --- | --- | --- |
| 1 | 可选预估默认关闭；旧显示偏好不自动启用；超过 5 秒只建议一次；查询、Agent、浏览共用开关，独立执行审批/只读保护保留 | SQLite 真实慢查询与状态测试通过；GUI 关闭无预估行，开启仅摘要，详情中可关闭 |
| 2 | 设置按通用、编辑器、数据、执行分类，按当前工作区路由 | 状态测试与真实设置窗口通过；分类文字标签隐藏，保留辅助功能名称 |
| 3 | 字号输入 10–28、步进、系统字体列表及实时 SQL/中文/数字样例 | GUI 输入 16、非法 999 恢复先前值；字体样例验证 |
| 4 | 三引擎实际分页大小 1–10000，修改后回到首页并刷新 | SQLite/PostgreSQL/MongoDB 合成 53 行，页大小 1/7/20/53/100 无重复遗漏；GUI 每页 5 条 |
| 5 | 设置作为模态 sheet，Escape 关闭并恢复工作区；保持系统主题 | 真实深浅主题、Escape 和焦点验证；后台应用截图会遵循系统失活外观 |
| 6 | ⌘+/⌘−/⌘0 与 ⌘滚轮调字号，文字、选区保持，行号同步字号与宽度 | GUI 快捷键与行号截图；原生视图事件测试通过，物理触控板另列未验 |
| 7 | Tab 默认 4 空格，可配置宽度/关闭转换；多行缩进、反缩进、单次撤销 | 原生 NSTextView 测试通过；marked-text 阶段不干预 |
| 8 | 本地 SQL 关键字/对象/带引号名称补全；无逐键联网；候选取消不改原文 | 词法、候选接受/取消、IME 标记测试；实际候选面板 Escape/Tab/撤销通过 |
| 9 | 第三次点击运行时一次性短提示，4 秒消失；快捷键不计数 | 实际点击触发，最终提示位于运行工具栏，无遮挡编辑正文 |
| 10 | 连续脚本标签、关闭与横向滚动；标签与编辑结果主体为两个独立圆角块；Safari 式原生玻璃活动标签，非活动标题 secondary；居中标题与悬停/焦点关闭叠层 | Safari 最终深浅 GUI、中英文长名、窄工作区溢出选中自动滚动、⇧⌘W 关闭与非活动关闭通过；用户确认悬停正常浮现/消失、标题不动 |
| 11 | 会话内每脚本保留结果/错误/语句索引/选区；异步结果归属原脚本，关闭释放 | 状态测试、跨连接同名脚本恢复、真实双脚本切换通过 |
| 12 | 移除编辑器下方及标题中的常驻运行快捷键提示 | 真实 GUI 通过 |
| 13 | 最近脚本菜单与独立历史窗口；跨连接恢复、缺失文件/孤立连接反馈，不自动执行 | 状态测试与实际历史窗口打开通过；无覆盖现有草稿 |

## 实现说明

最终采用两个独立圆角块：上方标签栏为系统 .bar 圆角背景、thinMaterial 胶囊底座和原生玻璃活动项，下方主体单独以 regularMaterial、16 pt 圆角和 8 pt 内侧安全间距承载编辑器及结果，两块间距 8 pt。参考图用于访达背景与层次，不复用其内部控件。

编辑器与结果区使用 12 pt 圆角内面板，实际 NSHostingView backing layer 同步裁剪，避免 NSScrollView、标尺、表格方角穿出 SwiftUI 圆角。内侧留白保护行号、首末行及滚动条。左右标题栏统一为 40 pt；SQL 工具栏仍覆盖滚动编辑器，系统 .bar 材质采样下方文字。独立标签栏不再占用编辑器留白，contentInsets.top 为 40 pt（慢查询建议展开时 76 pt）。

非活动文字为系统 secondary，活动文字 primary；非活动项悬停或键盘焦点显示 quaternary 胶囊反馈。标题居中且大小不随悬停改变。进入标签/键盘焦点时出现裸 x，仅关闭按钮自身悬停时显示系统 quaternary 普通圆底，关闭按钮没有 Liquid Glass。标题两侧永久预留 38 pt 对称空间，不再与关闭图标重叠，也不再使用局部模糊或双层文字遮罩。隐藏按钮不在视图树中，保留辅助功能关闭与 ⇧⌘W。

加号与分栏按钮使用 32 pt 原生交互玻璃，历史菜单同高、44 pt 宽以保留原生箭头；菜单玻璃附着于实际菜单控件外层，因为 macOS 原生 Menu 会忽略其标签内部玻璃。三者使用相同系统材质和图标字号。

本机 macOS 27 SDK 的公开 glassEffect(.regular) 与系统 Material 管理对应材质效果，不以固定 alpha 模拟，不读写私有系统偏好。Apple [材质说明](https://developer.apple.com/design/human-interface-guidelines/materials) 和 [WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/) 说明 Liquid Glass 会响应外观偏好与辅助功能设置。系统玻璃外观/透明度偏好和“降低透明度”是不同设置；没有声称应用读取了滑块数值。未改变用户全局设置，两种全局切换均未实测。

NSTabView/TabView 标准样式没有同时提供脚本关闭、横向溢出和原生编辑器会话保留，因此保留最小标签布局及既有编辑器生命周期。没有私有 Safari API、系统内部视图遍历或每个标签常驻模糊层。

预估关闭时不保留占位、关闭说明或设置按钮。开启时数据区只显示可点击摘要，计划文本和关闭设置在固定尺寸详情 sheet 内，避免长计划参与主分栏布局。

## 可复验命令

```sh
bash script/test_workbench053.sh
bash script/test_editor053.sh
bash script/test_editor_viewport.sh
bash script/test_editor_and_pg_state.sh
# 仅对调用者准备的合成夹具运行；未设置端口明确 SKIP
TV053_PG_PORT=<postgres-port> TV053_MONGO_PORT=<mongo-port> bash script/test_workbench053.sh --databases-only
```

工作台测试不传目录时创建独立临时目录，保留测试产物；分页数据库必须由调用者准备，脚本不会自动选择现有数据库服务器。

## 本轮证据与限制

- Release 编译通过（本地 Xcode beta / macOS SDK，ad hoc 签名）；最新构建记录为 tv053-scroll-under-glass.log。
- 最终工作台测试 tv053-store-final-verified.log、编辑器测试 tv053-editor-connected.log、SwiftUI 视图生命周期 tv053-rounded-viewport.log 通过。多结果 Picker 30 次生命周期测试 tv053-picker-accepted.log 通过。
- PostgreSQL 分页记录在 tv053-extensions-test3.log；MongoDB 分页记录在 tv053-mongo-test2.log。夹具初次配置错误已修正后重跑通过，不计入产品失败。最终默认测试明确跳过未配置的服务器，不能用该 SKIP 代替上述真实服务器证据。
- 补全上下文扫描在 66003 字符输入上 30 次平均约 17.6 ms；这是局部函数耗时，不是 Instruments、整帧延迟或帧率证明。
- 已启动独立 bundle 的真实 .app，连接、脚本及 Keychain 命名空间与用户应用隔离。只操作合成 Studio/独立数据库数据，未替换用户安装的应用。
- 圆角主体最终截图在 output/qa053：rounded-workspace-dark-stacked.png、rounded-workspace-dark-side-by-side.png、rounded-workspace-dark-narrow.png、rounded-workspace-light-narrow.png、rounded-workspace-light-stacked.png。已实测 81 行脚本末行、行号、第 120 条结果及滚动条均保留在圆角安全区域内，状态栏贴底。旧方案过程截图：safari-blended-light.png、safari-blended-dark.png（已被最新圆角主体方案覆盖）、safari-tabs-light.png、safari-tabs-dark.png（前版）、safari-tabs-overflow-selected.png、connected-tabs-light.png、connected-tabs-dark.png、liquid-glass-tabs-scaled-gutter-light.png、settings-category-label-hidden.png、estimates-off-no-row.png、estimates-summary-only.png、estimates-details-settings.png、run-hint-inline-dark.png、pagination-five-light.png、history-reopened-light.png。截图及原始日志不进入公开仓库。
- 未覆盖：物理触控板手势、真实系统拼音候选组合、最终标签栏的物理横向手势/窗口边缘拖动（已验证开启检查器后窄工作区选中溢出标签自动滚入视野）、macOS 26 兼容性实机矩阵、系统玻璃透明度/降低透明度开关切换和 Instruments 长时性能。marked-text 与滚轮已有原生视图事件测试，窄布局已有真实 SwiftUI hosting 生命周期测试，不能等同上述物理交互。
- 本轮不证明发行验收。原发布任务仍需在最终集成提交上重建、执行其余交互检查、签名、公证和发行校验；未复用旧组合包的发行结论。

### 本轮胶囊标签与滚动磨砂补验

- Release 构建通过；隔离 .app 已更新并实际启动。
- tv053-underlap-viewport.log：顶部选区可见性、窄宽重排、手动滚动和 A/B/A 撤销生命周期通过。
- tv053-underlap-editor.log：本轮编辑器回归通过，包括字号、行号、输入、补全和撤销。
- output/qa053/capsule-frosted-scroll-light.png 与 capsule-frosted-scroll-dark.png：深浅色左右分栏、滚动文字磨砂层和第 120 条结果；前述 rounded-workspace 截图为上一版。系统全局透明度切换仍未实测。

### 访达参考与空结果排版补验

- 标签采用连续系统 thinMaterial 胶囊底座，少量标签等分可用宽度，多标签仍可横向滚动；活动项为内嵌原生玻璃胶囊，关闭叠层置于左侧，新建按钮为圆形原生玻璃。
- 自有 NSSplitView 仅覆盖分隔条绘制，8 pt 空隙保留原生调整尺寸区域，不遍历 SwiftUI 私有视图。上下与左右分栏共用这一实现。
- 空状态独立填满标题栏以下的剩余高度，标题、导出和刷新固定顶部；真实应用深浅色、上下与左右布局均检查。截图：finder-empty-horizontal-dark.png、finder-empty-stacked-dark.png、finder-empty-horizontal-light.png。
- tv053-finder-viewport.log 通过：两个方向设置分栏尺寸不替换编辑器、首行与选区可见、A/B/A 撤销记录保留。后台拖动事件未使分隔位置变化，因此不将其计为物理鼠标拖动验收。
- 构建记录 tv053-finder-final.log；本轮不涉及数据库执行逻辑和发行。

### 独立圆角块与两级悬停最终补验

- 最终构建记录：tv053-finder-close-final.log。tv053-two-blocks-viewport.log 通过原生留白/选区、两方向分栏尺寸、会话保留及撤销回归。
- 前述包含标签的大圆角主体、82 pt 顶部留白和关闭按钮玻璃方案均已被本节及实现说明覆盖。
- 原生物理悬停、控件按下状态及全局透明度开关不由静态实现或构建成功代替验收；物理反馈尚待确认。

- 用户实际悬停发现活动标签 x 比非活动项模糊：旧版验收失败，不能沿用“正常”的早期反馈。单独背景试验导致标题被采样，已弃用；最终关闭按钮为玻璃标签的独立前景兄弟视图，使用独立合成层和 primary 单色前景。修正构建 tv053-close-foreground.log，等待最终物理悬停复核。

- 用户复核发现局部标题柔化产生重影，前景分离版本仍未通过。最终移除所有标题模糊/遮罩，永久对称预留关闭空间；标题与 x 先组成统一前景，再施加标签玻璃背景。构建 tv053-tab-foreground-final.log，最终悬停仍待用户确认。

- 最终真实应用证据：two-blocks-final-light.png、two-blocks-final-stacked-light.png、two-blocks-final-dark.png；长脚本与 120 行结果滚动边界见 two-blocks-corners-dark.png、two-blocks-corners-dark-narrow.png（标签前景修正前的同一圆角布局）。历史菜单实际打开正常；关闭图标最后一次悬停反馈仍待确认，不能称为完整视觉验收。
