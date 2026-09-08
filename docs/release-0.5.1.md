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

公证、公开下载和线上流水线结果在完成后补记。
