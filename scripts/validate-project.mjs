import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import assert from "node:assert/strict";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const source=fs.readFileSync(path.join(root,"ScreenMind.xcodeproj/project.pbxproj"),"utf8");
const tokens=[];let at=0;
const pattern=/\s+|\/\/[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[A-Za-z0-9_$<>.\/+\-]+/y;
while(at<source.length){pattern.lastIndex=at;const match=pattern.exec(source);assert.ok(match,"Unexpected project syntax at "+at);at=pattern.lastIndex;if(!/^\s|^\/\//.test(match[0]))tokens.push(match[0]);}
let position=0;
function take(expected){const token=tokens[position++];if(expected)assert.equal(token,expected);return token;}
function value(){const token=take();if(token==="{"){const result={};while(tokens[position]!=="}"){const key=JSON.parse(take());take("=");result[key]=value();take(";");}take("}");return result;}if(token==="("){const result=[];while(tokens[position]!==")"){result.push(value());take(",");}take(")");return result;}return token.startsWith('"')?JSON.parse(token):Number(token);}
const project=value();assert.equal(position,tokens.length);
const objects=project.objects;assert.equal(objects[project.rootObject].isa,"PBXProject");
const referenced=new Set();
function visit(value){if(typeof value==="string"&&/^[A-F0-9]{24}$/.test(value))referenced.add(value);else if(Array.isArray(value))value.forEach(visit);else if(value&&typeof value==="object")Object.values(value).forEach(visit);}
visit(project);for(const reference of referenced)assert.ok(objects[reference],"Unresolved object "+reference);
const manifest=JSON.parse(fs.readFileSync(path.join(root,"project-manifest.json"),"utf8"));
for(const object of Object.values(objects)){
 if(object.isa==="PBXFileReference"&&object.sourceTree==="SOURCE_ROOT")assert.ok(fs.existsSync(path.join(root,object.path)),"Missing resource "+object.path);
 if(object.isa==="PBXSourcesBuildPhase")for(const ref of object.files){const file=objects[objects[ref].fileRef];assert.equal(file.lastKnownFileType,"sourcecode.swift","Folders must never be compiled as source");}
}
const membership = [[manifest.appID,manifest.appFiles],[manifest.shareID,manifest.shareFiles],[manifest.testID,manifest.testFiles]];
if(manifest.uiTestID) membership.push([manifest.uiTestID,manifest.uiTestFiles]);
for(const [targetID,expected] of membership){
 const target=objects[targetID];const compiled=target.buildPhases.map(id=>objects[id]).filter(phase=>phase.isa==="PBXSourcesBuildPhase").flatMap(phase=>phase.files.map(id=>objects[objects[id].fileRef].path));
 assert.deepEqual(compiled.sort(),[...expected].sort());
}
const app=objects[manifest.appID];assert.ok(app.dependencies.some(id=>objects[id].target===manifest.shareID));
assert.ok(app.buildPhases.map(id=>objects[id]).some(phase=>phase.isa==="PBXCopyFilesBuildPhase"&&phase.dstSubfolderSpec===13));
for(const name of ["ScreenMind/ScreenMind.entitlements","ShareExtension/ScreenMindShare.entitlements"])assert.ok(fs.readFileSync(path.join(root,name),"utf8").includes("<string>"+manifest.group+"</string>"));
assert.ok(fs.readFileSync(path.join(root,"Shared/Vault.swift"),"utf8").includes('static let groupID = "'+manifest.group+'"'));
for(const name of new Set([...manifest.appFiles,...manifest.shareFiles,...manifest.testFiles,...(manifest.uiTestFiles||[])])){
 const swift=fs.readFileSync(path.join(root,name),"utf8"),stack=[];
 let i=0;
 while(i<swift.length){
  if(swift.slice(i,i+2)==="//"){i=swift.indexOf("\n",i);if(i<0)break;continue;}
  if(swift.slice(i,i+2)==="/*"){const end=swift.indexOf("*/",i+2);assert.ok(end>=0);i=end+2;continue;}
  if(swift[i]==='"'){i++;while(i<swift.length){if(swift[i]==="\\"){i+=2;continue;}if(swift[i++]==='"')break;}continue;}
  const char=swift[i++];if("{([".includes(char))stack.push(char);if("})]".includes(char))assert.equal(stack.pop(),{"}":"{",")":"(","]":"["}[char],name+" has unbalanced delimiters");
 }
 assert.equal(stack.length,0,name+" has unclosed delimiters");
}
const icon=fs.readFileSync(path.join(root,"ScreenMind/Assets.xcassets/AppIcon.appiconset/AppIcon.png"));
assert.equal(icon.readUInt32BE(16),1024);assert.equal(icon.readUInt32BE(20),1024);assert.equal(icon[25],2,"App Store icon must be opaque RGB");
console.log("PASS: OpenStep project syntax, all object/file references, explicit Swift build membership, embedded extension, matching App Groups, Swift delimiters and opaque 1024px icon.");
console.log("NOT RUN: Swift compiler, iOS simulator, XCTest execution, signing, device install, Photos and Files behavior.");
