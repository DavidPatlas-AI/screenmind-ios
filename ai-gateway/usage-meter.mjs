import fs from "node:fs";
import path from "node:path";
import {randomUUID} from "node:crypto";
import {pathToFileURL} from "node:url";
const providers=["openai","gemini","bedrock"];
const operations=["/analyze","/article","/answer"];
const count=n=>Number.isSafeInteger(n)&&n>=0;
const modelOK=s=>typeof s==="string"&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$/.test(s);
export function normalizeUsage(provider,data){
  let input,output,total;
  if(provider==="openai"){const u=data?.usage;input=u?.input_tokens;output=u?.output_tokens;total=u?.total_tokens;}
  else if(provider==="bedrock"){const u=data?.usage;input=u?.inputTokens;output=u?.outputTokens;total=u?.totalTokens;}
  else if(provider==="gemini"){
    const u=data?.usageMetadata;input=u?.promptTokenCount;total=u?.totalTokenCount;
    const c=u?.candidatesTokenCount,t=u?.thoughtsTokenCount??0;
    if(count(c)&&count(t))output=c+t;
  }
  if(![input,output,total].every(n=>count(n)&&n<=1000000000))return null;
  // Refuse unexplained differences (e.g. additional provider token categories).
  if(input+output!==total)return null;
  return {input,output,total};
}
function checkPath(file){if(typeof file!=="string"||!path.isAbsolute(file))throw Error("absolute_usage_path_required");return file;}
function validate(s){
  if(!s||s.version!==1||Object.keys(s).length!==2||!Array.isArray(s.rows)||s.rows.length>100)throw Error("invalid_usage_file");
  const keys=new Set();
  for(const r of s.rows){
    if(!r||Object.keys(r).sort().join(",")!=="attempts,input,measured,model,operation,output,provider,total"||
      !providers.includes(r.provider)||!modelOK(r.model)||!operations.includes(r.operation)||
      ![r.attempts,r.measured,r.input,r.output,r.total].every(count)||r.attempts<1||r.measured>r.attempts||
      r.attempts>100000||r.input+r.output!==r.total||(!r.measured&&r.total!==0))throw Error("invalid_usage_row");
    const key=JSON.stringify([r.provider,r.model,r.operation]);if(keys.has(key))throw Error("duplicate_usage_row");keys.add(key);
  }
  return s;
}
function read(file){
  const st=fs.lstatSync(file);
  if(!st.isFile()||st.nlink!==1||(st.mode&0o077)!==0||st.size>65536)throw Error("unsafe_usage_file");
  return validate(JSON.parse(fs.readFileSync(file,"utf8")));
}
function syncDir(file){const fd=fs.openSync(path.dirname(file),"r");try{fs.fsyncSync(fd)}finally{fs.closeSync(fd)}}
function writeNew(file,state){const fd=fs.openSync(file,"wx",0o600);try{fs.writeFileSync(fd,JSON.stringify(validate(state)));fs.fsyncSync(fd)}finally{fs.closeSync(fd)}}
export function initializeUsage(file){file=checkPath(file);writeNew(file,{version:1,rows:[]});syncDir(file);}
export function createUsageMeter(file){
  file=checkPath(file);read(file);let broken=false;
  function mutate(fn){
    if(broken)throw Error("usage_meter_unavailable");
    const lock=file+".lock",tmp=file+"."+randomUUID()+".tmp";let locked=false;
    try{
      fs.mkdirSync(lock,{mode:0o700});locked=true;
      const s=read(file);fn(s);writeNew(tmp,s);fs.renameSync(tmp,file);syncDir(file);
    }catch(e){broken=true;throw e;}
    finally{if(locked){if(fs.existsSync(tmp))fs.unlinkSync(tmp);fs.rmdirSync(lock);}}
  }
  return {begin(provider,model,operation){
    if(!providers.includes(provider)||!modelOK(model)||!operations.includes(operation))throw Error("invalid_usage_key");
    const matches=r=>r.provider===provider&&r.model===model&&r.operation===operation;
    mutate(s=>{
      let row=s.rows.find(matches);
      if(!row){row={provider,model,operation,attempts:0,measured:0,input:0,output:0,total:0};s.rows.push(row);}
      row.attempts++;
    });
    let observed=false;
    return data=>{
      if(observed)return;observed=true;
      const u=normalizeUsage(provider,data);if(!u)return;
      mutate(s=>{const row=s.rows.find(matches);if(!row||row.measured>=row.attempts)throw Error("missing_usage_attempt");row.measured++;row.input+=u.input;row.output+=u.output;row.total+=u.total;});
    };
  }};
}
// Rates supplied by operator, USD per million tokens, never auto-fetched.
// This simplified scenario excludes cache/discounts, extra fees and missing usage.
export function usageReport(file,rates=[]){
  if(!Array.isArray(rates)||rates.length>100)throw Error("invalid_rates");
  const map=new Map();
  for(const r of rates){
    if(!r||Object.keys(r).sort().join(",")!=="inputUSDPerMillion,model,outputUSDPerMillion,provider"||
      !providers.includes(r.provider)||!modelOK(r.model)||
      ![r.inputUSDPerMillion,r.outputUSDPerMillion].every(n=>typeof n==="number"&&Number.isFinite(n)&&n>=0&&n<=100000))throw Error("invalid_rate");
    const key=JSON.stringify([r.provider,r.model]);if(map.has(key))throw Error("duplicate_rate");map.set(key,r);
  }
  return {version:1,rows:read(checkPath(file)).rows.map(r=>{
    const rate=map.get(JSON.stringify([r.provider,r.model]));
    return {...r,unmeasured:r.attempts-r.measured,estimatedMeasuredUSD:rate&&r.measured?(r.input*rate.inputUSDPerMillion+r.output*rate.outputUSDPerMillion)/1000000:null};
  }),notice:"Measured responses only; unmeasured attempts may cost money. Operator-supplied rates; excludes cache pricing, tiers, fees and taxes. Not an invoice or budget cap."};
}
if(process.argv[1]&&pathToFileURL(process.argv[1]).href===import.meta.url){
  try{
    const [mode,file,ratesFile,...rest]=process.argv.slice(2);
    if(!file||rest.length)throw Error("usage");
    if(mode==="--init"&&!ratesFile)initializeUsage(file);
    else if(mode==="--report"){const rates=ratesFile?JSON.parse(fs.readFileSync(ratesFile,"utf8")):[];console.log(JSON.stringify(usageReport(file,rates),null,2));}
    else throw Error("usage");
  }catch{console.error("Usage: --init /private/usage.json OR --report /private/usage.json [rates.json]. Check private files and inputs.");process.exitCode=1;}
}
