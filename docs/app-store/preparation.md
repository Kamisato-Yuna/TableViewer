# 中国区 App Store 准备

2026-09-06：当前工具链为 **Xcode 27 beta 6（27A5252f）**，本机仅安装 Xcode-beta。Apple 当前允许该工具链用于 TestFlight 内部/外部测试；正式上架待可提交审核的 RC/正式工具链重新归档。本轮准备材料与 Developer ID 公证，不代表 App Store 审核或上架成功。

依据：[App Store Connect 更新说明](https://developer.apple.com/help/app-store-connect/release-notes/)、[Apple beta 软件说明](https://developer.apple.com/support/install-beta/)、[工具链要求](https://developer.apple.com/xcode/system-requirements)。

## 已准备的产品信息

- 名称：TableViewer
- 平台：macOS；当前二进制仅 Apple Silicon，最低 macOS 26。
- Bundle ID：`local.yuna.TableViewer`。继续使用当前 ID 以保持容器和钥匙串兼容；商店注册可用性仍需验证。
- 版本：0.2.0；Build：3（实际归档版本以工程为准）。
- 分类：开发者工具；语言：简体中文、英文。
- 目标地区：中国大陆；价格尚未在 App Store Connect 设置。
- 本地化商品文案：本目录下 `zh-Hans.md`、`en-US.md`。
- 隐私政策：[公开项目隐私政策](https://github.com/Kamisato-Yuna/TableViewer/blob/main/docs/privacy.md)。
- 支持页面：[Discussions](https://github.com/Kamisato-Yuna/TableViewer/discussions)。

## 后续提交事项

1. 使用 Apple 支持正式审核的工具链构建、验证并归档；启用对应团队的 App Store 分发签名与描述文件。Developer ID 公证包用于商店外分发，不能直接作为商店上传包。
2. 在 App Store Connect 创建/确认 macOS App、Bundle ID、SKU，填写实际审核联系人、年龄分级和产品截图。联系人电话等个人资料不放进开源仓库。
3. 设置中国大陆地区和价格；核实中国大陆备案信息是否适用于此应用，并按后台要求提交真实资料。不得臆造 ICP 或许可编号。
4. 完成隐私问卷：开发者不运营收集服务，但用户可连接数据库和第三方 AI 服务，须按实际数据处理方式填写，不能因“本机客户端”直接跳过判断。
5. 完成出口合规判断：应用包含 TLS/OpenSSL/数据库加密依赖；按 Apple 问卷提供真实说明，不预设“无加密”。
6. 上传处理成功后，选择对应构建、提交审核并跟踪结果。TestFlight 成功、公证 Accepted 和源码 CI 均不等于商店审核通过。

中国大陆资料依据：[Apple App 信息说明](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)。

## 审核说明草稿

应用是 SQLite、PostgreSQL、MongoDB 数据库开发工具。首次启动可直接在本机 Studio 示例库体验浏览、编辑、SQL 查询和 CSV 导出，无需账号。外部数据库使用用户自行配置的连接。AI 功能默认未配置，可选使用用户自己的 OpenAI-compatible 服务和凭据，不提供订阅或应用内购买。AI 工具需逐次确认，工具结果需单独确认后发送。内置 Shell 使用 JavaScriptCore 执行数据库命令，不提供 Node.js、npm、文件系统或系统 Shell API。
