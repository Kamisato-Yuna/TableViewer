# 0.5.3 发布验收

最终版本 0.5.3（10），关联 [Issue #31](https://github.com/Kamisato-Yuna/TableViewer/issues/31) 和 [Issue #32](https://github.com/Kamisato-Yuna/TableViewer/issues/32)。在最新 main `ca099ca` 上合并两项已授权改动，统一发布；来源目录与旧版本标签、附件保持不变。

## 集成范围

- 字体与示例入口：从 `codex/font-picker-demo-visibility` 来源工作树精确移入两份源文件增量及 [实现验收说明](font-picker-demo-visibility.md)，包含最后的 Label `.gray` 与 Menu `.tint(.gray)`。
- 空状态布局：核验 `133b316199778a0a7b3999f684a334bea870e470` 及其实现提交 `0e27e0e` 的 GPG 签名，仅移入 QueryEditorView、ObjectBrowserView、WorkspaceView 源码增量。重写统一报告，不把单项构建当作组合包验收。
- 最终扩展修复以 build 10 重新构建；旧范围 build 9 产物与公证均不作为发行证据。
- 工作台扩展：完整集成 `f6c84e061a6580d1854f659e1a4f4f0f096f7847` 及前序提交，关联 Issue #34；范围和用户视觉验收见 [工作台扩展验收](workbench-053-extensions.md)。

## 行为

字体设置使用本机可加载字体的原生下拉菜单，保留 SF Mono 与已有手输偏好。存在其他连接时，连接标题灰色省略号菜单持续提供示例显示/隐藏，示例连接右键也可隐藏；没有其他连接时不能隐藏。隐藏不删除连接或数据、不强制切换当前数据库，移除最后一个非示例连接仍自动恢复。

查询与实体关系内容填满剩余高度，空状态底栏贴底；无脚本的查询提示与创建按钮集中居中，实体关系说明/搜索保持顶部。保留 0.5.2 的编辑器边界与历史切换崩溃修复。

## 旧范围 build 9 验收记录（非最终发行证据）

- 源码提交 `faafafe5f333db75ceb463b8b3ecbf2700ef5cc5`，PR #33 的 source/macOS CI 均通过（run `34206944790`）。
- 最终 Release 组合构建为 0.5.3（9），Developer ID 深度严格签名验证通过；632 条双语资源、8 项更新源测试、打包资源本地化探针和示例显隐脚本通过。
- 从最终应用复制并重新签名独立 bundle `local.yuna.TableViewer.Release053CombinedQA`，禁用正式更新源，实际启动验收。字体原生菜单显示本机字体，选择 Menlo 后退出并重启仍保留 Menlo。
- 使用专用合成 SQLite `qa.sqlite`：示例右键隐藏、连接标题菜单恢复和再次隐藏均通过，期间当前连接保持 Synthetic；重启后仍隐藏示例并保留当前连接。移除最后一个合成连接后 Studio 自动恢复，唯一示例连接的隐藏菜单禁用，数据库文件保留。
- 最终灰色省略号已在深色和浅色外观目视检查。查询无脚本提示与按钮集中、底栏贴底；实体关系无匹配空态和窗口放大/恢复检查通过。
- Apple 公证上传的加速与非加速通道多次返回 `HTTPClientError.deadlineExceeded`。服务器存在 In Progress 记录，但尚无 Accepted；不能视为上传完整或公证通过。正式发布、DMG/appcast 和公开下载验收仍待完成。

本轮不重复外部 PostgreSQL/MongoDB、真实模型、macOS 26 真机或生产客户端自动安装重启全链路；使用独立 bundle 与合成数据保护用户真实连接、Keychain 和窗口。

## 最终 build 10 发行验收

- 最终源码 `089b71114001c5a239a105343d4843c68d1f47bf`，完整包含扩展提交 `f6c84e0`，版本 0.5.3（10）。PR source/macOS CI 通过（run `34253781931`）。
- Developer ID Release 重建、668 条双语资源、8 项更新源测试、合成工作台、编辑器交互、原生标签溢出与 SwiftUI 生命周期回归通过。本次未配置 PostgreSQL/MongoDB 端口，明确 SKIP；实现阶段的真实合成服务器证据见扩展报告。
- 最终包派生独立 bundle `local.yuna.TableViewer.Release053Build10QA` 实际启动：两份 SQLite 合成脚本分别返回 53/10 与 99，A/B/A 切换恢复原结果；上下/左右分栏、深浅色、设置按编辑器上下文打开、字号 16 与行号同步、Escape 返回工作台、侧栏标题顶部和空提示居中通过。标签溢出原生测试覆盖 30 个长标签、窄视口、首尾选择、关闭恢复和两侧离屏命中。用户对最终标签观感的验收保留，不声称与 Finder 完全相同。
- 最终应用 Apple 公证 Accepted：`f13312a8-9998-4e34-af44-01039992e337`；stapler 与 Gatekeeper 通过。
- 最终 DMG Apple 公证 Accepted：`39c86a27-d4e9-440c-be79-54c8abcc7e6c`；stapler 与 Gatekeeper 通过。DMG 为 10,272,966 字节，Sparkle 使用既有 Ed25519 密钥签名，更新版本 10。
- [PR #33](https://github.com/Kamisato-Yuna/TableViewer/pull/33) 已合并；签名标签 `v0.5.3` 指向 `2b7e1cae42455a5d9b5ecfef30ec1cf1cfd4b6b5`，合并树与已验收构建源码相同。GitHub 验证标签 GPG 签名有效。Issues #31、#32、#34 已关闭。
- [正式 Release](https://github.com/Kamisato-Yuna/TableViewer/releases/tag/v0.5.3) 已公开并为 latest，DMG 10,272,966 字节、appcast 1,130 字节，均为 uploaded；旧版本标签和附件保留。
- 从未认证公网完整下载 DMG，与本地逐字节相同；Release 和 [Pages appcast](https://kamisato-yuna.github.io/TableViewer/appcast.xml) 均与本地逐字节相同。使用应用内既有公钥独立验证下载包 Ed25519 签名通过。
- 公开下载 DMG 的 stapler/Gatekeeper 通过；只读挂载后的应用深度严格签名、stapler/Gatekeeper 通过，版本 0.5.3（10）、Applications 链接及可执行文件与最终构建一致。没有用下载包替换用户真实安装与连接。
- 最终 PR CI `34254252558`、main CI `34254532156`、Pages 部署 `34254676209` 均成功。产品页面显示 0.5.3 和正确 DMG 下载路径；首次部署缓存更新后，普通 appcast 地址也已一致。
- 最终包的 en/zh-Hans 签名沙箱资源探针、示例显隐与最后连接恢复回归全部通过；实际历史窗口显示两份合成脚本，入口正常。
