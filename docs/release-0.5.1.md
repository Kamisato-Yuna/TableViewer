# 0.5.1 发布验收

版本 0.5.1（7），关联 [Issue #25](https://github.com/Kamisato-Yuna/TableViewer/issues/25)。

从已验收的 GPG 签名提交 `5cb2e43f1c4fedf2b0f7b9bd4477c31e9a634fde` 开始，保留 0.5.0 与完整 Pages 更新。体验修复和 Debug GUI 证据见 [体验验收报告](feedback-051-acceptance.md)。本次仅递增版本与 build，并补齐示例数据库四条文案的显式简体中文资源，以通过既有本地化检查。

## 正式构建与专项验证

- Developer ID Release 构建完成；arm64、最低系统 macOS 26；保留 App Sandbox 与 Hardened Runtime，无 `get-task-allow`。嵌套 Sparkle 代码和正式 app 深层严格签名验证通过。
- 632 条中英文资源与格式参数检查、8 项更新清单测试通过；正式包资源的独立签名沙箱探针通过 en / zh-Hans 检查。
- Agent Experience 使用合成数据及本地 HTTP fixture，通过结果授权和执行审批等现有回归；Agent Workspace 会话隔离、历史保护与示例隐藏/恢复专项测试通过。
- 从最终 Release 包复制并重签独立 `local.yuna.TableViewer.Release051QA`，不重新编译，仅改变 QA 标识和更新设置以隔离用户容器、Keychain 和自动更新。实际启动 Studio，执行 `SELECT 51 AS release_check` 得到 51；查看含中文默认值的完整 DDL，点击复制显示“已复制”；未配置 API 的 Agent 显示手动审批与结果默认留在本机的说明。该副本不等同于公开发行原包，原包信任检查单独记录。

## 范围

本机为 Apple Silicon、macOS 27 beta、Xcode 27 beta 6。本轮未重复 macOS 26 真机、外部 PostgreSQL/MongoDB、真实模型供应商或生产客户端自动更新安装全链路验收，不把本地模拟或 Debug 证据视为这些验证通过。未访问用户真实数据库或发送真实 API 请求。

## 分发信任验证

正式 app 公证 Accepted：`f05b36fa-d338-4b74-98b0-c2994c7e31d7`；DMG 公证 Accepted：`5d61f440-d437-43fd-9af9-3a623c64e2c3`。app 和 DMG 均通过 staple validate 与 Gatekeeper（Notarized Developer ID）。首次 DMG 上传连接超时，改为非加速 S3 上传后成功，未修改产物。

最终 DMG 生成 Sparkle Ed25519 签名清单，版本 0.5.1 / build 7，最低 macOS 26、arm64，附件大小 10,055,202 字节。清单复用现有更新账户并与 app 内公钥匹配。

## 公开发布与下载验证

[PR #26](https://github.com/Kamisato-Yuna/TableViewer/pull/26) 已合并为 `b46f6cce2270fbfb18f0e6295687d8ce23875e6b`。GPG 签名标签 `v0.5.1` 指向 `f8d07ccf3bb30430d846af553d57f511e20ae686`，与构建源码一致；构建后的提交仅补充验收文档。正式 [Release](https://github.com/Kamisato-Yuna/TableViewer/releases/tag/v0.5.1) 于 2026-09-08 06:46:22 UTC 公开，标为 Latest，DMG 和 appcast 均完整上传后发布；0.5.0 标签与两项附件均保留。

- 通过不带认证的 GitHub 公开下载地址获取完整 DMG（HTTP Range 分段下载），10,055,202 字节，与本地正式 DMG 逐字节一致；公开 appcast 与签名清单一致。
- 下载 DMG 的 Sparkle Ed25519 签名使用 app 内公钥与线上 Pages 清单验证通过；DMG 及只读挂载的 app 均通过 staple validate、Gatekeeper（Notarized Developer ID），app 深层严格签名验证通过，可执行文件与正式构建一致。未替换或启动用户主应用。
- 正式包独立 QA 副本进一步通过 160 行脚本末尾选区：仅运行 `SELECT 80 AS selected_value;`，结果为 80，末尾选区和结果区同时可见。
- [PR CI](https://github.com/Kamisato-Yuna/TableViewer/actions/runs/34195777313) 与 [合并后 CI](https://github.com/Kamisato-Yuna/TableViewer/actions/runs/34196030638) 的 source / macOS build and tests 均成功。
- [Pages 部署](https://github.com/Kamisato-Yuna/TableViewer/actions/runs/34196159580) 成功；真实公开页面显示 0.5.1 下载地址，线上 appcast 与 Release 资产逐字节一致，版本 0.5.1 / build 7。

上述证明公开产物和更新源有效，不等同于生产客户端完成自动安装重启；该全链路仍在前述范围之外。
