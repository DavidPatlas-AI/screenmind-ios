import fs from "node:fs";
import path from "node:path";
import {createHash,timingSafeEqual} from "node:crypto";
import {createPilotGuard} from "./pilot-guard.mjs";

// Private, operator-provisioned beta access. No public signup or billing.
// Only random 256-bit tokens are supported; store their SHA-256 digests.
// The configuration is loaded at startup, so revocation requires a restart.
export function createTenantAuth(file,globalLedger){
  if(typeof file!=="string"||!path.isAbsolute(file))throw Error("absolute_manifest_required");
  const stat=fs.lstatSync(file);
  if(!stat.isFile()||(stat.mode&0o077)!==0||stat.size>65536)throw Error("unsafe_manifest");
  const data=JSON.parse(fs.readFileSync(file,"utf8"));
  if(data?.version!==1||Object.keys(data).length!==2||!Array.isArray(data.tenants)||data.tenants.length<1||data.tenants.length>100)throw Error("invalid_manifest");
  const ids=new Set(),digests=new Set(),ledgers=new Set();
  function ledgerKey(file){
    if(typeof file!=="string"||!path.isAbsolute(file))throw Error("absolute_ledger_required");
    const st=fs.lstatSync(file);
    if(!st.isFile()||st.nlink!==1)throw Error("unsafe_ledger");
    return fs.realpathSync(file);
  }
  if(globalLedger)ledgers.add(ledgerKey(globalLedger));
  const entries=data.tenants.map(x=>{
    if(!x||Object.keys(x).sort().join(",")!=="id,ledger,tokenSha256"||
       typeof x.id!=="string"||!/^[a-z0-9-]{1,40}$/.test(x.id)||
       typeof x.tokenSha256!=="string"||!/^[a-f0-9]{64}$/.test(x.tokenSha256)||
       ids.has(x.id)||digests.has(x.tokenSha256))throw Error("invalid_tenant");
    const ledger=ledgerKey(x.ledger);
    if(ledgers.has(ledger)||ledger===fs.realpathSync(file))throw Error("shared_ledger");
    ids.add(x.id);digests.add(x.tokenSha256);ledgers.add(ledger);
    return {digest:Buffer.from(x.tokenSha256,"hex"),guard:createPilotGuard(ledger)};
  });
  return {
    authenticate(header){
      if(typeof header!=="string"||!/^Bearer [A-Za-z0-9_-]{43}$/.test(header))return null;
      const token=header.slice(7);
      const bytes=Buffer.from(token,"base64url");
      if(bytes.length!==32||bytes.toString("base64url")!==token)return null;
      const digest=createHash("sha256").update(token,"utf8").digest();
      let found=null;
      for(const entry of entries)if(timingSafeEqual(digest,entry.digest))found=entry.guard;
      return found;
    }
  };
}
