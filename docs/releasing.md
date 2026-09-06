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

The package script builds Release, timestamps nested code, and verifies a fresh app bundle before replacing the generated `dist/TableViewer.app`. Release disables injected debugger entitlements while preserving App Sandbox and Hardened Runtime. Notarization submits to Apple, waits for Accepted, staples and validates the ticket, assesses Gatekeeper, and creates a ZIP with the stapled app. The profile name is an identifier, not a credential; never paste its secret contents into a log.

Run affected integration tests and check both app languages before publishing. Upload only the final `TableViewer-VERSION-macOS-arm64.zip` to GitHub Releases. Keep build caches, raw submission uploads, original local packages, and test outputs out of Git. Tag the exact source used to build the app.

## Mac App Store

See [China preparation](app-store/preparation.md). Developer ID notarization is for distribution outside the store. Use App Store distribution signing/provisioning and a supported RC or stable toolchain for review. Do not change the bundle identifier of an existing distribution without planning data-container and Keychain compatibility.

Privacy-policy and support URLs, screenshots, availability, pricing, review contact, age rating, China compliance information when applicable, and export compliance must be complete in App Store Connect before submission. The repository contains drafts; it does not contain the maintainer's private contact information or regulatory documents.
