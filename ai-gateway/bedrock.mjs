// Bedrock transport: explicit operator opt-in; never forwards to another provider.
// No AWS dependencies are loaded during mocked tests.
export function buildConverseRequest({modelId,body,schema,instructions}) {
  if (!modelId || typeof modelId !== "string") throw new Error("missing_model");
  return {
    modelId,
    system:[{text:instructions}],
    messages:[{role:"user",content:[{text:JSON.stringify(body)}]}],
    inferenceConfig:{maxTokens:4000,temperature:0},
    outputConfig:{textFormat:{type:"json_schema",structure:{jsonSchema:{
      name:"screenmind_analysis",schema:JSON.stringify(schema),
      description:"Grounded screenshot analysis"
    }}}}
  };
}
export function parseConverseResponse(response) {
  if (response?.stopReason !== "end_turn") throw new Error("incomplete");
  const blocks=response?.output?.message?.content;
  if (!Array.isArray(blocks) || blocks.some(x=>x.toolUse || x.toolResult)) throw new Error("invalid_result");
  const raw=blocks.filter(x=>typeof x.text==="string").map(x=>x.text).join("");
  if (!raw || raw.length>100000) throw new Error("invalid_result");
  return JSON.parse(raw);
}
export async function createBedrockProvider(env=process.env, load=()=>import("@aws-sdk/client-bedrock-runtime")) {
  if (env.SCREENMIND_ALLOW_LIVE_AI!=="yes") throw new Error("Live AI must be explicitly enabled.");
  const region=env.AWS_REGION,modelId=env.BEDROCK_MODEL_ID;
  // Direct model identifier only; no cross-region profiles, endpoints or ARNs in this prototype.
  if (!region || !/^[a-z]{2}(?:-[a-z]+)+-\d+$/.test(region) ||
      !modelId || !/^(anthropic|amazon|cohere|meta|mistral|openai|qwen)\.[a-zA-Z0-9_.:-]+$/.test(modelId)) {
    throw new Error("Set AWS_REGION and a supported direct BEDROCK_MODEL_ID.");
  }
  const {BedrockRuntimeClient,ConverseCommand}=await load();
  const client=new BedrockRuntimeClient({region,maxAttempts:1});
  return async ({body,schema,instructions,signal})=>{
    const request=buildConverseRequest({modelId,body,schema,instructions});
    const response=await client.send(new ConverseCommand(request),{abortSignal:signal});
    return parseConverseResponse(response);
  };
}
