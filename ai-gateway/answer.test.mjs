import test from "node:test";
import assert from "node:assert/strict";
import {validateAnswerInput,validateAnswerOutput} from "./answer.mjs";
const items=[{id:"s0",title:"מקור א",text:"נבדקו שלושה מסכים ונמצאה תקלה אחת."},{id:"s1",title:"מקור ב",text:"נבדקו ארבעה מסכים ונמצאו שתי תקלות."}];
const body={language:"he",question:"כמה מסכים נבדקו?",items};
const evidence=[{id:"s0",quote:"נבדקו שלושה מסכים"},{id:"s1",quote:"נבדקו ארבעה מסכים"}];
test("bounded input and temporary identifiers only",()=>{
 assert.equal(validateAnswerInput(body,["he"]),true);
 for(const b of [{...body,question:" "},{...body,question:"x".repeat(501)},{...body,history:[]},{...body,items:[items[0],items[0]]},{...body,items:[]}])assert.equal(validateAnswerInput(b,["he"]),false);
});
test("answer requires exact source evidence",()=>{
 const out={status:"answered",answer:"במקור א תועדו שלושה מסכים.",evidence:[evidence[0]]};
 assert.equal(validateAnswerOutput(out,items),true);
 for(const ev of [[],[{id:"s0",quote:"נבדקו ארבעה מסכים"}],[{id:"s9",quote:evidence[0].quote}],[evidence[0],evidence[0]]])assert.equal(validateAnswerOutput({...out,evidence:ev},items),false);
});
test("insufficient has no invented answer",()=>{
 const out={status:"insufficient",answer:"",evidence:[]};
 assert.equal(validateAnswerOutput(out,items),true);
 assert.equal(validateAnswerOutput({...out,answer:"probably three"},items),false);
 assert.equal(validateAnswerOutput({...out,evidence:[evidence[0]]},items),false);
});
test("conflicting requires multiple distinct sources",()=>{
 const out={status:"conflicting",answer:"המקורות מתארים כמויות שונות.",evidence};
 assert.equal(validateAnswerOutput(out,items),true);
 assert.equal(validateAnswerOutput({...out,evidence:[evidence[0]]},items),false);
 assert.equal(validateAnswerOutput({...out,status:"unknown"},items),false);
});
