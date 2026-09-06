# Contributing / 参与开发

欢迎中文和英文交流。用 Issues 报告可复现的问题或提出明确的功能需求；使用 Discussions 提问、分享工作流和讨论设计。

Chinese and English contributions are welcome. Use Issues for reproducible bugs and concrete feature requests, and Discussions for questions, workflows, and design ideas.

## Build

Apple Silicon Mac, macOS 26+, Xcode 26 or later with the macOS 26 SDK, and Homebrew are required. The current release was built with Xcode 27 beta 6; stable Xcode compatibility still needs verification.

```sh
brew install libpq mongo-c-driver
python3 script/bootstrap_drivers.py
./script/build_and_run.sh --build
```

Open `TableViewer.xcodeproj` to run and debug. Debug uses ad hoc signing; contributors do not need the maintainer's Apple account.

## Pull requests

1. Fork the repository and create a focused branch.
2. Describe the problem, resulting behavior, and validation. Keep unrelated formatting and generated files out of the diff.
3. Test only the affected behavior. Use disposable databases for write tests. Never paste credentials, connection URIs, real records, or private server addresses into issues, logs, or screenshots.
4. Update both `en` and `zh-Hans` in `TableViewer/Resources/Localizable.xcstrings` when changing user-facing text. Preserve interpolation placeholders and database identifiers. Restart the app after changing its language.
5. Keep App Sandbox, Keychain storage, explicit AI tool approval, and result-sharing consent intact.

Contributions are licensed under the repository's MIT license. Third-party dependencies retain their original licenses.

## Tests

```sh
./script/test_databases.sh       # SQLite integration tests
./script/test_reliability.sh     # Query limits, failures, and write safety
python3 script/test_features.py # Disposable MongoDB replica set + local mock API; Docker required
python3 script/test_features.py --sandbox # Signed sandbox host integration
```

See `Tests/` for test scope and limitations. Mock/API protocol tests do not prove compatibility with a real AI provider.
