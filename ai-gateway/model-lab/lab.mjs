import fs from "node:fs";
import {pathToFileURL} from "node:url";
const fixtureURL=new URL("./fixtures.json",import.meta.url);
const topics=new Set(["technology","learning","finance","shopping","work","media","travel","food","documents","unknown"]);
export const dataset=JSON.parse(fs.readFileSync(fixtureURL,"utf8"));
export function buildBatches(data=dataset) {
  const batches=[];
  for(const language of ["he","en","ru","mixed"]) {
    const entries=data.fixtures.filter(x=>x.language===language);
    for(let i=0;i<entries.length;i+=12) {
      const group=entries.slice(i,i+12);
      batches.push({
        group:language, batchId:language+"-"+(i/12+1),
        mapping:group.map((x,j)=>({id:"s"+j,fixtureId:x.id})),
        request:{language:language==="mixed"?"he":language,items:group.map((x,j)=>({id:"s"+j,title:x.title,text:x.text}))}
      });
    }
  }
  return batches;
}
function valid(x) {
  return x&&typeof x==="object"&&!Array.isArray(x)&&Object.keys(x).sort().join(",")==="fixtureId,suggestedTask,summary,title,topic"&&
    topics.has(x.topic)&&typeof x.title==="string"&&x.title.trim().length>0&&x.title.length<=240&&
    typeof x.summary==="string"&&x.summary.trim().length>0&&x.summary.length<=1200&&
    typeof x.suggestedTask==="string"&&x.suggestedTask.length<=300;
}
export function score(predictions,data=dataset) {
  if(!Array.isArray(predictions)) throw Error("predictions_must_be_array");
  const ids=new Set(data.fixtures.map(x=>x.id));
  const byId=new Map();
  const duplicate=new Set();
  let unexpected=0;
  for(const p of predictions) {
    if(!ids.has(p?.fixtureId)) {unexpected++;continue;}
    if(byId.has(p.fixtureId)) duplicate.add(p.fixtureId);
    else byId.set(p.fixtureId,p);
  }
  const details=data.fixtures.map(f=>{
    const p=byId.get(f.id);
    const usable=valid(p)&&!duplicate.has(f.id);
    const task=usable&&p.suggestedTask.trim().length>0;
    const topicCorrect=usable&&p.topic===f.expected.topic;
    const taskCorrect=usable&&task===f.expected.task;
    const anchors=f.expected.anchors;
    const matched=usable?anchors.filter(a=>(p.title+" "+p.summary+" "+p.suggestedTask).includes(a)).length:0;
    return {id:f.id,language:f.language,valid:Boolean(usable),missing:!p,duplicate:duplicate.has(f.id),
      topicCorrect:Boolean(topicCorrect),taskCorrect:Boolean(taskCorrect),falseTask:Boolean(usable&&task&&!f.expected.task),
      missedTask:Boolean(f.expected.task&&!task),anchors:anchors.length,matched};
  });
  function aggregate(rows) {
    return {total:rows.length,valid:rows.filter(x=>x.valid).length,missing:rows.filter(x=>x.missing).length,
      duplicates:rows.filter(x=>x.duplicate).length,topicCorrect:rows.filter(x=>x.topicCorrect).length,
      taskCorrect:rows.filter(x=>x.taskCorrect).length,falseTasks:rows.filter(x=>x.falseTask).length,
      missedTasks:rows.filter(x=>x.missedTask).length,anchors:rows.reduce((n,x)=>n+x.anchors,0),
      anchorsMatched:rows.reduce((n,x)=>n+x.matched,0)};
  }
  return {datasetVersion:data.version,synthetic:true,unexpected,overall:aggregate(details),
    byLanguage:Object.fromEntries(["he","en","ru","mixed"].map(l=>[l,aggregate(details.filter(x=>x.language===l))])),
    details,limitations:"Literal numeric substring matches are a weak diagnostic, not factual accuracy. Human review of summaries, language and task wording is required. This test covers OCR text, not image OCR."};
}
if(process.argv[1]&&pathToFileURL(process.argv[1]).href===import.meta.url) {
  const [mode,file]=process.argv.slice(2);
  if(mode==="batches"&&!file) console.log(JSON.stringify(buildBatches(),null,2));
  else if(mode==="score"&&file) console.log(JSON.stringify(score(JSON.parse(fs.readFileSync(file,"utf8"))),null,2));
  else {console.error("Usage: node lab.mjs batches | node lab.mjs score predictions.json");process.exitCode=1;}
}
