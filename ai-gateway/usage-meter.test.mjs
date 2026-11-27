import {test} from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {initializeUsage,createUsageMeter,normalizeUsage,usageReport} from "./usage-meter.mjs";
function fixture(t){
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"screenmind-usage-"));
 t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 const file=path.join(dir,"usage.json");
 initializeUsage(file);
 return file;
}
const openai={usage:{input_tokens:1000,output_tokens:100,total_tokens:1100},output:[{text:"private fixture"}]};
test("normalizes provider-reported token counts",()=>{
 assert.deepEqual(normalizeUsage("openai",openai),{input:1000,output:100,total:1100});
 assert.deepEqual(normalizeUsage("bedrock",{usage:{inputTokens:10,outputTokens:5,totalTokens:15}}),{input:10,output:5,total:15});
 assert.deepEqual(normalizeUsage("gemini",{usageMetadata:{promptTokenCount:10,candidatesTokenCount:2,thoughtsTokenCount:3,totalTokenCount:15}}),{input:10,output:5,total:15});
 for(const bad of [{},{usage:{input_tokens:-1,output_tokens:5,total_tokens:4}},{usage:{input_tokens:10,output_tokens:5,total_tokens:20}}])assert.equal(normalizeUsage("openai",bad),null);
});
test("unknown attempts stay unknown and persistence is aggregate only",t=>{
 const file=fixture(t),m=createUsageMeter(file);
 m.begin("openai","test-model","/answer");
 const observe=m.begin("openai","test-model","/answer");observe(openai);observe(openai);
 createUsageMeter(file).begin("openai","test-model","/article")({});
 const r=usageReport(file,[{provider:"openai",model:"test-model",inputUSDPerMillion:1,outputUSDPerMillion:4}]);
 assert.equal(r.rows.length,2);assert.equal(r.rows[0].attempts,2);assert.equal(r.rows[0].measured,1);assert.equal(r.rows[0].unmeasured,1);
 assert.ok(Math.abs(r.rows[0].estimatedMeasuredUSD-.0014)<1e-12);
 assert.equal(r.rows[1].estimatedMeasuredUSD,null);
 assert.ok(!fs.readFileSync(file,"utf8").includes("private fixture"));
});
test("unsafe files and invalid rates rejected",t=>{
 const file=fixture(t);
 assert.throws(()=>initializeUsage(file));
 assert.throws(()=>usageReport(file,[{provider:"openai",model:"test-model",inputUSDPerMillion:-1,outputUSDPerMillion:2}]));
 fs.chmodSync(file,0o644);assert.throws(()=>createUsageMeter(file));
});
test("write failure closes metering until restart",t=>{
 const file=fixture(t),m=createUsageMeter(file);
 fs.mkdirSync(file+".lock");
 assert.throws(()=>m.begin("openai","test-model","/answer"));
 fs.rmdirSync(file+".lock");
 assert.throws(()=>m.begin("openai","test-model","/answer"));
 assert.equal(usageReport(file).rows.length,0);
});
