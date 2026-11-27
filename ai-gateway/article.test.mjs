import test from "node:test";
import assert from "node:assert/strict";
import {validateArticleInput,validateArticleOutput} from "./article.mjs";
const body={language:"he",title:"טיוטה",items:[{id:"s0",title:"מקור",text:"נבדקו שלושה מסכים ונמצאה תקלה אחת."}]};
const output={title:"טיוטה",sections:[{heading:"בדיקה",paragraph:"המקור מתאר בדיקת שלושה מסכים.",evidence:[{id:"s0",quote:"נבדקו שלושה מסכים"}]}]};
test("accept bounded request and exact source quote",()=>{
 assert.equal(validateArticleInput(body,["he"]),true);
 assert.equal(validateArticleOutput(output,body.items),true);
});
test("reject unknown fields, language, duplicate identifiers and oversized inputs",()=>{
 for(const b of [{...body,secret:"x"},{...body,language:"bad"},{...body,items:[body.items[0],body.items[0]]},{...body,items:[{...body.items[0],text:"x".repeat(3501)}]},{...body,items:[{...body.items[0],captureID:"private"}]}])assert.equal(validateArticleInput(b,["he"]),false);
});
test("reject missing evidence, wrong source and fabricated quote",()=>{
 for(const e of [[],[{id:"s1",quote:"נבדקו שלושה מסכים"}],[{id:"s0",quote:"נבדקו ארבעה מסכים"}],[{id:"s0",quote:"נבדקו שלושה מסכים"},{id:"s0",quote:"נבדקו שלושה מסכים"}]]) assert.equal(validateArticleOutput({...output,sections:[{...output.sections[0],evidence:e}]},body.items),false);
});
test("reject empty, oversized or structurally invalid draft",()=>{
 for(const o of [{...output,sections:[]},{...output,sections:Array(7).fill(output.sections[0])},{...output,sections:[{...output.sections[0],paragraph:"x".repeat(1201)}]},{...output,extra:"x"}])assert.equal(validateArticleOutput(o,body.items),false);
});
