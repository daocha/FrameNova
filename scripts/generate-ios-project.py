#!/usr/bin/env python3
"""Generate the dependency-free iOS and desktop project from repository sources."""
import hashlib
import json
import pathlib
import plistlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
IOS = ROOT / 'ios'
PROJECT = IOS / 'FrameNova.xcodeproj'
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def obj(object_key, isa, **fields):
    key = ident(object_key)
    objects[key] = dict(isa=isa, **fields)
    return key

def file_ref(path, kind):
    return obj('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')

def phase(name, isa, files):
    return obj(name, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)

def buildfile(path, kind):
    return obj('build:' + path, 'PBXBuildFile', fileRef=file_ref(path, kind))

sources = sorted(IOS.glob('FrameNova/**/*.swift'))
source_paths = [str(p.relative_to(IOS)) for p in sources]
resources = ['FrameNova/Resources/Assets.xcassets', 'FrameNova/Resources/PrivacyInfo.xcprivacy', 'FrameNova/Resources/DownloadFonts.json',
             '../android/app/src/main/assets/preview_filler.mp4', '../LICENSE']
resources += [str(p.relative_to(ROOT)).replace('android/', '../android/', 1) for p in sorted((ROOT / 'android/app/src/main/res/font').glob('*')) if p.suffix in ('.ttf', '.otf')]
resources += ['../' + str(p.relative_to(ROOT)) for p in sorted((ROOT / 'third_party/fonts').glob('*'))]

def resource_type(path):
    if path.endswith('.xcassets'): return 'folder.assetcatalog'
    if path.endswith('.xcprivacy'): return 'text.xml'
    return 'file'

source_phase = phase('sources', 'PBXSourcesBuildPhase', [buildfile(p, 'sourcecode.swift') for p in source_paths])
resource_phase = phase('resources', 'PBXResourcesBuildPhase', [buildfile(p, resource_type(p)) for p in resources])
framework_phase = phase('frameworks', 'PBXFrameworksBuildPhase', [])
app = obj('product', 'PBXFileReference', explicitFileType='wrapper.application', path='FrameNova.app', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
products = obj('products', 'PBXGroup', children=[app], name='Products', sourceTree='<group>')
main = obj('main', 'PBXGroup', children=[file_ref(p, 'sourcecode.swift') for p in source_paths] + [file_ref(p, resource_type(p)) for p in resources] + [products], sourceTree='<group>')
gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
version = re.search(r'versionName = "([^"]+)"', gradle).group(1)
code = re.search(r'versionCode = (\d+)', gradle).group(1)
base = dict(SWIFT_VERSION='5.0', IPHONEOS_DEPLOYMENT_TARGET='17.0', MACOSX_DEPLOYMENT_TARGET='14.0',
            TARGETED_DEVICE_FAMILY='1,2', SUPPORTS_MACCATALYST='YES', SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD='NO',
            DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER='NO', SDKROOT='iphoneos', SUPPORTED_PLATFORMS='iphoneos iphonesimulator macosx',
            CODE_SIGN_STYLE='Automatic', **{'CODE_SIGN_ENTITLEMENTS[sdk=macosx*]':'FrameNova/Resources/Desktop.entitlements'}, PRODUCT_NAME='FrameNova', PRODUCT_MODULE_NAME='FrameNova',
            MARKETING_VERSION=version, CURRENT_PROJECT_VERSION=code, INFOPLIST_FILE='FrameNova/Resources/Info.plist',
            GENERATE_INFOPLIST_FILE='NO', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',
            ENABLE_USER_SCRIPT_SANDBOXING='YES', CLANG_ENABLE_MODULES='YES', SWIFT_EMIT_LOC_STRINGS='YES')
configs = []
for config in ['Debug', 'Release']:
    settings = dict(base, PRODUCT_BUNDLE_IDENTIFIER='com.framenova.app' + ('.debug' if config == 'Debug' else ''),
                    SWIFT_OPTIMIZATION_LEVEL='-Onone' if config == 'Debug' else '-O', DEBUG_INFORMATION_FORMAT='dwarf' if config == 'Debug' else 'dwarf-with-dsym')
    if config == 'Debug': settings.update(SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG', ENABLE_TESTABILITY='YES')
    configs.append(obj('target:' + config, 'XCBuildConfiguration', name=config, buildSettings=settings))
target_configs = obj('targetConfigs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationName='Release', defaultConfigurationIsVisible=0)
target = obj('target', 'PBXNativeTarget', name='FrameNova', buildConfigurationList=target_configs,
             buildPhases=[source_phase, framework_phase, resource_phase], buildRules=[], dependencies=[], productName='FrameNova', productReference=app, productType='com.apple.product-type.application')
project_configs = obj('projectConfigs', 'XCConfigurationList', buildConfigurations=[obj('project:' + c, 'XCBuildConfiguration', name=c, buildSettings={}) for c in ['Debug', 'Release']], defaultConfigurationName='Release', defaultConfigurationIsVisible=0)
test_files = [str(p.relative_to(IOS)) for p in sorted((IOS / 'Tests/FrameNovaAppTests').glob('*.swift'))]
test_sources = phase('testSources', 'PBXSourcesBuildPhase', [buildfile(p, 'sourcecode.swift') for p in test_files])
test_product = obj('testProduct', 'PBXFileReference', explicitFileType='wrapper.cfbundle', path='FrameNovaTests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
objects[products]['children'].append(test_product)
objects[main]['children'] += [file_ref(p, 'sourcecode.swift') for p in test_files]
proxy = obj('testProxy', 'PBXContainerItemProxy', containerPortal=ident('project'), proxyType=1, remoteGlobalIDString=target, remoteInfo='FrameNova')
dependency = obj('testDependency', 'PBXTargetDependency', target=target, targetProxy=proxy)
test_configs = []
for c in ['Debug', 'Release']:
    settings = dict(base, PRODUCT_NAME='FrameNovaTests', PRODUCT_MODULE_NAME='FrameNovaTests', PRODUCT_BUNDLE_IDENTIFIER='com.framenova.app.tests', GENERATE_INFOPLIST_FILE='YES', TEST_HOST='$(BUILT_PRODUCTS_DIR)/FrameNova.app/FrameNova', **{'TEST_HOST[sdk=macosx*]': '$(BUILT_PRODUCTS_DIR)/FrameNova.app/Contents/MacOS/FrameNova'}, BUNDLE_LOADER='$(TEST_HOST)')
    for key in ['INFOPLIST_FILE','ASSETCATALOG_COMPILER_APPICON_NAME']:
        settings.pop(key, None)
    test_configs.append(obj('test:' + c, 'XCBuildConfiguration', name=c, buildSettings=settings))
test_config_list = obj('testConfigs', 'XCConfigurationList', buildConfigurations=test_configs, defaultConfigurationName='Debug', defaultConfigurationIsVisible=0)
test_target = obj('testTarget', 'PBXNativeTarget', name='FrameNovaTests', productName='FrameNovaTests', productType='com.apple.product-type.bundle.unit-test', productReference=test_product, buildConfigurationList=test_config_list, buildPhases=[test_sources, phase('testFrameworks','PBXFrameworksBuildPhase',[])], buildRules=[], dependencies=[dependency])
project = obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '1600'}, buildConfigurationList=project_configs,
              compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en', 'Base'], mainGroup=main,
              productRefGroup=products, projectDirPath='', projectRoot='', targets=[target, test_target])

def encode(value, depth=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (depth+1) + json.dumps(str(k)) + ' = ' + encode(v, depth+1) + ';\n' for k, v in value.items()) + '\t' * depth + '}'
    if isinstance(value, list): return '(' + ', '.join(encode(v, depth+1) for v in value) + ')'
    if isinstance(value, int): return str(value)
    return json.dumps(value)

PROJECT.mkdir(exist_ok=True)
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + encode(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)) + '\n')
schemes = PROJECT / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="FrameNova.app" BlueprintName="FrameNova" ReferencedContainer="container:FrameNova.xcodeproj"/>'
(schemes / 'FrameNova.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="FrameNovaTests.xctest" BlueprintName="FrameNovaTests" ReferencedContainer="container:FrameNova.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(PROJECT)
