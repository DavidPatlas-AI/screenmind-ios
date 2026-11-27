import {pathToFileURL} from "node:url";
import {createTenantAuth} from "./tenant-auth.mjs";
import {readPilotUsage} from "./pilot-guard.mjs";

// Counters are reservations, including failures, not successful calls or invoices.
// A live report may differ across files because there is no cross-ledger snapshot.
export function report(manifest,globalLedger){
  if(!globalLedger)throw Error("global_ledger_required");
  const tenants=createTenantAuth(manifest,globalLedger).usage().map(x=>({...x,
    status:x.remaining===0?"exhausted":x.used/x.limit>=0.8?"near_limit":"available"
  })).sort((a,b)=>a.id.localeCompare(b.id));
  const global=readPilotUsage(globalLedger);
  return {version:1,generatedAt:new Date().toISOString(),global,participants:tenants.length,
    exhausted:tenants.filter(x=>x.status==="exhausted").length,
    nearLimit:tenants.filter(x=>x.status==="near_limit").length,
    tenants,notice:"Reservations, not successful requests or billed usage. Non-atomic live snapshot. No secrets or content."};
}
const escape=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
export function html(r){
  const rows=r.tenants.map(x=>"<tr><td>"+escape(x.id)+"</td><td>"+escape(x.limit)+"</td><td>"+escape(x.used)+"</td><td>"+escape(x.remaining)+"</td><td>"+({exhausted:"מכסה נגמרה",near_limit:"קרוב לתקרה",available:"זמין"}[x.status]||"לא ידוע")+"</td></tr>").join("");
  return '<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src &apos;none&apos;; style-src &apos;unsafe-inline&apos;"><title>ScreenMind — דוח פיילוט</title><style>body{font:16px/1.6 system-ui;max-width:900px;margin:30px auto;padding:18px;background:#f4f3f8;color:#171c31}section{background:white;padding:18px;border-radius:14px;margin:16px 0}table{width:100%;border-collapse:collapse}th,td{text-align:right;padding:10px;border-bottom:1px solid #ddd}h1,h2{line-height:1.2}.scroll{overflow:auto}</style></head><body><h1>ScreenMind — דוח פיילוט</h1><p>תמונת מצב מקומית, '+escape(r.generatedAt)+'</p><section><h2>מכסה כללית</h2><p>'+escape(r.global.used)+' / '+escape(r.global.limit)+' הזמנות קריאה · נותרו '+escape(r.global.remaining)+'</p><p>'+escape(r.participants)+' משתתפים · '+escape(r.exhausted)+' מיצו מכסה · '+escape(r.nearLimit)+' קרובים לתקרה</p></section><section class="scroll"><h2>מכסות אישיות</h2><table><thead><tr><th>מזהה בדוי</th><th>מכסה</th><th>נוצל</th><th>נותר</th><th>מצב</th></tr></thead><tbody>'+rows+'</tbody></table></section><p>הנתונים הם הזמנות קריאה, לא חשבוניות או הצלחות. ייתכנו פערים זמניים בין קבצים. אין לפרסם דוח זה.</p></body></html>';
}
if(process.argv[1]&&pathToFileURL(process.argv[1]).href===import.meta.url){
  try{
    const [manifest,global,format,...extra]=process.argv.slice(2);
    if(!manifest||!global||extra.length||(format!==undefined&&format!=="--html"))throw Error("usage");
    const r=report(manifest,global);
    console.log(format==="--html"?html(r):JSON.stringify(r,null,2));
  }catch{console.error("Unable to read a valid private pilot manifest and ledgers. See README.");process.exitCode=1;}
}
