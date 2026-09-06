# 简体中文商店文案

**名称**：TableViewer

**副标题**：原生数据库浏览与查询工作台

**关键词**：数据库,SQLite,PostgreSQL,MongoDB,SQL,查询,开发工具,CSV

**描述**：

在 Mac 上连接、探索和编辑数据。TableViewer 是原生 macOS 数据库工作台，支持 SQLite、PostgreSQL 和 MongoDB，提供简体中文与英文界面。

- 浏览数据表、视图、集合与字段结构，筛选当前页，导出已加载结果为 CSV。
- 运行 SQL 或 MongoDB JSON 命令，编辑有主键的记录和 Extended JSON 文档。
- 查看 MongoDB 副本集拓扑，在内置 JavaScript Shell 中执行常用数据库操作。
- 可选连接自己的 OpenAI-compatible AI 服务，辅助解释结构和编写查询。AI 操作逐次确认，结果发送单独确认。
- 连接凭据保存在 macOS 钥匙串，应用启用沙盒。

首次启动自带可编辑的 SQLite 示例库。远程数据库与 AI 服务由用户自行配置。当前支持 Apple Silicon Mac，要求 macOS 26 或更新系统。内置 Shell 不是完整 mongosh，不包含 Node.js 或 npm。SQL 和 Shell 写入直接作用于目标数据库，请按需使用受限权限与备份。

**0.2.0 更新说明**：提供简体中文/英文界面与语言设置，支持 SQLite、PostgreSQL、MongoDB 工作流、可选 AI 助手与 MongoDB Shell。
