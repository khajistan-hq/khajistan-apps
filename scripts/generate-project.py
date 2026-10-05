#!/usr/bin/env python3
"""Generate the checked-in Xcode project with Python's standard library."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
objects = {}
def uid(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def add(key, value):
    objects[uid(key)] = value
    return uid(key)
def quote(value): return json.dumps(value)
def array(items): return '(' + ', '.join(items) + ',)' if items else '()'
def obj(**kwargs): return '{ ' + ' '.join(f'{k} = {v};' for k,v in kwargs.items()) + ' }'

sources = sorted((root/'Khajistan').rglob('*.swift'))
app_refs=[]; app_builds=[]
for path in sources:
    rel=path.relative_to(root).as_posix()
    ref=add(rel, obj(isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=quote(rel), sourceTree='SOURCE_ROOT'))
    app_refs.append(ref)
    app_builds.append(add('build/'+rel, obj(isa='PBXBuildFile', fileRef=ref)))
assets=add('assets',obj(isa='PBXFileReference', lastKnownFileType='folder.assetcatalog', path=quote('Khajistan/Resources/Assets.xcassets'), sourceTree='SOURCE_ROOT'))
privacy=add('privacy',obj(isa='PBXFileReference', lastKnownFileType='text.xml',path=quote('Khajistan/Resources/PrivacyInfo.xcprivacy'),sourceTree='SOURCE_ROOT'))
# Every file under Khajistan/Resources/Media is copied to the bundle root (pigeon.gif, the wipe).
media=[p.relative_to(root).as_posix() for p in sorted((root/'Khajistan/Resources/Media').glob('*')) if p.is_file() and not p.name.startswith('.')]
media_refs=[add(rel,obj(isa='PBXFileReference',lastKnownFileType='image.gif' if rel.endswith('.gif') else 'file',path=quote(rel),sourceTree='SOURCE_ROOT')) for rel in media]
resource_builds=[add('build/'+ref,obj(isa='PBXBuildFile',fileRef=ref)) for ref in [assets,privacy]+media_refs]
app=add('product/app',obj(isa='PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='Khajistan.app',sourceTree='BUILT_PRODUCTS_DIR'))
test=add('product/test',obj(isa='PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex='0',path='KhajistanUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR'))
test_files=[p.relative_to(root).as_posix() for p in sorted((root/'UITests').glob('*.swift'))]
test_refs=[add('uitest/'+rel,obj(isa='PBXFileReference',lastKnownFileType='sourcecode.swift',path=quote(rel),sourceTree='SOURCE_ROOT')) for rel in test_files]
test_builds=[add('build/uitest/'+rel,obj(isa='PBXBuildFile',fileRef=ref)) for rel,ref in zip(test_files,test_refs)]
products=add('products',obj(isa='PBXGroup',children=array([app,test]),name='Products',sourceTree=quote('<group>')))
main=add('main',obj(isa='PBXGroup',children=array(app_refs+[assets,privacy]+media_refs+test_refs+[products]),sourceTree=quote('<group>')))

def phase(key,kind,files): return add(key,obj(isa=kind,buildActionMask='2147483647',files=array(files),runOnlyForDeploymentPostprocessing='0'))
app_phases=[phase('sources','PBXSourcesBuildPhase',app_builds),phase('frameworks','PBXFrameworksBuildPhase',[]),phase('resources','PBXResourcesBuildPhase',resource_builds)]
test_phases=[phase('test-sources','PBXSourcesBuildPhase',test_builds),phase('test-frameworks','PBXFrameworksBuildPhase',[]),phase('test-resources','PBXResourcesBuildPhase',[])]

def configs(key,settings):
    refs=[]
    for name in ['Debug','Release']:
        local=dict(settings)
        local.update({'SWIFT_OPTIMIZATION_LEVEL':quote('-Onone' if name=='Debug' else '-O'), 'DEBUG_INFORMATION_FORMAT':quote('dwarf' if name=='Debug' else 'dwarf-with-dsym')})
        if name=='Debug': local['SWIFT_ACTIVE_COMPILATION_CONDITIONS']=quote('DEBUG $(inherited)'); local['ENABLE_TESTABILITY']='YES'
        refs.append(add(key+'/'+name,obj(isa='XCBuildConfiguration',buildSettings=obj(**local),name=name)))
    return add(key,obj(isa='XCConfigurationList',buildConfigurations=array(refs),defaultConfigurationIsVisible='0',defaultConfigurationName='Release'))
common={'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES','TARGETED_DEVICE_FAMILY':quote('1,2')}
project_configs=configs('project-config',common)
app_settings={'PRODUCT_BUNDLE_IDENTIFIER':'com.khajistan.archive','PRODUCT_NAME':quote('$(TARGET_NAME)'),'INFOPLIST_FILE':'Khajistan/Resources/Info.plist','CODE_SIGN_STYLE':'Automatic','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'1.0','GENERATE_INFOPLIST_FILE':'NO','SUPPORTED_PLATFORMS':quote('iphoneos iphonesimulator'),'SUPPORTS_MACCATALYST':'NO','LD_RUNPATH_SEARCH_PATHS':quote('$(inherited) @executable_path/Frameworks')}
app_configs=configs('app-config',app_settings)
test_configs=configs('test-config',{'PRODUCT_BUNDLE_IDENTIFIER':'com.khajistan.archive.uitests','PRODUCT_NAME':quote('$(TARGET_NAME)'),'GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','TEST_TARGET_NAME':'Khajistan','LD_RUNPATH_SEARCH_PATHS':quote('$(inherited) @executable_path/Frameworks @loader_path/Frameworks')})
app_target=add('app-target',obj(isa='PBXNativeTarget',buildConfigurationList=app_configs,buildPhases=array(app_phases),buildRules='()',dependencies='()',name='Khajistan',productName='Khajistan',productReference=app,productType=quote('com.apple.product-type.application')))
proxy=add('test-proxy',obj(isa='PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=app_target,remoteInfo='Khajistan'))
dependency=add('test-dependency',obj(isa='PBXTargetDependency',target=app_target,targetProxy=proxy))
test_target=add('test-target',obj(isa='PBXNativeTarget',buildConfigurationList=test_configs,buildPhases=array(test_phases),buildRules='()',dependencies=array([dependency]),name='KhajistanUITests',productName='KhajistanUITests',productReference=test,productType=quote('com.apple.product-type.bundle.ui-testing')))
project=add('project',obj(isa='PBXProject',attributes=obj(BuildIndependentTargetsInParallel='YES',LastUpgradeCheck='1600'),buildConfigurationList=project_configs,compatibilityVersion=quote('Xcode 14.0'),developmentRegion='en',hasScannedForEncodings='0',knownRegions=array(['en','Base']),mainGroup=main,productRefGroup=products,projectDirPath=quote(''),projectRoot=quote(''),targets=array([app_target,test_target])))
project_dir=root/'Khajistan.xcodeproj'
project_dir.mkdir(exist_ok=True)
text='// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n'
text+='\n'.join(f'{key} = {value};' for key,value in objects.items())
text+=f'\n}};\nrootObject = {project};\n}}\n'
(project_dir/'project.pbxproj').write_text(text)
schemes=project_dir/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def reference(target,name,buildable): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{buildable}" BlueprintName="{name}" ReferencedContainer="container:Khajistan.xcodeproj"/>'
app_ref=reference(app_target,'Khajistan','Khajistan.app'); test_ref=reference(test_target,'KhajistanUITests','KhajistanUITests.xctest')
(schemes/'Khajistan.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f'Generated {len(sources)} app sources, {len(media)} media files and {len(test_files)} UI test files in {project_dir}')
