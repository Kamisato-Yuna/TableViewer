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
| 10 | 连续脚本标签、关闭与横向滚动；Safari 式共享系统玻璃背景，非活动标题使用 secondary，活动标题清晰；居中标题、悬停/焦点关闭叠层 | Safari 最终深浅 GUI、中英文长名、窄工作区溢出选中自动滚动、⇧⌘W 关闭与非活动关闭通过；用户确认悬停正常浮现/消失、标题不动 |
| 11 | 会话内每脚本保留结果/错误/语句索引/选区；异步结果归属原脚本，关闭释放 | 状态测试、跨连接同名脚本恢复、真实双脚本切换通过 |
| 12 | 移除编辑器下方及标题中的常驻运行快捷键提示 | 真实 GUI 通过 |
| 13 | 最近脚本菜单与独立历史窗口；跨连接恢复、缺失文件/孤立连接反馈，不自动执行 | 状态测试与实际历史窗口打开通过；无覆盖现有草稿 |

## 实现说明

最终采用 Safari 式轻量共享背景方向：取消连体栏的外框与强调色短线，非活动文字为系统 secondary、活动文字为 primary。固定宽度标题居中，关闭控件以 28 pt 叠层在悬停或键盘焦点时浮现，仅按钮下方使用局部原生材质，不参与标签尺寸计算。隐藏时按钮不在视图树中；保留上下文菜单、辅助功能关闭动作与 ⇧⌘W 菜单快捷键。活动标签改变时自动滚入视野。

本机 macOS 27 SDK 的公开 glassEffect(.regular) 与系统 Material 管理玻璃效果，不以固定 alpha 模拟，不读写私有系统偏好。Apple [材质说明](https://developer.apple.com/design/human-interface-guidelines/materials) 和 [WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/) 说明 Liquid Glass 会响应外观偏好与辅助功能设置。系统玻璃外观/透明度偏好和“降低透明度”是两项不同设置；没有声称应用读取了滑块数值。未改变用户全局设置，因此两种全局切换均未实测。

NSTabView/TabView 标准样式没有同时提供脚本关闭、横向溢出和指定底边连接控制，因此保留最小标签布局及既有编辑器生命周期。没有私有 Safari API、系统内部视图遍历或每个标签常驻模糊层。

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

- Release 编译通过（本地 Xcode beta / macOS SDK，ad hoc 签名）；最新构建记录为 tv053-safari-final.log。
- 最终工作台测试 tv053-store-final-verified.log、编辑器测试 tv053-editor-connected.log、SwiftUI 视图生命周期 tv053-viewport-connected.log 通过。多结果 Picker 30 次生命周期测试 tv053-picker-accepted.log 通过。
- PostgreSQL 分页记录在 tv053-extensions-test3.log；MongoDB 分页记录在 tv053-mongo-test2.log。夹具初次配置错误已修正后重跑通过，不计入产品失败。最终默认测试明确跳过未配置的服务器，不能用该 SKIP 代替上述真实服务器证据。
- 补全上下文扫描在 66003 字符输入上 30 次平均约 17.6 ms；这是局部函数耗时，不是 Instruments、整帧延迟或帧率证明。
- 已启动独立 bundle 的真实 .app，连接、脚本及 Keychain 命名空间与用户应用隔离。只操作合成 Studio/独立数据库数据，未替换用户安装的应用。
- 本地截图在 output/qa053（Safari 为最终选定方案，其余标签图片为过程证据）：safari-tabs-light.png、safari-tabs-dark.png、safari-tabs-overflow-selected.png、connected-tabs-light.png、connected-tabs-dark.png、liquid-glass-tabs-scaled-gutter-light.png、settings-category-label-hidden.png、estimates-off-no-row.png、estimates-summary-only.png、estimates-details-settings.png、run-hint-inline-dark.png、pagination-five-light.png、history-reopened-light.png。截图及原始日志不进入公开仓库。
- 未覆盖：物理触控板手势、真实系统拼音候选组合、最终标签栏的物理横向手势/窗口边缘拖动（已验证开启检查器后窄工作区选中溢出标签自动滚入视野）、macOS 26 兼容性实机矩阵、系统玻璃透明度/降低透明度开关切换和 Instruments 长时性能。marked-text 与滚轮已有原生视图事件测试，窄布局已有真实 SwiftUI hosting 生命周期测试，不能等同上述物理交互。
- 本轮不证明发行验收。原发布任务仍需在最终集成提交上重建、执行其余交互检查、签名、公证和发行校验；未复用旧组合包的发行结论。
