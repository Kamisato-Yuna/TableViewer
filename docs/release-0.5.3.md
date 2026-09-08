# 0.5.3 发布验收

版本 0.5.3（9），关联 [Issue #31](https://github.com/Kamisato-Yuna/TableViewer/issues/31) 和 [Issue #32](https://github.com/Kamisato-Yuna/TableViewer/issues/32)。在最新 main `ca099ca` 上合并两项已授权改动，统一发布；来源目录与旧版本标签、附件保持不变。

## 集成范围

- 字体与示例入口：从 `codex/font-picker-demo-visibility` 来源工作树精确移入两份源文件增量及 [实现验收说明](font-picker-demo-visibility.md)，包含最后的 Label `.gray` 与 Menu `.tint(.gray)`。
- 空状态布局：核验 `133b316199778a0a7b3999f684a334bea870e470` 及其实现提交 `0e27e0e` 的 GPG 签名，仅移入 QueryEditorView、ObjectBrowserView、WorkspaceView 源码增量。重写统一报告，不把单项构建当作组合包验收。
- 版本递增为 0.5.3 / build 9。

## 行为

字体设置使用本机可加载字体的原生下拉菜单，保留 SF Mono 与已有手输偏好。存在其他连接时，连接标题灰色省略号菜单持续提供示例显示/隐藏，示例连接右键也可隐藏；没有其他连接时不能隐藏。隐藏不删除连接或数据、不强制切换当前数据库，移除最后一个非示例连接仍自动恢复。

查询与实体关系内容填满剩余高度，空状态底栏贴底；无脚本的查询提示与创建按钮集中居中，实体关系说明/搜索保持顶部。保留 0.5.2 的编辑器边界与历史切换崩溃修复。

## 验收

- 源码提交 `faafafe5f333db75ceb463b8b3ecbf2700ef5cc5`，PR #33 的 source/macOS CI 均通过（run `34206944790`）。
- 最终 Release 组合构建为 0.5.3（9），Developer ID 深度严格签名验证通过；632 条双语资源、8 项更新源测试、打包资源本地化探针和示例显隐脚本通过。
- 从最终应用复制并重新签名独立 bundle `local.yuna.TableViewer.Release053CombinedQA`，禁用正式更新源，实际启动验收。字体原生菜单显示本机字体，选择 Menlo 后退出并重启仍保留 Menlo。
- 使用专用合成 SQLite `qa.sqlite`：示例右键隐藏、连接标题菜单恢复和再次隐藏均通过，期间当前连接保持 Synthetic；重启后仍隐藏示例并保留当前连接。移除最后一个合成连接后 Studio 自动恢复，唯一示例连接的隐藏菜单禁用，数据库文件保留。
- 最终灰色省略号已在深色和浅色外观目视检查。查询无脚本提示与按钮集中、底栏贴底；实体关系无匹配空态和窗口放大/恢复检查通过。
- Apple 公证上传的加速与非加速通道多次返回 `HTTPClientError.deadlineExceeded`。服务器存在 In Progress 记录，但尚无 Accepted；不能视为上传完整或公证通过。正式发布、DMG/appcast 和公开下载验收仍待完成。

本轮不重复外部 PostgreSQL/MongoDB、真实模型、macOS 26 真机或生产客户端自动安装重启全链路；使用独立 bundle 与合成数据保护用户真实连接、Keychain 和窗口。
