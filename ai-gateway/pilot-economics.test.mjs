import {test} from "node:test";
import assert from "node:assert/strict";
import {estimate,illustrativeScenario as s} from "./pilot-economics.mjs";
test("illustrative scenario",()=>{const r=estimate(s);assert.equal(r.requests,1000);assert.ok(Math.abs(r.providerUSD-5.4)<1e-9);assert.ok(Math.abs(r.totalUSD-16.75)<1e-9);assert.equal(r.paying,4);assert.equal(r.ledgerLimit,1000);assert.ok(r.withinBudget)});
test("budget and ledger ceilings are different",()=>{const r=estimate({...s,participants:300,budgetUSD:1});assert.equal(r.maxBudgetRequests,0);assert.equal(r.ledgerLimit,null);assert.equal(r.withinBudget,false)});
test("rejects negative and invalid assumptions",()=>{for(const x of [{feeShare:1.1},{participants:2.5},{outputTokens:-1},{inputUSDPerMillion:NaN}])assert.throws(()=>estimate({...s,...x}))});
test("free token scenario has no calculated provider ceiling",()=>{assert.equal(estimate({...s,inputUSDPerMillion:0,outputUSDPerMillion:0}).maxBudgetRequests,null)});
