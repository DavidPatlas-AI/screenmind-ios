import fs from "node:fs";
import {pathToFileURL} from "node:url";
import {createHash} from "node:crypto";
import {dataset,buildBatches,score} from "./lab.mjs";

const digest=x=>createHash("sha256").update(JSON.stringify(x)).digest("hex");
export const datasetHash=digest(dataset);
const providers=["openai","gemini","bedrock"];
const batches=buildBatches();
const keys=(x,k)=>x&&typeof x==="object"&&!Array.isArray(x)&&Object.keys(x).sort().join(",")===k;
const count=x=>Number.isSafeInteger(x)&&x>=0&&x<=1000000000;
const ratio=(a,b)=>b?a/b:null;
const validModel=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$/.test(x);
export function compare(runs,rates=[]){
 if(!Array.isArray(runs)||runs.length<1||runs.length>20||!Array.isArray(rates)||rates.length>100)throw Error("invalid_comparison");
 const priceMap=new Map();
 for(const r of rates){
   if(!keys(r,"inputUSDPerMillion,model,outputUSDPerMillion,provider")||!providers.includes(r.provider)||!validModel(r.model)||
     ![r.inputUSDPerMillion,r.outputUSDPerMillion].every(x=>typeof x==="number"&&Number.isFinite(x)&&x>=0&&x<=100000))throw Error("invalid_rate");
   const k=JSON.stringify([r.provider,r.model]);if(priceMap.has(k))throw Error("duplicate_rate");priceMap.set(k,r);
 }
 const seen=new Set();let protocol=null;
 const models=runs.map(run=>{
   if(!keys(run,"batches,datasetHash,model,protocolHash,provider")||run.datasetHash!==datasetHash||!providers.includes(run.provider)||!validModel(run.model)||
     typeof run.protocolHash!=="string"||!/^[a-f0-9]{64}$/.test(run.protocolHash)||!Array.isArray(run.batches)||run.batches.length!==batches.length)throw Error("invalid_run");
   if(protocol!==null&&protocol!==run.protocolHash)throw Error("different_protocols");protocol=run.protocolHash;
   const key=JSON.stringify([run.provider,run.model]);if(seen.has(key))throw Error("duplicate_model");seen.add(key);
   const remaining=new Map(batches.map(b=>[b.batchId,b])),predictions=[];
   let failed=0,unexpected=0,measured=0,input=0,output=0,latencies=[];
   for(const b of run.batches){
     if(!keys(b,"batchId,durationMs,items,usage")||!remaining.has(b.batchId)||!count(b.durationMs)||b.durationMs===0||
       !(b.items===null||Array.isArray(b.items)&&b.items.length<=24))throw Error("invalid_batch_result");
     const fixture=remaining.get(b.batchId);remaining.delete(b.batchId);latencies.push(b.durationMs);
     if(b.usage!==null){
       if(!keys(b.usage,"input,output")||![b.usage.input,b.usage.output].every(count))throw Error("invalid_usage");
       measured++;input+=b.usage.input;output+=b.usage.output;
     }
     if(b.items===null){failed++;continue;}
     const map=new Map(fixture.mapping.map(x=>[x.id,x.fixtureId]));
     for(const item of b.items){
       if(!map.has(item?.id)){unexpected++;continue;}
       const fixtureId=map.get(item.id);
       if(!keys(item,"id,suggestedTask,summary,title,topic")){predictions.push({fixtureId});continue;}
       const {id,...rest}=item;predictions.push({fixtureId,...rest});
     }
   }
   const s=score(predictions),o=s.overall,rate=priceMap.get(key);
   const estimate=rate&&measured?(input*rate.inputUSDPerMillion+output*rate.outputUSDPerMillion)/1e6:null;
   latencies.sort((a,b)=>a-b);
   const median=(latencies[Math.floor((latencies.length-1)/2)]+latencies[Math.floor(latencies.length/2)])/2;
   const criteria={valid:ratio(o.valid,o.total),topic:ratio(o.topicCorrect,o.total),task:ratio(o.taskCorrect,o.total),anchors:ratio(o.anchorsMatched,o.anchors)};
   const eligible=o.valid===o.total&&unexpected===0&&s.unexpected===0&&failed===0&&o.falseTasks===0&&criteria.topic>=.85&&criteria.task>=.85&&Object.values(s.byLanguage).every(l=>ratio(l.topicCorrect,l.total)>=.75);
   return {provider:run.provider,model:run.model,eligibleForHumanReview:eligible,criteria,overall:o,byLanguage:s.byLanguage,failedBatches:failed,unexpectedItems:unexpected+s.unexpected,
     durationMs:{median,max:latencies.at(-1)},usage:{measuredBatches:measured,unmeasuredBatches:batches.length-measured,input,output,estimatedMeasuredUSD:estimate},
     comparableEstimatedUSD:measured===batches.length&&estimate!==null?estimate:null};
 });
 // Pareto front only for models with complete cost measurements and passing quality gates.
 const pool=models.filter(m=>m.eligibleForHumanReview&&m.comparableEstimatedUSD!==null);
 const vector=m=>[m.criteria.topic,m.criteria.task,m.criteria.anchors??0,-m.durationMs.median,-m.comparableEstimatedUSD];
 const dominates=(a,b)=>{const x=vector(a),y=vector(b);return x.every((v,i)=>v>=y[i])&&x.some((v,i)=>v>y[i]);};
 return {datasetHash,protocolHash:protocol,synthetic:true,models,
  candidates:pool.filter(m=>!pool.some(n=>n!==m&&dominates(n,m))).map(({provider,model})=>({provider,model})),
  notice:"No automatic winner. Synthetic text labels and numeric anchors are weak diagnostics. Human review, independent holdout and verified provider terms are required. Missing usage is not zero cost. Supplied rates are estimates, not bills."};
}
if(process.argv[1]&&pathToFileURL(process.argv[1]).href===import.meta.url){
 try{
  const [mode,file,ratesFile,...extra]=process.argv.slice(2);
  if(extra.length)throw Error("invalid_arguments");
  if(mode==="template"&&!file){
   console.log(JSON.stringify({provider:"openai",model:"replace-with-exact-model",datasetHash,protocolHash:"replace-with-sha256-of-common-protocol",batches:batches.map(({batchId})=>({batchId,durationMs:null,items:null,usage:null}))},null,2));
  }else if(mode==="compare"&&file){
   console.log(JSON.stringify(compare(JSON.parse(fs.readFileSync(file,"utf8")),ratesFile?JSON.parse(fs.readFileSync(ratesFile,"utf8")):[]),null,2));
  }else throw Error("invalid_arguments");
 }catch(e){console.error("Comparison failed: "+e.message);process.exitCode=1;}
}
