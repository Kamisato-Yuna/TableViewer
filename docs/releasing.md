# Releasing / 发布

Keep signing identities and notary credentials in your own Apple account and Keychain. No certificates, private keys, passwords, app-specific passwords, or provisioning profiles belong in Git.

## Developer ID distribution

```sh
export TABLEVIEWER_DEVELOPMENT_TEAM=YOUR_TEAM_ID
export TABLEVIEWER_CODE_SIGN_IDENTITY='Developer ID Application: Your Name (YOUR_TEAM_ID)'
./script/package_app.sh
./script/test_localizations.sh

# Use a previously configured notarytool Keychain profile.
export TABLEVIEWER_NOTARY_PROFILE=YOUR_KEYCHAIN_PROFILE
./script/notarize_app.sh
```

The package script builds Release, timestamps nested code, and verifies a fresh app bundle before replacing the generated `dist/TableViewer.app`. Release disables injected debugger entitlements while preserving App Sandbox and Hardened Runtime. Notarization submits to Apple, waits for Accepted, staples and validates the ticket, assesses Gatekeeper, then creates a DMG containing the stapled app and an Applications shortcut. The DMG is also signed, notarized, and stapled. The profile name is an identifier, not a credential; never paste its secret contents into a log.

Run affected integration tests and check both app languages before publishing. Upload the final `TableViewer-VERSION-macOS-arm64.dmg` and its `appcast.xml` to GitHub Releases. Keep build caches, raw submission uploads, original local packages, and test outputs out of Git. Tag the exact source used to build the app.

## 应用内自动更新（0.3.0 起）

应用使用 Sparkle 2 从 GitHub Pages 的 `appcast.xml` 检查正式版本，从 GitHub Release 下载 DMG。版本比较使用应用的 `CFBundleVersion`，每次正式更新应递增 build；用户看到的版本来自 `CFBundleShortVersionString`。菜单和设置支持手动检查，默认每天自动检查，自动下载/退出后安装由用户在设置开启。Sparkle 使用正常的应用退出流程，保留数据库修改和运行中任务的退出提示。

更新签名公钥在 `Info.plist`；本机专用签名账户名为 `local.yuna.TableViewer.updates`，私钥仅保存在 Keychain。使用同一个账户签署后续更新，不要为每次发布重新生成密钥。应用安装的是可执行代码，Git 提交和版本号不能验证用户实际下载的归档来源，因此更新归档需要 Sparkle Ed25519 签名；现有 Developer ID 签名、公证和沙箱要求仍保留。

最终 DMG 完成公证和 stapling **之后**生成清单：

```sh
./script/generate_appcast.sh
# 发布时将 dist/appcast.xml 与最终 DMG 一起上传。
```

脚本复用 Swift Package 中的 Sparkle 工具，检查签名账户的公钥与应用内公钥一致，签署最终 DMG，输出指向当前版本 GitHub Release 的清单。不要在清单签名后重新打包或修改 DMG。`script/package_app.sh` 会从内到外重签 Sparkle 的 XPC 服务与安装器，避免仅框架外壳被签名。Pages 工作流随正式 Release 发布/编辑，下载其 appcast 并同步到网站；发布时先上传完整资产再将草稿设为正式版本。

本地更新验收可运行 `python3 script/test_update_fixture.py --identity '你的 Developer ID 身份'`。该工具复制真实应用到独立目录与沙箱标识，用临时测试密钥签署归档并监听 localhost；先验证篡改包被拒绝，再按脚本输出切换有效清单，执行安装重启和无更新检查。`--automatic` 使用另一独立标识测试后台下载/退出安装。测试客户端不是正式发布物，不可上传它的应用、清单或归档。

0.2.0 没有更新器，用户需要手动安装一次 0.3.0，之后才支持应用内更新。首个更新器版本的安装链路用隔离客户端验证；未来真实生产版本之间仍应检查发现、下载、安装、重启和无更新全链路。

## Mac App Store

当前 Sparkle 集成用于 Developer ID 直接分发。正式准备 Mac App Store 目标时应移除 Sparkle 及其安装服务权限，使用 App Store 自身更新渠道。

See [China preparation](app-store/preparation.md). Developer ID notarization is for distribution outside the store. Use App Store distribution signing/provisioning and a supported RC or stable toolchain for review. Do not change the bundle identifier of an existing distribution without planning data-container and Keychain compatibility.

Privacy-policy and support URLs, screenshots, availability, pricing, review contact, age rating, China compliance information when applicable, and export compliance must be complete in App Store Connect before submission. The repository contains drafts; it does not contain the maintainer's private contact information or regulatory documents.

## Changing an existing release to DMG

For an already signed and stapled app, run `./script/notarize_dmg.sh path/to/TableViewer.app` with the same signing identity and Keychain profile environment variables. This preserves the app binary and creates the DMG without rebuilding it. Verify the mounted app and Applications link, upload the DMG, and confirm the public download works before removing the superseded ZIP asset. Keep the existing version tag when only the container format changes.

## CI coverage

The `source` job checks syntax and translations. A separate `macOS build and tests` job runs on GitHub's Apple Silicon `xcode-27` preview runner (macOS 26) and covers Release compilation, embedded drivers, SQLite integration, reliability regression, and DMG mount/layout verification. Its app is ad hoc signed and is not a distributable release. Public pull requests do not receive Apple credentials.

The workflow cancels superseded runs and has a 30-minute macOS timeout. It does not run full Docker replica-set integration on macOS runners or automate App Store submissions. Signing and notarization continue on the maintainer's Mac. The existing required `source` check is unchanged; no extra mandatory branch check is added.

The current Icon Composer resource fails in Xcode 26.6 actool, so CI uses the [Xcode 27 preview image](https://github.com/actions/runner-images/issues/14404), matching local development. Move to the supported stable image after that toolchain is available and verified. A green CI run does not establish App Store toolchain eligibility.
