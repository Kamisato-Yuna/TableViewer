0.5.1 的正式构建与分发验证见 [0.5.1 验收记录](release-0.5.1.md)。

0.5.0 的估算、Agent 与侧栏回归和正式分发验证见 [0.5.0 验收记录](release-0.5.0.md)。

0.4.0 的工作台、脚本、三级审批和三引擎检查见 [0.4.0 验收记录](release-0.4.0.md)。

# Validation / 验证范围

0.3.0（build 4）的自动更新、签名安装、退出保护和本轮回归见 [自动更新验证](updater-validation.md)。下文保留 0.2.0 的历史验收。

Release 0.2.0 (build 3), 2026-09-06. Verified on Apple Silicon with macOS 27 beta and Xcode 27 beta 6 (27A5252f).

| Check | Evidence / Scope |
| --- | --- |
| Release build | Native arm64 app, embedded PostgreSQL and MongoDB drivers, sandboxed JavaScriptCore helper |
| Localization | 348 translated entries; both languages present; matching format arguments; no untranslated Chinese in English values |
| Native UI | English menus, data workspace, connection form, settings; language selection and restart into Simplified Chinese |
| Worker localization | Actual signed Release helper in a separate sandbox host, English and Simplified Chinese missing-parameter errors |
| SQLite | Existing integration suite: queries, writes, composite keys, pagination, BLOB and NUL handling |
| Reliability | Existing suite: query bounds, ambiguous keys, failure recovery, unsaved edits and quit warnings |
| Signed sandbox | Existing suite: temporary three-node MongoDB replica set, shell commands/cursors/stop, SQLite bookmarks, local mock AI protocol and credential handling |

Run `script/check_localizations.py`, `script/test_databases.sh`, `script/test_reliability.sh`, and the Docker-based `script/test_features.py --sandbox` as appropriate. `script/test_localizations.sh` uses a copy of the actual Release helper and requires the same signing identity as that release.

The two workspace images in `docs/screenshots/` show only the built-in Studio sample. Chinese database values remain Chinese in English mode because database content is never translated.

GitHub Actions checks Python/shell syntax and localization resources, builds the Release app on macOS, runs SQLite and reliability regression, and mounts the generated DMG to verify its layout and embedded signature. CI does not perform distribution signing or notarization. Interactive macOS 26 app compatibility, Intel, real remote TLS/SRV deployments, real AI providers, TestFlight, and App Store review are not certified by these checks.

## Apple distribution evidence

- Signing: Developer ID Application, team `852H844JG2`; Hardened Runtime and App Sandbox retained; no `get-task-allow` in Release.
- Apple notarization: **Accepted**; submission `274a1096-0cbf-45ac-b61b-9ba56c0d2e39`.
- `stapler staple` and `stapler validate`: passed.
- `spctl --assess --type execute`: accepted, `Notarized Developer ID`.
- The initial ZIP distribution has been replaced by `TableViewer-0.2.0-macOS-arm64.dmg`, containing the same app and an Applications shortcut.

This is distribution outside the Mac App Store; App Store approval has not been obtained.

凭据重复授权的本轮改动、65 条凭据回归、模型请求回归及实机边界见 [凭据复用验证](keychain-session-validation.md)。

## OrbStack 大数据量数据库验收

PostgreSQL / MongoDB 每库 10 个表或集合、每个 50,000 条仿真记录，真实驱动与原生界面场景、复现命令及覆盖口径见 [OrbStack E2E 报告](orbstack-e2e.md)。

MongoDB 三实例副本集、主从切换、多数派故障及恢复验收见 [副本集 E2E 报告](mongodb-replica-e2e.md)。
