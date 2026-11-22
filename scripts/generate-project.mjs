import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const personal = process.env.SCREENMIND_PERSONAL === "1";
const bundle = process.env.SCREENMIND_BUNDLE_ID || "app.screenmind.next";
const group = process.env.SCREENMIND_APP_GROUP || "group.app.screenmind.next";
const team = process.env.SCREENMIND_TEAM_ID || "";
if (!/^[A-Za-z0-9.-]+$/.test(bundle) || !/^group\.[A-Za-z0-9.-]+$/.test(group)) throw Error("Invalid signing identifiers");
const id = label => crypto.createHash("sha256").update("screenmind-ios:"+label).digest("hex").slice(0,24).toUpperCase();
const objects = {};
const add = (name, value) => { const key = id(name); objects[key] = value; return key; };
const appFiles = ["Shared/Capture.swift","Shared/Vault.swift","Shared/BackupArchive.swift","Shared/SpacePrompt.swift","ScreenMind/ScreenMindApp.swift","ScreenMind/NativeLibrary.swift","ScreenMind/PhotoService.swift","ScreenMind/TextRecognition.swift","ScreenMind/AlbumScan.swift","ScreenMind/AlbumCleanupView.swift","ScreenMind/NativeHome.swift","ScreenMind/NativeActions.swift","ScreenMind/LibraryViews.swift","ScreenMind/ReviewFlow.swift","ScreenMind/CaptureDetail.swift","ScreenMind/CleanupView.swift","ScreenMind/IdeasBrain.swift","ScreenMind/IdeasBrainView.swift","ScreenMind/UITestLaunch.swift"];
const shareFiles = ["Shared/Capture.swift","Shared/Vault.swift","Shared/SpacePrompt.swift","ShareExtension/ShareViewController.swift"];
const testFiles = ["ScreenMindTests/ScreenMindTests.swift"];
const uiTestFiles = ["ScreenMindUITests/ScreenMindUITests.swift"];
for (const file of new Set([...appFiles,...shareFiles,...testFiles,...uiTestFiles])) if(!fs.existsSync(path.join(root,file))) throw Error("Missing source: "+file);
for (const file of ["ScreenMind/tessdata/heb.traineddata","ScreenMind/tessdata/eng.traineddata","ScreenMindTests/Fixtures/hebrew-sample.png"]) {
  if(!fs.existsSync(path.join(root,file))) throw Error("Missing resource: "+file);
}
const sourceRefs = {};
for(const file of new Set([...appFiles,...shareFiles,...testFiles,...uiTestFiles])) sourceRefs[file] = add("file:"+file,{isa:"PBXFileReference",lastKnownFileType:"sourcecode.swift",path:file,sourceTree:"SOURCE_ROOT"});
const appProduct=add("product:app",{isa:"PBXFileReference",explicitFileType:"wrapper.application",includeInIndex:0,path:"ScreenMind.app",sourceTree:"BUILT_PRODUCTS_DIR"});
const shareProduct=add("product:share",{isa:"PBXFileReference",explicitFileType:"wrapper.app-extension",includeInIndex:0,path:"ScreenMindShare.appex",sourceTree:"BUILT_PRODUCTS_DIR"});
const testProduct=add("product:test",{isa:"PBXFileReference",explicitFileType:"wrapper.cfbundle",includeInIndex:0,path:"ScreenMindTests.xctest",sourceTree:"BUILT_PRODUCTS_DIR"});
const uiTestProduct=add("product:uitest",{isa:"PBXFileReference",explicitFileType:"wrapper.cfbundle",includeInIndex:0,path:"ScreenMindUITests.xctest",sourceTree:"BUILT_PRODUCTS_DIR"});
const assetRef=add("assets",{isa:"PBXFileReference",lastKnownFileType:"folder.assetcatalog",path:"ScreenMind/Assets.xcassets",sourceTree:"SOURCE_ROOT"});
const privacyRef=add("privacy",{isa:"PBXFileReference",lastKnownFileType:"text.xml",path:"ScreenMind/PrivacyInfo.xcprivacy",sourceTree:"SOURCE_ROOT"});
const tessdataRef=add("tessdata",{isa:"PBXFileReference",name:"tessdata",lastKnownFileType:"folder",path:"ScreenMind/tessdata",sourceTree:"SOURCE_ROOT"});
const hebrewSampleRef=add("hebrew-sample",{isa:"PBXFileReference",name:"hebrew-sample.png",lastKnownFileType:"image.png",path:"ScreenMindTests/Fixtures/hebrew-sample.png",sourceTree:"SOURCE_ROOT"});
const products=add("products",{isa:"PBXGroup",name:"Products",children:[appProduct,shareProduct,testProduct,uiTestProduct],sourceTree:"<group>"});
const sources=add("sources",{isa:"PBXGroup",name:"Sources",children:[...Object.values(sourceRefs),assetRef,privacyRef,tessdataRef,hebrewSampleRef],sourceTree:"<group>"});
const mainGroup=add("mainGroup",{isa:"PBXGroup",children:[sources,products],sourceTree:"<group>"});
const phases=(target,files,resources=[],frameworkFiles=[])=>{
 const sources=add("sources:"+target,{isa:"PBXSourcesBuildPhase",buildActionMask:2147483647,files:files.map(file=>add("build:"+target+":"+file,{isa:"PBXBuildFile",fileRef:sourceRefs[file]})),runOnlyForDeploymentPostprocessing:0});
 const frameworks=add("frameworks:"+target,{isa:"PBXFrameworksBuildPhase",buildActionMask:2147483647,files:frameworkFiles,runOnlyForDeploymentPostprocessing:0});
 const resourcePhase=add("resources:"+target,{isa:"PBXResourcesBuildPhase",buildActionMask:2147483647,files:resources.map(ref=>add("resource:"+target+":"+ref,{isa:"PBXBuildFile",fileRef:ref})),runOnlyForDeploymentPostprocessing:0});
 return [sources,frameworks,resourcePhase];
};
const common={SWIFT_VERSION:"5.0",IPHONEOS_DEPLOYMENT_TARGET:"17.0",SDKROOT:"iphoneos",CLANG_ENABLE_MODULES:"YES",CODE_SIGN_STYLE:"Automatic",TARGETED_DEVICE_FAMILY:"1,2",SWIFT_STRICT_CONCURRENCY:"minimal",...(personal?{SWIFT_ACTIVE_COMPILATION_CONDITIONS:"SCREENMIND_PERSONAL"}:{}),...(team?{DEVELOPMENT_TEAM:team}:{})};
function configurations(name,settings,project=false) {
 const values=["Debug","Release"].map(mode=>add("config:"+name+":"+mode,{isa:"XCBuildConfiguration",name:mode,buildSettings:{...common,...settings,...(mode==="Debug"?{SWIFT_OPTIMIZATION_LEVEL:"-Onone",DEBUG_INFORMATION_FORMAT:"dwarf",ENABLE_TESTABILITY:"YES",SWIFT_ACTIVE_COMPILATION_CONDITIONS:personal?"DEBUG SCREENMIND_PERSONAL":"DEBUG"}:{SWIFT_OPTIMIZATION_LEVEL:"-O",DEBUG_INFORMATION_FORMAT:"dwarf-with-dsym",SWIFT_COMPILATION_MODE:"wholemodule"}),...(project?{CODE_SIGN_STYLE:"Automatic"}:{})}}));
 return add("configList:"+name,{isa:"XCConfigurationList",buildConfigurations:values,defaultConfigurationIsVisible:0,defaultConfigurationName:"Release"});
}
const projectID=id("project"),appID=id("target:app"),shareID=id("target:share"),testID=id("target:test"),uiTestID=id("target:uitest");
const dependency=(name,target,remoteInfo=name)=> {
 const proxy=add("proxy:"+name,{isa:"PBXContainerItemProxy",containerPortal:projectID,proxyType:1,remoteGlobalIDString:target,remoteInfo});
 return add("dependency:"+name,{isa:"PBXTargetDependency",target,targetProxy:proxy});
};
const embed=add("embed",{isa:"PBXCopyFilesBuildPhase",buildActionMask:2147483647,dstPath:"",dstSubfolderSpec:13,name:"Embed App Extensions",files:[add("embedFile",{isa:"PBXBuildFile",fileRef:shareProduct,settings:{ATTRIBUTES:["RemoveHeadersOnCopy"]}})],runOnlyForDeploymentPostprocessing:0});
const tesseractPackage=add("pkg:tesseract-apple",{isa:"XCRemoteSwiftPackageReference",repositoryURL:"https://github.com/lexiaoyao20/tesseract-Apple.git",requirement:{kind:"exactVersion",version:"5.5.2"}});
const tesseractProduct=add("pkgproduct:TesseractSwift",{isa:"XCSwiftPackageProductDependency",package:tesseractPackage,productName:"TesseractSwift"});
const tesseractLink=add("build:app:TesseractSwift",{isa:"PBXBuildFile",productRef:tesseractProduct});
objects[shareID]={isa:"PBXNativeTarget",name:"ScreenMindShare",productName:"ScreenMindShare",productType:"com.apple.product-type.app-extension",productReference:shareProduct,buildConfigurationList:configurations("share",{PRODUCT_BUNDLE_IDENTIFIER:bundle+".share",PRODUCT_NAME:"$(TARGET_NAME)",INFOPLIST_FILE:"ShareExtension/Info.plist",CODE_SIGN_ENTITLEMENTS:"ShareExtension/ScreenMindShare.entitlements",APPLICATION_EXTENSION_API_ONLY:"YES",SKIP_INSTALL:"YES",LD_RUNPATH_SEARCH_PATHS:"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"}),buildPhases:phases("share",shareFiles,[privacyRef]),buildRules:[],dependencies:[]};
objects[appID]={isa:"PBXNativeTarget",name:"ScreenMind",productName:"ScreenMind",productType:"com.apple.product-type.application",productReference:appProduct,buildConfigurationList:configurations("app",{PRODUCT_BUNDLE_IDENTIFIER:bundle,PRODUCT_NAME:"$(TARGET_NAME)",INFOPLIST_FILE:"ScreenMind/Info.plist",CODE_SIGN_ENTITLEMENTS:"ScreenMind/ScreenMind.entitlements",ASSETCATALOG_COMPILER_APPICON_NAME:"AppIcon",ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME:"AccentColor",LD_RUNPATH_SEARCH_PATHS:"$(inherited) @executable_path/Frameworks"}),buildPhases:[...phases("app",appFiles,[assetRef,privacyRef,tessdataRef],[tesseractLink]),embed],buildRules:[],dependencies:[dependency("ScreenMindShare",shareID)],packageProductDependencies:[tesseractProduct]};
objects[testID]={isa:"PBXNativeTarget",name:"ScreenMindTests",productName:"ScreenMindTests",productType:"com.apple.product-type.bundle.unit-test",productReference:testProduct,buildConfigurationList:configurations("test",{PRODUCT_BUNDLE_IDENTIFIER:bundle+".tests",PRODUCT_NAME:"$(TARGET_NAME)",GENERATE_INFOPLIST_FILE:"YES",BUNDLE_LOADER:"$(TEST_HOST)",TEST_HOST:"$(BUILT_PRODUCTS_DIR)/ScreenMind.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ScreenMind",LD_RUNPATH_SEARCH_PATHS:"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"}),buildPhases:phases("test",testFiles,[hebrewSampleRef]),buildRules:[],dependencies:[dependency("ScreenMind",appID)]};
objects[uiTestID]={isa:"PBXNativeTarget",name:"ScreenMindUITests",productName:"ScreenMindUITests",productType:"com.apple.product-type.bundle.ui-testing",productReference:uiTestProduct,buildConfigurationList:configurations("uitest",{PRODUCT_BUNDLE_IDENTIFIER:bundle+".uitests",PRODUCT_NAME:"$(TARGET_NAME)",GENERATE_INFOPLIST_FILE:"YES",TEST_TARGET_NAME:"ScreenMind",LD_RUNPATH_SEARCH_PATHS:"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"}),buildPhases:phases("uitest",uiTestFiles),buildRules:[],dependencies:[dependency("ScreenMindUI",appID,"ScreenMind")]};
objects[projectID]={isa:"PBXProject",attributes:{LastUpgradeCheck:"1600",LastSwiftUpdateCheck:"1600",TargetAttributes:{[appID]:{CreatedOnToolsVersion:"16.0",SystemCapabilities:{"com.apple.ApplicationGroups.iOS":{enabled:1}}},[shareID]:{CreatedOnToolsVersion:"16.0",SystemCapabilities:{"com.apple.ApplicationGroups.iOS":{enabled:1}}},[testID]:{CreatedOnToolsVersion:"16.0",TestTargetID:appID},[uiTestID]:{CreatedOnToolsVersion:"16.0",TestTargetID:appID}}},buildConfigurationList:configurations("project",{},true),compatibilityVersion:"Xcode 14.0",developmentRegion:"he",hasScannedForEncodings:0,knownRegions:["he","en","Base"],mainGroup,packageReferences:[tesseractPackage],productRefGroup:products,projectDirPath:"",projectRoot:"",targets:[appID,shareID,testID,uiTestID]};
function plist(value,depth=0) {
 const pad="\t".repeat(depth),next="\t".repeat(depth+1);
 if(Array.isArray(value))return "(\n"+value.map(v=>next+plist(v,depth+1)+",").join("\n")+"\n"+pad+")";
 if(typeof value==="object")return "{\n"+Object.entries(value).map(([k,v])=>next+JSON.stringify(k)+" = "+plist(v,depth+1)+";").join("\n")+"\n"+pad+"}";
 return typeof value==="number"?String(value):JSON.stringify(value);
}
if (personal) {
 objects[appID].buildPhases = objects[appID].buildPhases.filter(phase => phase !== embed);
 objects[appID].dependencies = [];
 objects[projectID].targets = [appID, testID, uiTestID];
 objects[projectID].attributes.TargetAttributes[appID].SystemCapabilities = {};
 for (const key of objects[objects[appID].buildConfigurationList].buildConfigurations) {
  objects[key].buildSettings.CODE_SIGN_ENTITLEMENTS = "";
  objects[key].buildSettings.PRODUCT_BUNDLE_IDENTIFIER = bundle + ".personal";
 }
}
const projectDir=path.join(root,"ScreenMind.xcodeproj");
fs.mkdirSync(path.join(projectDir,"xcshareddata","xcschemes"),{recursive:true});
fs.writeFileSync(path.join(projectDir,"project.pbxproj"),"// !$*UTF8*$!\n"+plist({archiveVersion:1,classes:{},objectVersion:56,objects,rootObject:projectID})+"\n");
const ref=(target,name,blueprint)=>'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'+target+'" BuildableName="'+name+'" BlueprintName="'+blueprint+'" ReferencedContainer="container:ScreenMind.xcodeproj"/>';
const scheme='<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'+ref(appID,"ScreenMind.app","ScreenMind")+'</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">'+ref(testID,"ScreenMindTests.xctest","ScreenMindTests")+'</TestableReference><TestableReference skipped="NO">'+ref(uiTestID,"ScreenMindUITests.xctest","ScreenMindUITests")+'</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+ref(appID,"ScreenMind.app","ScreenMind")+'</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+ref(appID,"ScreenMind.app","ScreenMind")+'</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>';
fs.writeFileSync(path.join(projectDir,"xcshareddata","xcschemes","ScreenMind.xcscheme"),scheme);
const workspace=path.join(projectDir,"project.xcworkspace");
fs.mkdirSync(path.join(workspace,"xcshareddata","swiftpm"),{recursive:true});
fs.writeFileSync(path.join(workspace,"contents.xcworkspacedata"),'<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n');
fs.writeFileSync(path.join(workspace,"xcshareddata","swiftpm","Package.resolved"),JSON.stringify({
  pins:[{identity:"tesseract-apple",kind:"remoteSourceControl",location:"https://github.com/lexiaoyao20/tesseract-Apple.git",state:{revision:"e5ab1b56b2d479ee2f2fcb86b0b91c1676d17b28",version:"5.5.2"}}],
  version:2
},null,2)+"\n");
const entitlement='<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.application-groups</key><array><string>'+group+'</string></array></dict></plist>';
for(const file of ["ScreenMind/ScreenMind.entitlements","ShareExtension/ScreenMindShare.entitlements"])fs.writeFileSync(path.join(root,file),entitlement);
const vaultPath=path.join(root,"Shared/Vault.swift");
fs.writeFileSync(vaultPath,fs.readFileSync(vaultPath,"utf8").replace(/static let groupID = "[^"]+"/,'static let groupID = "'+group+'"'));
fs.writeFileSync(path.join(root,"project-manifest.json"),JSON.stringify({bundle,group,projectID,appID,shareID,testID,uiTestID,appFiles,shareFiles,testFiles,uiTestFiles},null,2)+"\n");
console.log("Created Xcode project: app, Share Extension, unit tests, UI tests. No signing or native compilation performed.");

