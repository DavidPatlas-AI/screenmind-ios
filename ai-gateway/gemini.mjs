// Optional Gemini REST adapter. Disabled unless operator confirms live opt-in
// and reviews paid-service data terms. No API key is exposed to iOS.
export function buildGeminiRequest({body,schema,instructions}) {
  return {
    systemInstruction:{parts:[{text:instructions}]},
    contents:[{role:"user",parts:[{text:JSON.stringify(body)}]}],
    generationConfig:{
      candidateCount:1,maxOutputTokens:4000,
      responseMimeType:"application/json",responseJsonSchema:schema
    }
  };
}
export function parseGeminiResponse(data) {
  if(data?.promptFeedback?.blockReason &&
     data.promptFeedback.blockReason!=="BLOCK_REASON_UNSPECIFIED") throw Error("blocked");
  if(!Array.isArray(data?.candidates)||data.candidates.length!==1) throw Error("invalid_candidate");
  const candidate=data.candidates[0];
  if(candidate.finishReason!=="STOP") throw Error("incomplete");
  const parts=candidate.content?.parts;
  if(!Array.isArray(parts)||parts.some(p=>p.functionCall||p.functionResponse||p.executableCode||p.codeExecutionResult)) throw Error("unexpected_content");
  const raw=parts.filter(p=>p.thought!==true&&typeof p.text==="string").map(p=>p.text).join("");
  if(!raw||raw.length>100000) throw Error("invalid_result");
  return JSON.parse(raw);
}
export function createGeminiProvider(env=process.env, transport=globalThis.fetch) {
  if(env.SCREENMIND_ALLOW_LIVE_AI!=="yes" ||
     env.SCREENMIND_GEMINI_PAID_TERMS_REVIEWED!=="yes") {
    throw Error("Gemini requires explicit live opt-in and paid-service privacy review.");
  }
  const key=env.GEMINI_API_KEY, model=env.GEMINI_MODEL;
  if(typeof key!=="string"||!key.trim()||key.length>500||
      typeof model!=="string"||!/^gemini-[a-z0-9][a-z0-9.-]{0,100}$/.test(model)) {
    throw Error("Set server-only GEMINI_API_KEY and GEMINI_MODEL.");
  }
  const url="https://generativelanguage.googleapis.com/v1beta/models/"+encodeURIComponent(model)+":generateContent";
  return async ({body,schema,instructions,signal})=>{
    const response=await transport(url,{
      method:"POST",redirect:"error",
      headers:{"x-goog-api-key":key,"content-type":"application/json"},
      signal,body:JSON.stringify(buildGeminiRequest({body,schema,instructions}))
    });
    if(!response.ok) throw Error("provider_unavailable");
    return parseGeminiResponse(await response.json());
  };
}
