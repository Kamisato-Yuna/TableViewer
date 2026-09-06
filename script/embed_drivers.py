#!/usr/bin/env python3
import os
import pathlib
import shutil
import subprocess
root = pathlib.Path(__file__).resolve().parent.parent
identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or '-'
destination = pathlib.Path(os.environ['TARGET_BUILD_DIR']) / os.environ['FRAMEWORKS_FOLDER_PATH']
destination.mkdir(parents=True, exist_ok=True)
for source in (root / '.build/lib').glob('*.dylib'):
    if source.is_symlink():
        continue
    target = destination / source.name
    shutil.copy2(source, target)
    subprocess.check_call(['codesign', '--force', '--sign', identity, *(['--timestamp'] if identity != '-' else []), str(target)])
resources = pathlib.Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH']
resources.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'TableViewer/Resources/MongoShell.js', resources / 'MongoShell.js')
shutil.copytree(root / 'TableViewer/Resources/ThirdPartyNotices', resources / 'ThirdPartyNotices', dirs_exist_ok=True)

# A sandboxed helper must inherit the parent sandbox; the app executable has
# additional entitlements and cannot be relaunched as that helper.
helper_dir = pathlib.Path(os.environ['TARGET_BUILD_DIR']) / os.environ['CONTENTS_FOLDER_PATH'] / 'Helpers'
helper_dir.mkdir(parents=True, exist_ok=True)
intermediates = pathlib.Path(os.environ['DERIVED_FILE_DIR'])
intermediates.mkdir(parents=True, exist_ok=True)
bridge = intermediates / 'MongoShellBridge.o'
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
target = f"{os.environ['ARCHS'].split()[0]}-apple-macos{os.environ['MACOSX_DEPLOYMENT_TARGET']}"
subprocess.check_call(['xcrun', 'clang', '-target', target, '-isysroot', sdk, '-c', str(root / 'Native/MongoBridge.c'), '-I', str(root / '.build/include'), '-o', str(bridge)])
helper = helper_dir / 'TableViewerShell'
subprocess.check_call([
    'xcrun', 'swiftc', '-parse-as-library', '-O', '-swift-version', '5', '-target', target, '-sdk', sdk,
    '-module-cache-path', str(intermediates / 'ShellModuleCache'),
    '-import-objc-header', str(root / 'Native/TableViewer-Bridging-Header.h'),
    '-I', str(root / '.build/include/postgresql'), '-L', str(root / '.build/lib'),
    '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
    '-lmongoc2', '-lbson2', '-framework', 'JavaScriptCore',
    str(root / 'TableViewer/Models/DatabaseModels.swift'), str(root / 'TableViewer/Services/MongoShellRuntime.swift'),
    str(root / 'Native/MongoShellMain.swift'), str(bridge), '-o', str(helper),
])
# Match Xcode: hardened runtime requires a real signing identity for bundled
# third-party libraries; ad hoc development builds have no Team ID.
runtime_options = ['--timestamp', '--options', 'runtime'] if identity != '-' else []
subprocess.check_call(['codesign', '--force', '--sign', identity, *runtime_options,
                       '--entitlements', str(root / 'Native/MongoShell.entitlements'), str(helper)])
