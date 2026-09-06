# Privacy / 隐私政策

Effective date / 生效日期：2026-09-06

TableViewer is an open-source macOS database client maintained by Yuna Kamisato. It has no developer-operated account service, advertising SDK, or analytics service.

TableViewer 是由 Yuna Kamisato 维护的开源 macOS 数据库客户端，没有开发者运营的账户服务、广告 SDK 或分析服务。

## Local data / 本机数据

Saved connection configuration, file bookmarks, and app preferences remain on your Mac. Database passwords, MongoDB connection URIs, and AI API keys are stored in macOS Keychain. Query and shell history remain in memory for the current session. AI conversations and pending actions are saved in the app's local container so they can be restored after restarting. The app creates an editable SQLite sample database on first launch.

连接配置、文件授权书签和偏好设置保存在本机。数据库密码、MongoDB URI 和 AI API Key 存入 macOS 钥匙串。查询和 Shell 历史在当前会话内存中保留；AI 对话及待处理操作保存在应用本地容器中，以便重启后恢复。首次启动会创建可编辑的 SQLite 示例数据库。

Successfully read or saved credentials are reused in process memory to avoid repeated Keychain prompts. This cache is cleared on display/system sleep, user-session deactivation, Keychain lock, or external Keychain item changes, and does not survive quitting the app. Failed reads are never cached; updates and deletions invalidate the previous value. Keychain remains the only persistent credential store, and existing item permissions are preserved.

成功读取或保存的凭据会在进程内存中复用，以减少重复的钥匙串弹窗。显示器或系统休眠、用户会话退出活动状态、钥匙串锁定或其他进程修改钥匙串项目时会清除缓存，退出应用后不保留。失败读取不会缓存，更新与删除会使旧值失效。凭据仍仅持久化到钥匙串，原有访问权限保持不变。

## Connections and optional AI / 网络连接与可选 AI

Database connections send commands, credentials needed for authentication, and edits directly to servers you configure. The optional AI assistant sends your messages, conversation history, and current connection name/database type to the API provider you choose. Schema is included only if you opt in. Every AI-proposed database operation requires confirmation; its results are sent to the AI provider only when you choose **Send Results & Continue**. That provider may process or retain this data under its own policy. The maintainer does not receive these requests or operate the configured services.

数据库连接直接向你配置的服务器发送命令、认证所需凭据和编辑内容。可选 AI 助手向你选择的 API 服务发送消息、对话历史和当前连接名称/数据库类型；仅在勾选时附带表结构。每项 AI 数据库操作都需要确认；结果仅在你选择“发送结果并继续”后发给 API 服务。第三方服务可能按其政策处理或保留数据，开发者不会接收这些请求，也不运营所配置的服务。

## Control, deletion and contact / 控制、删除与联系

The updater checks GitHub Pages for stable releases and downloads updates from GitHub Releases. Automatic checks run daily by default and can be disabled in Settings. Automatic downloading and installation on quit are optional. These requests disclose ordinary connection information such as your IP address and app version to GitHub; database contents, API keys, and AI conversations are not included. Sparkle system profiling is disabled.

更新器从 GitHub Pages 检查正式版本，从 GitHub Releases 下载安装包。默认每天检查一次，可在设置中关闭；自动下载及退出后安装由用户选择开启。请求会向 GitHub 提供 IP 地址、应用版本等正常连接信息，不包含数据库内容、API Key 或 AI 对话。Sparkle 系统信息统计默认关闭。

Remove saved connections in the app to remove their saved configuration and credentials. Clear the AI API key in API settings to remove it. Creating a conversation or changing connections retains earlier AI history; manage it in All Conversations. Exported CSV files and user databases remain under your control; deleting a connection does not delete them. macOS backups and third-party servers may retain separate copies.

在应用内移除连接可删除保存的配置和凭据；在 API 设置清空 Key 可移除 AI 密钥。新建对话或切换连接会保留原有 AI 历史，可在“所有会话”中管理。导出的 CSV 和用户数据库由你管理；移除连接不会删除它们。macOS 备份和第三方服务器可能另行保留副本。

For privacy questions, use [GitHub Discussions](https://github.com/Kamisato-Yuna/TableViewer/discussions). For sensitive reports, use [private security reporting](https://github.com/Kamisato-Yuna/TableViewer/security/advisories/new). Never post private records or credentials publicly.
