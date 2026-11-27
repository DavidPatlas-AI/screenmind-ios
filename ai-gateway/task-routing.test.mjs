import {test} from "node:test";
import assert from "node:assert/strict";
import {taskPolicy,createTaskRouter} from "./task-routing.mjs";
const base={SCREENMIND_PROVIDER:"openai",OPENAI_MODEL:"fixture-default"};
const reviewed={...base,SCREENMIND_ROUTE_MODELS_REVIEWED:"yes",SCREENMIND_ROUTE_MODELS:JSON.stringify({"/analyze":"fixture-small","/answer":"fixture-large","/article":"fixture-large"})};
test("default preserves one configured model",()=>{
 const p=taskPolicy(base);
 assert.deepEqual(p.models,["fixture-default"]);
 for(const op of ["/analyze","/answer","/article"])assert.equal(p.modelFor(op),"fixture-default");
 assert.throws(()=>p.modelFor("/unknown"));
});
test("reviewed overrides dispatch by operation; reuse transport",async()=>{
 const p=taskPolicy(reviewed),initialized=[],calls=[];
 const r=await createTaskRouter(p,async m=>{initialized.push(m);return async payload=>{calls.push(m);return payload};});
 assert.deepEqual(initialized,["fixture-small","fixture-large"]);
 for(const op of ["/analyze","/article","/answer"])assert.equal(await r.dispatch(op,"fixture"),"fixture");
 assert.deepEqual(calls,["fixture-small","fixture-large","fixture-large"]);
});
test("transport failure does not retry or switch model",async()=>{
 const calls=[],r=await createTaskRouter(taskPolicy(reviewed),async m=>async()=>{calls.push(m);throw Error("fixture_failure")});
 await assert.rejects(r.dispatch("/answer",{}),/fixture_failure/);
 assert.deepEqual(calls,["fixture-large"]);
});
test("unreviewed overrides, unknown routes, invalid model identifiers and disabled mode reject",()=>{
 for(const env of [
 {...reviewed,SCREENMIND_ROUTE_MODELS_REVIEWED:"no"},
 {...reviewed,SCREENMIND_ROUTE_MODELS:'{"/unrecognized":"fixture"}'},
 {...reviewed,SCREENMIND_ROUTE_MODELS:'{"/answer":"https://example.invalid"}'},
 {...reviewed,SCREENMIND_PROVIDER:"disabled"},
 {...reviewed,SCREENMIND_ROUTE_MODELS:"[]"},
 {...reviewed,SCREENMIND_ROUTE_MODELS:"{}"}
 ])assert.throws(()=>taskPolicy(env));
 assert.deepEqual(taskPolicy({}).models,[]);
});
test("Gemini and Bedrock identifiers are provider-specific",()=>{
 const g={SCREENMIND_PROVIDER:"gemini",GEMINI_MODEL:"gemini-fixture",SCREENMIND_ROUTE_MODELS_REVIEWED:"yes"};
 assert.equal(taskPolicy({...g,SCREENMIND_ROUTE_MODELS:'{"/answer":"gemini-fixture-large"}'}).modelFor("/answer"),"gemini-fixture-large");
 assert.throws(()=>taskPolicy({...g,SCREENMIND_ROUTE_MODELS:'{"/answer":"fixture-openai"}'}));
 const b={SCREENMIND_PROVIDER:"bedrock",BEDROCK_MODEL_ID:"amazon.fixture",SCREENMIND_ROUTE_MODELS_REVIEWED:"yes"};
 assert.equal(taskPolicy({...b,SCREENMIND_ROUTE_MODELS:'{"/answer":"anthropic.fixture"}'}).modelFor("/answer"),"anthropic.fixture");
 assert.throws(()=>taskPolicy({...b,SCREENMIND_ROUTE_MODELS:'{"/answer":"arn:aws:bedrock:fixture"}'}));
});
