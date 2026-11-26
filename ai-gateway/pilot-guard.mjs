import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";

// Single-host, persistent pilot invocation ceiling. This is NOT a dollar cap.
// The operator must explicitly initialize a private ledger before enabling AI.
// Reserve before calling the provider; failed or uncertain calls still count.
const MAX_LIMIT=10000;
function validLimit(limit) {
  return Number.isSafeInteger(limit) && limit>=1 && limit<=MAX_LIMIT;
}
function absoluteFile(file) {
  if(typeof file!=="string" || !path.isAbsolute(file)) throw Error("absolute_ledger_path_required");
  return file;
}
function readState(file) {
  const stat=fs.lstatSync(file);
  if(!stat.isFile() || (stat.mode & 0o077)!==0 || stat.size>4096) throw Error("unsafe_ledger");
  const state=JSON.parse(fs.readFileSync(file,"utf8"));
  if(state.version!==1 || !validLimit(state.limit) || !Number.isSafeInteger(state.used) ||
      state.used<0 || state.used>state.limit || Object.keys(state).length!==3) throw Error("invalid_ledger");
  return state;
}
function syncDirectory(file) {
  const fd=fs.openSync(path.dirname(file),"r");
  try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
}
export function initializePilotLedger(file,limit) {
  file=absoluteFile(file);
  if(!validLimit(limit)) throw Error("invalid_limit");
  const fd=fs.openSync(file,"wx",0o600);
  try { fs.writeFileSync(fd,JSON.stringify({version:1,limit,used:0})); fs.fsyncSync(fd); }
  finally { fs.closeSync(fd); }
  syncDirectory(file);
}
export function createPilotGuard(file) {
  file=absoluteFile(file);
  readState(file);
  return {
    reserve() {
      // A crashed lock fails closed until the operator investigates.
      const lock=file+".lock";
      fs.mkdirSync(lock,{mode:0o700});
      const tmp=file+"."+randomUUID()+".tmp";
      try {
        const state=readState(file);
        if(state.used>=state.limit) return false;
        const fd=fs.openSync(tmp,"wx",0o600);
        try { fs.writeFileSync(fd,JSON.stringify({...state,used:state.used+1})); fs.fsyncSync(fd); }
        finally { fs.closeSync(fd); }
        fs.renameSync(tmp,file);
        syncDirectory(file);
        return true;
      } finally {
        if(fs.existsSync(tmp)) fs.unlinkSync(tmp);
        fs.rmdirSync(lock);
      }
    }
  };
}
