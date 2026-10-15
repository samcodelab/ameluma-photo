from pathlib import Path
import hashlib
root=Path(__file__).resolve().parents[1]
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key, text): objects[uid(key)]=text; return uid(key)
def arr(ids): return '('+','.join(ids)+',)'
files={}
shared = [str(p.relative_to(root)) for p in sorted((root/'Apps/Shared').glob('*.swift'))] + [str(p.relative_to(root)) for p in sorted((root/'SharedUI').glob('*.swift'))]
platform_files = ['Apps/macOS/FramepebbleMacApp.swift', 'Apps/macOS/MacZoomCapture.swift', 'Apps/macOS/MacPhotoSelectionCapture.swift', 'Apps/macOS/Automations.swift', 'Apps/macOS/FolderEvents.swift', 'Apps/macOS/BrowserDropImporter.swift', 'Apps/iOS/FramepebbleIOSApp.swift', 'Apps/iOS/PhotoLibraryExporter.swift']
for path in shared + platform_files:
    files[path]=add(path, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path}"; sourceTree = SOURCE_ROOT;}}')
files['Resources/PrivacyInfo.xcprivacy']=add('privacyfile','{isa = PBXFileReference; lastKnownFileType = text.xml; path = Resources/PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;}')
files['Resources/Assets.xcassets']=add('assetsfile','{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;}')
legal_files = ['Resources/Legal/PrivacyPolicy.md', 'Resources/Legal/Help.md', 'Resources/Distribution.plist']
for file in legal_files:
    files[file] = add(file, f'{{isa = PBXFileReference; lastKnownFileType = text; path = "{file}"; sourceTree = SOURCE_ROOT;}}')
products=[];targets=[]
package=add('package','{isa = XCLocalSwiftPackageReference; relativePath = Packages/FramepebbleCore;}')
for platform, app, bundle in [('Mac','macOS/FramepebbleMacApp.swift','com.broadframestudio.framepebble'),('iOS','iOS/FramepebbleIOSApp.swift','com.broadframestudio.framepebble.ios')]:
    name='Framepebble'+platform
    app_name = 'Ameluma Photo' if platform == 'Mac' else 'Ameluma'
    product=add(name+'product',f'{{isa = PBXFileReference; explicitFileType = wrapper.application; path = "{app_name}.app"; sourceTree = BUILT_PRODUCTS_DIR;}}');products.append(product)
    sourcebuild=[]
    for file in shared + ['Apps/'+app] + (['Apps/macOS/MacZoomCapture.swift', 'Apps/macOS/MacPhotoSelectionCapture.swift', 'Apps/macOS/Automations.swift', 'Apps/macOS/FolderEvents.swift', 'Apps/macOS/BrowserDropImporter.swift'] if platform == 'Mac' else ['Apps/iOS/PhotoLibraryExporter.swift']): sourcebuild.append(add(name+file,f'{{isa = PBXBuildFile; fileRef = {files[file]};}}'))
    dependency=add(name+'dep',f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = FramepebbleCore;}}')
    framework=add(name+'framework',f'{{isa = PBXBuildFile; productRef = {dependency};}}')
    sources=add(name+'sources',f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sourcebuild)}; runOnlyForDeploymentPostprocessing = 0;}}')
    frameworks=add(name+'frameworks',f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([framework])}; runOnlyForDeploymentPostprocessing = 0;}}')
    privacybuild=add(name+'privacybuild', f'{{isa = PBXBuildFile; fileRef = {files["Resources/PrivacyInfo.xcprivacy"]};}}')
    assetsbuild=add(name+'assetsbuild', f'{{isa = PBXBuildFile; fileRef = {files["Resources/Assets.xcassets"]};}}')
    legalbuilds = [add(name+file, f'{{isa = PBXBuildFile; fileRef = {files[file]};}}') for file in legal_files]
    resources=add(name+'resources' , f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr([privacybuild,assetsbuild]+legalbuilds)}; runOnlyForDeploymentPostprocessing = 0;}}')
    configs=[]
    for mode in ['Debug','Release']:
        settings=f'PRODUCT_NAME = "{app_name}"; PRODUCT_MODULE_NAME = {name}; EXECUTABLE_NAME = {name}; PRODUCT_BUNDLE_IDENTIFIER = {bundle if mode == "Debug" else "com.broadframestudio.framepebble"}; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "{app_name}"; INFOPLIST_KEY_CFBundleName = "{app_name}"; MARKETING_VERSION = 0.1; CURRENT_PROJECT_VERSION = 1; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; SWIFT_VERSION = 6.0; ENABLE_TESTABILITY = {"YES" if mode == "Debug" else "NO"}; CODE_SIGN_STYLE = Automatic;'
        if platform=='Mac': settings+=' INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.photography"; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 15.0; ENABLE_APP_SANDBOX = YES; CODE_SIGN_ENTITLEMENTS = Apps/macOS/FramepebbleMac.entitlements; ENABLE_USER_SELECTED_FILES = readwrite;'
        else: settings+=' SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Ameluma Photo adds finished images, such as resized photos and collages, to your Photos library when you choose Save to Photos."; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES;'
        configs.append(add(name+mode,f'{{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = {mode};}}'))
    configlist=add(name+'configs',f'{{isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
    target=add(name,f'{{isa = PBXNativeTarget; buildConfigurationList = {configlist}; buildPhases = {arr([sources,frameworks,resources])}; buildRules = (); dependencies = (); name = {name}; packageProductDependencies = {arr([dependency])}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.application";}}'); targets.append(target)
    scheme=f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{app_name}.app" BlueprintName="{name}" ReferencedContainer="container:Framepebble.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{app_name}.app" BlueprintName="{name}" ReferencedContainer="container:Framepebble.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
    folder=root/'Framepebble.xcodeproj/xcshareddata/xcschemes';folder.mkdir(parents=True,exist_ok=True);(folder/(name+'.xcscheme')).write_text(scheme)
testfiles = [str(p.relative_to(root)) for p in sorted((root/'Packages/FramepebbleCore/Tests/FramepebbleCoreTests').glob('*.swift'))] + [str(p.relative_to(root)) for p in sorted((root/'Tests').glob('*.swift'))]
for testfile in testfiles:
    files[testfile] = add(testfile, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{testfile}"; sourceTree = SOURCE_ROOT;}}')
testfile = testfiles[0]
files[testfile] = add(testfile, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{testfile}"; sourceTree = SOURCE_ROOT;}}')
name = 'FramepebbleCoreiOSTests'
product = add(name+'product', f'{{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {name}.xctest; sourceTree = BUILT_PRODUCTS_DIR;}}'); products.append(product)
dep = add(name+'dep', f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = FramepebbleCore;}}')
testbuilds = [add(name+file, f'{{isa = PBXBuildFile; fileRef = {files[file]};}}') for file in testfiles]
fb = add(name+'fb', f'{{isa = PBXBuildFile; productRef = {dep};}}')
sp = add(name+'sp', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(testbuilds)}; runOnlyForDeploymentPostprocessing = 0;}}')
fp = add(name+'fp', f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([fb])}; runOnlyForDeploymentPostprocessing = 0;}}')
cs = [add(name+m, f'{{isa = XCBuildConfiguration; buildSettings = {{PRODUCT_NAME = {name}; PRODUCT_BUNDLE_IDENTIFIER = com.broadframestudio.framepebble.coretests; GENERATE_INFOPLIST_FILE = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; TARGETED_DEVICE_FAMILY = "1,2"; SWIFT_VERSION = 6.0; ENABLE_TESTING_SEARCH_PATHS = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ameluma.app/FramepebbleiOS"; BUNDLE_LOADER = "$(TEST_HOST)"; CODE_SIGN_STYLE = Automatic;}}; name = {m};}}') for m in ['Debug','Release']]
cl = add(name+'cl', f'{{isa = XCConfigurationList; buildConfigurations = {arr(cs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
proxy = add('testproxy', f'{{isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("FramepebbleiOS")}; remoteInfo = FramepebbleiOS;}}')
td = add('testdependency', f'{{isa = PBXTargetDependency; target = {uid("FramepebbleiOS")}; targetProxy = {proxy};}}')
testtarget = add(name, f'{{isa = PBXNativeTarget; buildConfigurationList = {cl}; buildPhases = {arr([sp,fp])}; buildRules = (); dependencies = {arr([td])}; name = {name}; packageProductDependencies = {arr([dep])}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.bundle.unit-test";}}'); targets.append(testtarget)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testtarget}" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:Framepebble.xcodeproj"/>'
(root/'Framepebble.xcodeproj/xcshareddata/xcschemes/FramepebbleCoreiOSTests.xcscheme').write_text(f'<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.3"><BuildAction><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{ref}</TestableReference></Testables></TestAction></Scheme>')
name = 'FramepebbleMacTests'
mac_builds=[]
for p in sorted((root/'Tests/macOS').glob('*.swift')) + [root/'Tests/DistributionResourceTests.swift']:
    file=str(p.relative_to(root))
    files[file]=add(file,f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{file}"; sourceTree = SOURCE_ROOT;}}')
    mac_builds.append(add(name+file,f'{{isa = PBXBuildFile; fileRef = {files[file]};}}'))
product=add(name+'product',f'{{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {name}.xctest; sourceTree = BUILT_PRODUCTS_DIR;}}');products.append(product)
dep=add(name+'dep',f'{{isa = XCSwiftPackageProductDependency; package = {package}; productName = FramepebbleCore;}}')
fb=add(name+'fb',f'{{isa = PBXBuildFile; productRef = {dep};}}')
sp=add(name+'sp',f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(mac_builds)}; runOnlyForDeploymentPostprocessing = 0;}}')
fp=add(name+'fp',f'{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {arr([fb])}; runOnlyForDeploymentPostprocessing = 0;}}')
cs=[add(name+m,f'{{isa = XCBuildConfiguration; buildSettings = {{PRODUCT_NAME = {name}; PRODUCT_BUNDLE_IDENTIFIER = com.broadframestudio.framepebble.mactests; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.photography"; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 15.0; SWIFT_VERSION = 6.0; ENABLE_TESTING_SEARCH_PATHS = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ameluma Photo.app/Contents/MacOS/FramepebbleMac"; BUNDLE_LOADER = "$(TEST_HOST)";}}; name = {m};}}') for m in ['Debug','Release']]
cl=add(name+'cl',f'{{isa = XCConfigurationList; buildConfigurations = {arr(cs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
proxy=add('mactestproxy',f'{{isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("FramepebbleMac")}; remoteInfo = FramepebbleMac;}}')
td=add('mactestdependency',f'{{isa = PBXTargetDependency; target = {uid("FramepebbleMac")}; targetProxy = {proxy};}}')
testtarget=add(name,f'{{isa = PBXNativeTarget; buildConfigurationList = {cl}; buildPhases = {arr([sp,fp])}; buildRules = (); dependencies = {arr([td])}; name = {name}; packageProductDependencies = {arr([dep])}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.bundle.unit-test";}}');targets.append(testtarget)
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testtarget}" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:Framepebble.xcodeproj"/>'
(root/'Framepebble.xcodeproj/xcshareddata/xcschemes/FramepebbleMacTests.xcscheme').write_text(f'<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.3"><BuildAction><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{ref}</TestableReference></Testables></TestAction></Scheme>')
pg=add('products',f'{{isa = PBXGroup; children = {arr(products)}; name = Products; sourceTree = "<group>";}}')
group=add('main',f'{{isa = PBXGroup; children = {arr(list(files.values())+[pg])}; sourceTree = "<group>";}}')
configs=[add('project'+m,f'{{isa = XCBuildConfiguration; buildSettings = {{DEVELOPMENT_TEAM = PLQG3PMFP8; SWIFT_ACTIVE_COMPILATION_CONDITIONS = "{"DEBUG $(inherited)" if m == "Debug" else "$(inherited)"}"; CLANG_ENABLE_MODULES = YES; ONLY_ACTIVE_ARCH = {"YES" if m == "Debug" else "NO"}; SWIFT_OPTIMIZATION_LEVEL = "'+('-Onone' if m=='Debug' else '-O')+f'";}}; name = {m};}}') for m in ['Debug','Release']]
cl=add('projectconfig',f'{{isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
project=add('project',f'{{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {cl}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {group}; packageReferences = {arr([package])}; productRefGroup = {pg}; projectDirPath = ""; projectRoot = ""; targets = {arr(targets)};}}')
(root/'Framepebble.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+';}\n')
