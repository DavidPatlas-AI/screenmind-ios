import {test} from "node:test";
import assert from "node:assert/strict";
import {dataset,buildBatches} from "./lab.mjs";
import {compare,datasetHash} from "./compare.mjs";
const protocolHash="a".repeat(64);
function run(provider,model,{duration=1000,usage={input:1000,output:200},fail=false,falseTask=false}={}){
 const fixtures=new Map(dataset.fixtures.map(x=>[x.id,x]));
 return {provider,model,datasetHash,protocolHash,batches:buildBatches().map((b,i)=>({
   batchId:b.batchId,durationMs:duration,usage,items:fail&&i===0?null:b.mapping.map(({id,fixtureId})=>{
     const f=fixtures.get(fixtureId);
     return {id,title:"Synthetic reference",summary:f.expected.anchors.join(" ")||"Reference summary",topic:f.expected.topic,suggestedTask:f.expected.task||falseTask?"Synthetic action":""};
   })
 }))};
}
const rate=(provider,model,inputUSDPerMillion,outputUSDPerMillion)=>({provider,model,inputUSDPerMillion,outputUSDPerMillion});
test("quality gates and Pareto comparison",()=>{
 const a=run("openai","fixture-a"),b=run("gemini","fixture-b",{duration:2000});
 const r=compare([a,b],[rate("openai","fixture-a",1,2),rate("gemini","fixture-b",2,3)]);
 assert.equal(r.models[0].overall.valid,48);
 assert.equal(r.models[0].eligibleForHumanReview,true);
 assert.deepEqual(r.candidates,[{provider:"openai",model:"fixture-a"}]);
});
test("cost and speed tradeoffs retain both candidates",()=>{
 const a=run("openai","fixture-a"),b=run("gemini","fixture-b",{duration:2000});
 assert.equal(compare([a,b],[rate("openai","fixture-a",2,3),rate("gemini","fixture-b",1,2)]).candidates.length,2);
});
test("missing usage is unknown and failed batches cannot pass",()=>{
 const a=run("openai","fixture-a",{usage:null}),b=run("bedrock","fixture-b",{fail:true});
 const r=compare([a,b],[rate("openai","fixture-a",1,2),rate("bedrock","fixture-b",1,2)]);
 assert.equal(r.models[0].comparableEstimatedUSD,null);
 assert.equal(r.models[0].usage.unmeasuredBatches,4);
 assert.equal(r.models[1].failedBatches,1);
 assert.equal(r.models[1].eligibleForHumanReview,false);
 assert.deepEqual(r.candidates,[]);
});
test("false tasks and duplicate predictions fail quality gates",()=>{
 const a=run("openai","fixture-a",{falseTask:true});
 assert.equal(compare([a]).models[0].eligibleForHumanReview,false);
 const b=run("openai","fixture-b");
 b.batches[0].items.push({...b.batches[0].items[0]});
 assert.equal(compare([b]).models[0].eligibleForHumanReview,false);
});
test("reject incompatible experiments and malformed counts",()=>{
 const a=run("openai","fixture-a"),b=run("gemini","fixture-b");
 assert.throws(()=>compare([a,{...b,protocolHash:"b".repeat(64)}]));
 assert.throws(()=>compare([{...a,datasetHash:"0".repeat(64)}]));
 assert.throws(()=>compare([a,a]));
 b.batches[0].durationMs=-1;assert.throws(()=>compare([b]));
});
