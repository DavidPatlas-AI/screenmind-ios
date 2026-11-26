import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { initializePilotLedger, createPilotGuard } from "./pilot-guard.mjs";
function fixture(t) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"screenmind-pilot-"));
  t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  return path.join(dir,"ledger.json");
}
test("reservation persists across provider restarts and stops at ceiling",t=>{
  const file=fixture(t);
  initializePilotLedger(file,2);
  assert.equal(createPilotGuard(file).reserve(),true);
  assert.equal(createPilotGuard(file).reserve(),true);
  assert.equal(createPilotGuard(file).reserve(),false);
  assert.deepEqual(JSON.parse(fs.readFileSync(file,"utf8")),{version:1,limit:2,used:2});
});
test("missing ledger and corrupt ledger fail closed",t=>{
  const file=fixture(t);
  assert.throws(()=>createPilotGuard(file));
  initializePilotLedger(file,5);
  const guard=createPilotGuard(file);
  fs.writeFileSync(file,"not json");
  assert.throws(()=>guard.reserve());
});
test("initialization never overwrites existing reservations",t=>{
  const file=fixture(t);
  initializePilotLedger(file,2);
  createPilotGuard(file).reserve();
  assert.throws(()=>initializePilotLedger(file,100));
  assert.equal(JSON.parse(fs.readFileSync(file,"utf8")).used,1);
});
test("invalid limits and unsafe file permissions rejected",t=>{
  const file=fixture(t);
  for(const limit of [0,-1,1.5,10001,NaN]) assert.throws(()=>initializePilotLedger(file,limit));
  assert.throws(()=>initializePilotLedger("relative.json",2));
  initializePilotLedger(file,2);
  fs.chmodSync(file,0o644);
  assert.throws(()=>createPilotGuard(file),/unsafe_ledger/);
});
test("existing lock stops concurrent or uncertain reservation",t=>{
  const file=fixture(t);
  initializePilotLedger(file,2);
  const guard=createPilotGuard(file);
  fs.mkdirSync(file+".lock");
  assert.throws(()=>guard.reserve());
  assert.equal(JSON.parse(fs.readFileSync(file,"utf8")).used,0);
});
