import {test} from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {randomBytes,createHash} from "node:crypto";
import {initializePilotLedger,createPilotGuard} from "./pilot-guard.mjs";
import {report,html} from "./pilot-admin.mjs";
function fixture(t){
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"screenmind-admin-"));
 t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 const global=path.join(dir,"global.json");initializePilotLedger(global,20);
 const records=["alpha","beta","gamma"].map(id=>{
   const token=randomBytes(32).toString("base64url");
   const ledger=path.join(dir,id+".json");initializePilotLedger(ledger,5);
   return {id,ledger,tokenSha256:createHash("sha256").update(token).digest("hex")};
 });
 const manifest=path.join(dir,"manifest.json");
 fs.writeFileSync(manifest,JSON.stringify({version:1,tenants:records}),{mode:0o600});
 return {global,manifest,records};
}
test("reports actual counters without mutation or leaking credentials",t=>{
 const f=fixture(t);
 for(let i=0;i<5;i++)createPilotGuard(f.records[0].ledger).reserve();
 for(let i=0;i<4;i++)createPilotGuard(f.records[1].ledger).reserve();
 for(let i=0;i<9;i++)createPilotGuard(f.global).reserve();
 const before=fs.readFileSync(f.global,"utf8"),r=report(f.manifest,f.global);
 assert.equal(r.exhausted,1);assert.equal(r.nearLimit,1);assert.equal(r.global.remaining,11);
 assert.deepEqual(r.tenants.map(x=>x.status),["exhausted","near_limit","available"]);
 assert.equal(fs.readFileSync(f.global,"utf8"),before);
 for(const x of f.records){
   for(const output of [JSON.stringify(r),html(r)]){assert.ok(!output.includes(x.tokenSha256));assert.ok(!output.includes(x.ledger));}
 }
 assert.match(html(r),/dir="rtl"/);
});
test("rejects invalid and unavailable ledger rather than inventing counts",t=>{
 const f=fixture(t);fs.unlinkSync(f.records[0].ledger);
 assert.throws(()=>report(f.manifest,f.global));
});
test("HTML escapes report text",()=>{
 const rendered=html({generatedAt:"<script>",global:{used:0,limit:1,remaining:1},participants:1,exhausted:0,nearLimit:0,tenants:[{id:"<script>",used:0,limit:1,remaining:1,status:"available"}]});
 assert.ok(!rendered.includes("<script>"));assert.ok(rendered.includes("&lt;script&gt;"));
});
