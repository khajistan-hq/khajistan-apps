#!/usr/bin/env python3
"""Generate the checked-in tvOS Xcode project with Python's standard library.

    python3 tvos/scripts/generate-project.py

App sources are every .swift file under KhajistanTV/, UI test sources every .swift file under
UITests/. The Top Shelf extension (KhajistanTopShelf.appex, embedded in the app) compiles every
.swift file under TopShelf/ with KhajistanTV/Core/ and Services/Keychain.swift, and every file under KhajistanTV/Resources/Media is a bundle resource of the app
(copied to the bundle root, so Bundle.main.url(forResource: "pigeon", withExtension: "gif")
finds it). Object ids are sha256 of a stable key, so a re-run over the same files writes the
same bytes. An empty or missing UITests/ or Media/ still produces a project.
"""
from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parent.parent  # tvos/
APP, TESTS, SHELF = 'KhajistanTV', 'KhajistanTVUITests', 'KhajistanTopShelf'
ICON = 'App Icon & Top Shelf Image'
objects = {}
def uid(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def add(key, value):
    objects[uid(key)] = value
    return uid(key)
def quote(value): return json.dumps(value, ensure_ascii=False)
def array(items): return '(' + ', '.join(items) + ',)' if items else '()'
def obj(**kwargs): return '{ ' + ' '.join(f'{k} = {v};' for k,v in kwargs.items()) + ' }'

def sources(folder, prefix='build/'):
    base = root / folder
    refs, builds = [], []
    for path in ([base] if base.is_file() else sorted(base.rglob('*.swift'), key=lambda p: p.as_posix()) if base.is_dir() else []):
        rel = path.relative_to(root).as_posix()
        ref = add(rel, obj(isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=quote(rel), sourceTree='SOURCE_ROOT'))
        refs.append(ref)
        builds.append(add(prefix + rel, obj(isa='PBXBuildFile', fileRef=ref)))
    return refs, builds
app_refs, app_builds = sources(APP)
test_refs, test_builds = sources('UITests')
shelf_refs, shelf_builds = sources('TopShelf')
shared_builds = sources(f'{APP}/Core', 'shelf-build/')[1] + sources(f'{APP}/Services/Keychain.swift', 'shelf-build/')[1]
plain = lambda rel, kind: add(rel, obj(isa='PBXFileReference', lastKnownFileType=kind, path=quote(rel), sourceTree='SOURCE_ROOT'))
# The extension draws the pigeon on its transmission slides: the catalog's master, copied as a file.
shelf_pigeon_ref = plain(f'{APP}/Resources/Assets.xcassets/Pigeon.imageset/pigeon.png', 'image.png')
extras = [shelf_pigeon_ref, plain('TopShelf/Info.plist', 'text.plist.xml'), plain('TopShelf/TopShelf.entitlements', 'text.plist.entitlements'), plain(f'{APP}/Resources/{APP}.entitlements', 'text.plist.entitlements')]
assets = add('assets', obj(isa='PBXFileReference', lastKnownFileType='folder.assetcatalog', path=quote(f'{APP}/Resources/Assets.xcassets'), sourceTree='SOURCE_ROOT'))
privacy = add('privacy', obj(isa='PBXFileReference', lastKnownFileType='text.xml', path=quote(f'{APP}/Resources/PrivacyInfo.xcprivacy'), sourceTree='SOURCE_ROOT'))
media_dir = root / APP / 'Resources' / 'Media'
media = sorted((p for p in media_dir.rglob('*') if p.is_file() and not p.name.startswith('.')), key=lambda p: p.as_posix()) if media_dir.is_dir() else []
media_refs = [add(p.relative_to(root).as_posix(), obj(isa='PBXFileReference', lastKnownFileType='image.gif' if p.suffix.lower() == '.gif' else 'file', path=quote(p.relative_to(root).as_posix()), sourceTree='SOURCE_ROOT')) for p in media]
resource_builds = [add('build/' + ref, obj(isa='PBXBuildFile', fileRef=ref)) for ref in [assets, privacy] + media_refs]
app = add('product/app', obj(isa='PBXFileReference', explicitFileType='wrapper.application', includeInIndex='0', path=f'{APP}.app', sourceTree='BUILT_PRODUCTS_DIR'))
shelf = add('product/shelf', obj(isa='PBXFileReference', explicitFileType=quote('wrapper.app-extension'), includeInIndex='0', path=f'{SHELF}.appex', sourceTree='BUILT_PRODUCTS_DIR'))
test = add('product/test', obj(isa='PBXFileReference', explicitFileType='wrapper.cfbundle', includeInIndex='0', path=f'{TESTS}.xctest', sourceTree='BUILT_PRODUCTS_DIR'))
products = add('products', obj(isa='PBXGroup', children=array([app, shelf, test]), name='Products', sourceTree=quote('<group>')))
main = add('main', obj(isa='PBXGroup', children=array(app_refs + [assets, privacy] + media_refs + shelf_refs + extras + test_refs + [products]), sourceTree=quote('<group>')))

def phase(key, kind, files): return add(key, obj(isa=kind, buildActionMask='2147483647', files=array(files), runOnlyForDeploymentPostprocessing='0'))
embed_shelf = add('build/embed-shelf', obj(isa='PBXBuildFile', fileRef=shelf, settings=obj(ATTRIBUTES='(RemoveHeadersOnCopy, )')))
embed = add('embed', obj(isa='PBXCopyFilesBuildPhase', buildActionMask='2147483647', dstPath=quote(''), dstSubfolderSpec='13', files=array([embed_shelf]), name=quote('Embed Foundation Extensions'), runOnlyForDeploymentPostprocessing='0'))
app_phases = [phase('sources', 'PBXSourcesBuildPhase', app_builds), phase('frameworks', 'PBXFrameworksBuildPhase', []), phase('resources', 'PBXResourcesBuildPhase', resource_builds), embed]
shelf_pigeon = add('shelf-build/pigeon', obj(isa='PBXBuildFile', fileRef=shelf_pigeon_ref))
shelf_phases = [phase('shelf-sources', 'PBXSourcesBuildPhase', shared_builds + shelf_builds), phase('shelf-frameworks', 'PBXFrameworksBuildPhase', []), phase('shelf-resources', 'PBXResourcesBuildPhase', [shelf_pigeon])]
test_phases = [phase('test-sources', 'PBXSourcesBuildPhase', test_builds), phase('test-frameworks', 'PBXFrameworksBuildPhase', []), phase('test-resources', 'PBXResourcesBuildPhase', [])]

def configs(key, settings):
    refs = []
    for name in ['Debug', 'Release']:
        local = dict(settings)
        local.update({'SWIFT_OPTIMIZATION_LEVEL': quote('-Onone' if name == 'Debug' else '-O'), 'DEBUG_INFORMATION_FORMAT': quote('dwarf' if name == 'Debug' else 'dwarf-with-dsym')})
        if name == 'Debug': local['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = quote('DEBUG $(inherited)'); local['ENABLE_TESTABILITY'] = 'YES'; local['ONLY_ACTIVE_ARCH'] = 'YES'
        refs.append(add(key + '/' + name, obj(isa='XCBuildConfiguration', buildSettings=obj(**local), name=name)))
    return add(key, obj(isa='XCConfigurationList', buildConfigurations=array(refs), defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
common = {'TVOS_DEPLOYMENT_TARGET': '17.0', 'SDKROOT': 'appletvos', 'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'TARGETED_DEVICE_FAMILY': '3'}
project_configs = configs('project-config', common)
app_settings = {'PRODUCT_BUNDLE_IDENTIFIER': 'com.khajistan.tv', 'PRODUCT_NAME': quote('$(TARGET_NAME)'), 'INFOPLIST_FILE': f'{APP}/Resources/Info.plist', 'CODE_SIGN_STYLE': 'Automatic', 'ASSETCATALOG_COMPILER_APPICON_NAME': quote(ICON), 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '1.0', 'GENERATE_INFOPLIST_FILE': 'NO', 'SUPPORTED_PLATFORMS': quote('appletvos appletvsimulator'), 'SUPPORTS_MACCATALYST': 'NO', 'LD_RUNPATH_SEARCH_PATHS': quote('$(inherited) @executable_path/Frameworks'), 'CODE_SIGN_ENTITLEMENTS': f'{APP}/Resources/{APP}.entitlements', 'COPY_PHASE_STRIP': 'NO'}
app_configs = configs('app-config', app_settings)
test_configs = configs('test-config', {'PRODUCT_BUNDLE_IDENTIFIER': 'com.khajistan.tv.uitests', 'PRODUCT_NAME': quote('$(TARGET_NAME)'), 'GENERATE_INFOPLIST_FILE': 'YES', 'CODE_SIGN_STYLE': 'Automatic', 'TEST_TARGET_NAME': APP, 'LD_RUNPATH_SEARCH_PATHS': quote('$(inherited) @executable_path/Frameworks @loader_path/Frameworks')})
shelf_configs = configs('shelf-config', {'PRODUCT_BUNDLE_IDENTIFIER': 'com.khajistan.tv.topshelf', 'PRODUCT_NAME': quote('$(TARGET_NAME)'), 'INFOPLIST_FILE': 'TopShelf/Info.plist', 'CODE_SIGN_STYLE': 'Automatic', 'CODE_SIGN_ENTITLEMENTS': 'TopShelf/TopShelf.entitlements', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '1.0', 'GENERATE_INFOPLIST_FILE': 'NO', 'SUPPORTED_PLATFORMS': quote('appletvos appletvsimulator'), 'SKIP_INSTALL': 'YES', 'APPLICATION_EXTENSION_API_ONLY': 'YES', 'LD_RUNPATH_SEARCH_PATHS': quote('$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks')})
shelf_target = add('shelf-target', obj(isa='PBXNativeTarget', buildConfigurationList=shelf_configs, buildPhases=array(shelf_phases), buildRules='()', dependencies='()', name=SHELF, productName=SHELF, productReference=shelf, productType=quote('com.apple.product-type.app-extension')))
shelf_proxy = add('shelf-proxy', obj(isa='PBXContainerItemProxy', containerPortal=uid('project'), proxyType='1', remoteGlobalIDString=shelf_target, remoteInfo=SHELF))
shelf_dependency = add('shelf-dependency', obj(isa='PBXTargetDependency', target=shelf_target, targetProxy=shelf_proxy))
app_target = add('app-target', obj(isa='PBXNativeTarget', buildConfigurationList=app_configs, buildPhases=array(app_phases), buildRules='()', dependencies=array([shelf_dependency]), name=APP, productName=APP, productReference=app, productType=quote('com.apple.product-type.application')))
proxy = add('test-proxy', obj(isa='PBXContainerItemProxy', containerPortal=uid('project'), proxyType='1', remoteGlobalIDString=app_target, remoteInfo=APP))
dependency = add('test-dependency', obj(isa='PBXTargetDependency', target=app_target, targetProxy=proxy))
test_target = add('test-target', obj(isa='PBXNativeTarget', buildConfigurationList=test_configs, buildPhases=array(test_phases), buildRules='()', dependencies=array([dependency]), name=TESTS, productName=TESTS, productReference=test, productType=quote('com.apple.product-type.bundle.ui-testing')))
attributes = obj(BuildIndependentTargetsInParallel='YES', LastUpgradeCheck='2600', TargetAttributes=obj(**{test_target: obj(TestTargetID=app_target)}))
project = add('project', obj(isa='PBXProject', attributes=attributes, buildConfigurationList=project_configs, compatibilityVersion=quote('Xcode 14.0'), developmentRegion='en', hasScannedForEncodings='0', knownRegions=array(['en', 'Base']), mainGroup=main, productRefGroup=products, projectDirPath=quote(''), projectRoot=quote(''), targets=array([app_target, shelf_target, test_target])))
project_dir = root / f'{APP}.xcodeproj'
project_dir.mkdir(exist_ok=True)
text = '// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n'
text += '\n'.join(f'{key} = {value};' for key, value in objects.items())
text += f'\n}};\nrootObject = {project};\n}}\n'
(project_dir / 'project.pbxproj').write_text(text, encoding='utf-8')
schemes = project_dir / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
def reference(target, name, buildable): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{buildable}" BlueprintName="{name}" ReferencedContainer="container:{APP}.xcodeproj"/>'
app_ref = reference(app_target, APP, f'{APP}.app'); test_ref = reference(test_target, TESTS, f'{TESTS}.xctest')
(schemes / f'{APP}.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding='utf-8')
if not (root / APP / 'Resources/Info.plist').exists(): print(f'warning: {APP}/Resources/Info.plist is missing; the app target will not build', file=sys.stderr)
print(f'Generated {len(app_refs)} app sources, {len(media_refs)} media resources, {len(shelf_builds)} Top Shelf sources and {len(test_refs)} UI test sources in {project_dir}')
