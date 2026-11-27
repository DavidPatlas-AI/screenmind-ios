import {test} from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {randomBytes,createHash} from "node:crypto";
import {createTenantAuth} from "./tenant-auth.mjs";
import {initializePilotLedger} from "./pilot-guard.mjs";
function fixture(t){
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"screenmind-tenants-"));
  t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const global=path.join(dir,"global.json");initializePilotLedger(global,10);
  const tenants=["alpha","beta"].map(id=>{
    const token=randomBytes(32).toString("base64url");
    const ledger=path.join(dir,id+".json");initializePilotLedger(ledger,1);
    return {token,record:{id,ledger,tokenSha256:createHash("sha256").update(token).digest("hex")}};
  });
  const file=path.join(dir,"tenants.json");
  const write=(records=tenants.map(x=>x.record))=>fs.writeFileSync(file,JSON.stringify({version:1,tenants:records}),{mode:0o600});
  write();return {file,global,tenants,write};
}
test("independent quotas persist across auth reload",t=>{
  const f=fixture(t),a=createTenantAuth(f.file,f.global);
  const header=x=>"Bearer "+x.token;
  assert.equal(a.authenticate(header(f.tenants[0])).reserve(),true);
  assert.equal(a.authenticate(header(f.tenants[0])).reserve(),false);
  assert.equal(a.authenticate(header(f.tenants[1])).reserve(),true);
  assert.equal(createTenantAuth(f.file,f.global).authenticate(header(f.tenants[1])).reserve(),false);
});
test("unknown and malformed tokens denied",t=>{
  const f=fixture(t),a=createTenantAuth(f.file,f.global);
  for(const h of [undefined,"Bearer invalid","Bearer "+randomBytes(32).toString("base64url"),f.tenants[0].token])assert.equal(a.authenticate(h),null);
});
test("reject duplicate token, ledger, or global ledger",t=>{
  const f=fixture(t),[a,b]=f.tenants.map(x=>x.record);
  for(const bad of [{...b,tokenSha256:a.tokenSha256},{...b,ledger:a.ledger},{...b,ledger:f.global}]){
    f.write([a,bad]);assert.throws(()=>createTenantAuth(f.file,f.global));
  }
});
test("manifest permissions fail closed and removed tokens are revoked after restart",t=>{
  const f=fixture(t);fs.chmodSync(f.file,0o644);
  assert.throws(()=>createTenantAuth(f.file,f.global));
  fs.chmodSync(f.file,0o600);f.write([f.tenants[1].record]);
  assert.equal(createTenantAuth(f.file,f.global).authenticate("Bearer "+f.tenants[0].token),null);
});
