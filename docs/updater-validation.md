# 0.3.0 自动更新验证

日期：2026-09-06。版本：0.3.0，build 4。平台：Apple Silicon、macOS 27 beta、Xcode 27 beta 6。

Sparkle 2.9.6 负责版本比较、签名校验、下载、解压和安装。应用从 `https://kamisato-yuna.github.io/TableViewer/appcast.xml` 检查正式版本，从本仓库 GitHub Releases 下载 DMG。菜单与设置提供手动检查，默认每天自动检查，后台下载/正常退出后安装由用户开启。

更新归档使用独立 Ed25519 公钥验证；私钥保存在本机 Keychain，未导出。保留 App Sandbox、数据库/Agent 退出提醒、Developer ID 签名和 Apple 公证。新增的 Mach 通信权限仅用于 Sparkle 安装与状态服务。Release 从内到外重签 Sparkle 辅助程序并包含其许可证。

## 原生客户端验收

`script/test_update_fixture.py` 复制真实应用到独立目录，分别使用 `local.yuna.TableViewer.UpdateFixture`、`local.yuna.TableViewer.AutomaticUpdateFixture` 沙箱标识。临时测试签名密钥在签署/验证后删除，服务器仅监听 localhost。原 TableViewer 窗口与真实数据库未参与测试。

| 场景 | 观察结果 |
| --- | --- |
| 篡改归档 | 客户端发现更新；安装时提示“此更新未正确签名，无法验证其真实性”；取消后仍为 0.2.99、build 3。 |
| 手动更新 | 换为有效签名清单后可重新检查、下载、解压，点击“安装并重启应用”后自动重启；设置显示 0.3.0，原路径内 build 为 4。 |
| 无更新 | 再次检查提示“0.3.0 是当前的最新版本”。 |
| 设置 | 自动检查开启后自动下载开关可用，两项均可启用并持久保留。 |
| 自动下载 | 第二个客户端没有手动检查或点击安装，后台完成下载，设置显示“更新已下载，将在退出应用后安装”。 |
| 未保存保护 | 修改独立 Studio 示例记录但不保存，退出时出现未保存提示。取消退出后仍为旧版本且测试草稿保留，更新未强制安装。 |
| 退出安装 | 撤销测试草稿并正常退出，原路径 build 自动变为 4；再次打开设置显示 0.3.0，两项自动更新设置仍开启。 |

服务器日志：`.build/updater-fixture.log`、`.build/updater-automatic-fixture.log`。测试目录：`.build/update-e2e-kekhh5_x`、`.build/update-e2e-pe1713zl`。这些是本地验收产物，不是公开安装包。测试副本重新签名后未单独公证，不能表述为两个历史正式发行版本间的更新；正式 DMG 的签名、公证与公开下载另行验证。

## 检查与公证

- 更新清单发布 8 项测试通过：旧版本无清单、清单未下载、版本/大小不符、缺失签名、其他仓库链接和损坏 XML。
- Keychain 65 项、Agent 246 项、Agent 跨库/恢复 24 项、数据库可靠性 27 项、SQLite 集成通过。
- 449 条英文与简体中文资源检查通过；签名沙箱 helper 的两种语言实测通过。
- Release 构建、嵌套签名、App Sandbox entitlement、DMG 布局与 Pages 本地构建通过。
- 最终应用公证 Accepted：`3b95f44d-2651-4319-9eef-278d3f56be33`。
- 最终 DMG 公证 Accepted：`78de4d75-da56-449b-bc98-02b49602ff47`。应用和 DMG 的 stapling、票据验证、Gatekeeper 检查通过。

0.2.0 未内置更新器，需要手动安装一次 0.3.0，之后支持应用内更新。本轮只发布 Apple Silicon/macOS 26+ 的 Developer ID 直接下载包，未进行 App Store 提交。
