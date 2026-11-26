import test from "node:test";
import assert from "node:assert/strict";
import {dataset,buildBatches,score} from "./lab.mjs";
function oracle(f) {return {fixtureId:f.id,title:f.title,summary:f.text,topic:f.expected.topic,suggestedTask:f.expected.task?"Test task":""};}
test("48 unique synthetic fixtures across four languages, without expected labels in requests",()=>{
  assert.equal(dataset.synthetic,true);
  assert.equal(dataset.fixtures.length,48);
  assert.equal(new Set(dataset.fixtures.map(x=>x.id)).size,48);
  const batches=buildBatches();
  assert.equal(batches.length,4);
  for(const batch of batches) {
    assert.equal(batch.request.items.length,12);
    assert.equal(new Set(batch.request.items.map(x=>x.id)).size,12);
    assert.ok(batch.request.items.every(x=>Object.keys(x).sort().join(",")==="id,text,title"));
  }
});
test("reference answers score perfectly; this is a scorer sanity check, not model quality",()=>{
  const report=score(dataset.fixtures.map(oracle));
  assert.equal(report.overall.valid,48);
  assert.equal(report.overall.topicCorrect,48);
  assert.equal(report.overall.taskCorrect,48);
  assert.equal(report.overall.anchorsMatched,report.overall.anchors);
  assert.equal(report.overall.falseTasks,0);
});
test("missing, duplicated, malformed and unexpected predictions never increase accuracy",()=>{
  const predictions=dataset.fixtures.map(oracle);
  predictions.shift();
  predictions.push({...predictions[0]});
  predictions[1].topic="invalid";
  predictions.push({...predictions[2],fixtureId:"other"});
  const report=score(predictions);
  assert.equal(report.overall.valid,45);
  assert.equal(report.overall.missing,1);
  assert.equal(report.overall.duplicates,1);
  assert.equal(report.unexpected,1);
  assert.equal(report.overall.topicCorrect,45);
});
test("reports false tasks separately and counts omissions in denominator",()=>{
  const predictions=dataset.fixtures.map(oracle);
  const first=dataset.fixtures.findIndex(x=>!x.expected.task);
  predictions[first].suggestedTask="Invented task";
  const report=score(predictions);
  assert.equal(report.overall.falseTasks,1);
  assert.equal(report.overall.taskCorrect,47);
  assert.equal(score([]).overall.valid,0);
  assert.equal(score([]).overall.total,48);
});
