# 凭据重复授权优化

日期：2026-09-06

问题：模型每轮请求、API 设置、数据库重连及 Mongo Shell 都直接读取同一 Keychain 项目，设置保存还会重复写入未修改的凭据。当前 Debug 产物使用 ad hoc 签名，检查其 designated requirement 确认为绑定二进制内容，重新构建后的系统授权还会受到签名身份变化影响。

## 本轮改动

- 在 `ConnectionVault` 内统一复用成功读取或保存的凭据，各数据库与模型密钥按原 UUID 分开存储，仅在进程内存保留。同一凭据的并发读取串行执行，后续调用复用成功结果；未修改凭据不重复写 Keychain。
- 缺失项目、取消、拒绝和其他读取错误不缓存，保留手动重试。保存与删除先使旧值失效，只有保存成功才复用新值。
- 应用启动时注册系统/显示器休眠、用户会话退出活动状态及 Keychain 锁定/外部项目变更通知。清理可以在系统授权尚未结束时执行，晚到的读取不能重新填充已清理的缓存。Keychain 通知注册失败时退回直接读取。
- 保留 Keychain service/account、可访问属性、原有 ACL 和 App Sandbox。现有文件型 Keychain 使用已弃用但本机仍支持的 `SecKeychainAddCallback`，本轮构建有该 API 的弃用警告；没有为了消除警告迁移凭据或调整权限。
- Debug 构建入口支持与打包脚本相同的 `TABLEVIEWER_CODE_SIGN_IDENTITY` 和 `TABLEVIEWER_DEVELOPMENT_TEAM` 参数，默认仍为 ad hoc。连续 E2E 构建可选择本机已有的稳定签名身份；未自动选择证书或修改已有凭据授权。

## 验证

| 检查 | 结果与边界 |
| --- | --- |
| `./script/test_keychain_denial.sh` | 65 条通过，包含既有 47 条拒绝恢复检查，以及本轮复用、凭据隔离、空密钥、更新/删除失败、重新读取、清理、并发和通知注册检查。合成凭据测试中 20 次并发读取仅访问一次后端。实际 macOS 通知注册成功且重复初始化不重复注册。日志：`.build/keychain-session-tests.log`。 |
| `./script/test_agent.sh` | 246 条通过，仅使用本地 HTTP fixture；未调用真实模型提供商。日志：`.build/keychain-session-agent-tests.log`。 |
| `./script/build_and_run.sh --build` | 当前 macOS arm64 Debug 构建成功，默认 ad hoc 参数路径通过。日志：`.build/keychain-session-build.log`。 |
| 脚本和签名 | `bash -n`、`git diff --check`、`codesign --verify --deep --strict` 通过；产物 App Sandbox entitlement 保留。 |

原生界面检查时应用停留在已打开的 API 设置窗口，因此保留现场，没有强制退出或覆盖其设置。当前构建产物已生成，但未确认运行中的窗口已加载新构建，不将其作为新二进制的验收。未操作真实系统凭据提示，未实测睡眠/锁定事件的投递、跨重建的稳定证书授权或实际弹窗总数；上述次数证据来自可控后端回归。

关于签名身份与 Keychain 授权的关系，参见 Apple [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) 与 [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)。正常首次授权和安全状态改变后的再次读取仍由 macOS 决定。
