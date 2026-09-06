# Markdown 表格与快捷回复验收

日期：2026-09-06。当前项目已重新编译、正常重启并完成原生界面与真实 MiniMax 验证。这里的“回复选择”指点击模型给出的候选项回复。

## 改动

- Markdown 表格显示表头、交替行底色、边框与列对齐；保留单元格里的加粗、行内代码等格式。长内容可换行，宽表可横向滚动。支持省略外侧竖线、转义竖线和流式未完成行；多出的单元格保留为原文，避免静默丢内容。
- 当前最后一条完整回复中，明确邀请选择的末尾短列表会直接显示为候选按钮。点击后通过普通用户消息流程发送对应选项，保留输入框原草稿。普通说明列表、代码中的列表、未完成回复、旧消息和存在待处理工具操作的会话不会成为可发送选项。
- 原有 `ask_user` 工具选项点击后直接确认本机答案；仍由“发送结果并继续”单独确认回传。数据库操作继续使用原批准流程。
- 保留当前会话、历史记录、数据库绑定和既有本地改动；没有增加依赖，没有改变真实密钥或连接设置。

## 自动验证

测试只覆盖本轮显示、快捷回复和必要的原 Agent 回归。

| 检查 | 结果 |
| --- | --- |
| `./script/test_agent.sh` | **220 项通过**，包括新增的 22 项表格/快捷回复检查。[日志](../.build/markdown-validation/tests.log) |
| 流式表格 | 遍历示例每个截断位置，验证列、对齐信息及行宽始终一致；验证未完成行、转义竖线、代码围栏及多余值不丢失。 |
| 点击发送 | 验证准确选项、旧消息拒绝、原数据库绑定、归档/生成状态、待批准操作、草稿保留、重复点击不重复发送，以及实际请求中的 user 消息。使用本地可控 completion。 |
| `python3 script/check_localizations.py` | **427 条双语文案通过**，格式参数一致。 |
| `./script/build_and_run.sh --build` | macOS arm64 Debug 成功。[日志](../.build/markdown-validation/build.log) |
| `git diff --check` | 通过。 |

Swift 宏插件在受限沙箱中无法启动；同一测试脚本在正常构建权限下通过，没有修改构建安全设置。

## 原生界面与真实模型

运行产物为当前项目的 [TableViewer.app](../.build/Xcode/Build/Products/Debug/TableViewer.app)。

1. 打开用户截图对应的“帮我了解当前数据库”历史会话，两张表显示为真实行列，末尾四个候选项成为按钮。[表格](../.build/markdown-validation/02-tables.png)、[四个候选项](../.build/markdown-validation/01-original-reply.png)。原会话仅查看，未点击发送。
2. 新建独立测试对话，沿用应用已配置的 `MiniMax-M2.7 / api.minimax.cn`，未勾选附带表结构。只发送人工编写的分页示例和 `SELECT 1;` 文本，没有执行该 SQL、读取或发送业务记录，也没有输出密钥。
3. 真实回复包含表格、代码块和两个候选按钮。[截图](../.build/markdown-validation/03-minimax-options.png)、[界面文本](../.build/markdown-validation/03-minimax-options-ax.txt)。
4. 输入一段测试草稿后，点击“解释游标分页”。会话新增一条对应的用户消息，模型实际回复“收到：解释游标分页”并继续解释；草稿保持原值。[发送与草稿保留](../.build/markdown-validation/04-option-sent-draft-kept.png)、[界面文本](../.build/markdown-validation/04-option-sent-draft-kept-ax.txt)。
5. 让模型调用一次 `ask_user`，点击“游标分页”立即显示已回答，并停在本机结果待确认状态。[截图](../.build/markdown-validation/05-structured-answer-local.png)。展开后核对本地答案为“游标分页”，再通过原按钮单独发送，模型回复“收到：游标分页”。测试会话没有剩余待处理操作，原来一个待处理会话保持不变。

当前自动候选识别覆盖中英文明确邀请后的末尾 2–6 个短列表项；复杂嵌套列表或其他自由格式仍按正文显示，结构化 `ask_user` 继续支持原选项和自由输入。没有宣称完成所有 Markdown 扩展语法、所有主题或所有窗口尺寸的验收。本轮原生截图为深色界面。

源码保持未提交、可审查，未推送或发布。截图与日志保存在当前项目被忽略的 `.build/markdown-validation` 内。
