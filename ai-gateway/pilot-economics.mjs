import fs from "node:fs";
import { pathToFileURL } from "node:url";
// Offline scenario estimator. All rates are operator-provided hypotheses, never live billing or a dollar cap.
export function estimate(x){
  const keys=["participants","requestsPerParticipant","inputTokens","outputTokens","inputUSDPerMillion","outputUSDPerMillion","fixedUSD","priceUSD","payingShare","feeShare","reserveShare","budgetUSD"];
  for(const k of keys) if(typeof x[k]!=="number"||!Number.isFinite(x[k])||x[k]<0)throw Error("invalid_"+k);
  for(const k of keys.slice(0,4))if(!Number.isSafeInteger(x[k])||x[k]>10000000)throw Error("invalid_count_"+k);
  for(const k of ["payingShare","feeShare","reserveShare"])if(x[k]>1)throw Error("invalid_fraction_"+k);
  const requests=x.participants*x.requestsPerParticipant;
  const perRequest=(x.inputTokens*x.inputUSDPerMillion+x.outputTokens*x.outputUSDPerMillion)/1000000;
  const providerUSD=requests*perRequest, reservedProviderUSD=providerUSD*(1+x.reserveShare);
  const totalUSD=reservedProviderUSD+x.fixedUSD;
  const paying=Math.floor(x.participants*x.payingShare);
  const netRevenueUSD=paying*x.priceUSD*(1-x.feeShare);
  const maxBudgetRequests=perRequest>0?Math.min(10000,Math.max(0,Math.floor((x.budgetUSD-x.fixedUSD)/(perRequest*(1+x.reserveShare))))):null;
  return {requests,providerUSD,reservedProviderUSD,totalUSD,paying,netRevenueUSD,contributionUSD:netRevenueUSD-totalUSD,withinBudget:totalUSD<=x.budgetUSD,maxBudgetRequests,ledgerLimit:requests<=10000?requests:null};
}
export const illustrativeScenario = {
  "participants": 20,
  "requestsPerParticipant": 50,
  "inputTokens": 3000,
  "outputTokens": 600,
  "inputUSDPerMillion": 1,
  "outputUSDPerMillion": 4,
  "fixedUSD": 10,
  "priceUSD": 5,
  "payingShare": 0.2,
  "feeShare": 0.15,
  "reserveShare": 0.25,
  "budgetUSD": 30
};
if(process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url){
  try { const x=process.argv[2]?JSON.parse(fs.readFileSync(process.argv[2],"utf8")):illustrativeScenario; console.log(JSON.stringify({illustrative:!process.argv[2],estimate:estimate(x),warning:"Not a price quote, actual usage measurement, or enforced spending cap."},null,2)); }
  catch(e){ console.error(e.message);process.exitCode=1; }
}
