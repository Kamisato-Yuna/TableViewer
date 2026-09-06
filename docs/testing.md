# Validation / 验证范围

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

GitHub Actions checks Python/shell syntax and localization resources. It does not build or notarize the macOS app. macOS 26 runtime, Intel, real remote TLS/SRV deployments, real AI providers, TestFlight, and App Store review are not certified by these checks.

## Apple distribution evidence

- Signing: Developer ID Application, team `852H844JG2`; Hardened Runtime and App Sandbox retained; no `get-task-allow` in Release.
- Apple notarization: **Accepted**; submission `274a1096-0cbf-45ac-b61b-9ba56c0d2e39`.
- `stapler staple` and `stapler validate`: passed.
- `spctl --assess --type execute`: accepted, `Notarized Developer ID`.
- Public asset: `TableViewer-0.2.0-macOS-arm64.zip`, containing the stapled app.

This is distribution outside the Mac App Store; App Store approval has not been obtained.
