// Explicit same-provider task routing. No network, no automatic retry,
// no user-supplied model selection and no implicit provider change.
const operations=["/analyze","/article","/answer"];
const defaults={openai:"OPENAI_MODEL",gemini:"GEMINI_MODEL",bedrock:"BEDROCK_MODEL_ID"};
function validModel(provider,model){
  if(typeof model!=="string"||model.length>160)return false;
  if(provider==="openai")return /^[A-Za-z0-9][A-Za-z0-9._:-]*$/.test(model);
  if(provider==="gemini")return /^gemini-[a-z0-9][a-z0-9.-]{0,100}$/.test(model);
  if(provider==="bedrock")return /^(anthropic|amazon|cohere|meta|mistral|openai|qwen)\.[a-zA-Z0-9_.:-]+$/.test(model);
  return false;
}
export function taskPolicy(env=process.env){
  const provider=env.SCREENMIND_PROVIDER||"disabled";
  const raw=env.SCREENMIND_ROUTE_MODELS;
  if(provider==="disabled"){
    if(raw!==undefined)throw Error("routing_requires_enabled_provider");
    return Object.freeze({provider,models:Object.freeze([]),modelFor(){throw Error("provider_disabled");}});
  }
  if(!Object.hasOwn(defaults,provider))throw Error("invalid_provider");
  const base=env[defaults[provider]]??(provider==="openai"?"gpt-4o-mini":undefined);
  if(!validModel(provider,base))throw Error("invalid_default_model");
  let overrides={};
  if(raw!==undefined){
    if(env.SCREENMIND_ROUTE_MODELS_REVIEWED!=="yes"||typeof raw!=="string"||raw.length>2048)throw Error("routing_review_required");
    try{overrides=JSON.parse(raw);}catch{throw Error("invalid_route_models");}
    if(!overrides||typeof overrides!=="object"||Array.isArray(overrides)||Object.keys(overrides).length===0||
      !Object.entries(overrides).every(([op,m])=>operations.includes(op)&&validModel(provider,m)))throw Error("invalid_route_models");
  }
  const routes=new Map(operations.map(op=>[op,Object.hasOwn(overrides,op)?overrides[op]:base]));
  return Object.freeze({provider,models:Object.freeze([...new Set(routes.values())]),
    modelFor(op){if(!routes.has(op))throw Error("unknown_operation");return routes.get(op);}
  });
}
export async function createTaskRouter(policy,factory){
  const transports=new Map();
  for(const model of policy.models){
    const transport=await factory(model);
    if(typeof transport!=="function")throw Error("invalid_transport");
    transports.set(model,transport);
  }
  return Object.freeze({
    modelFor(op){return policy.modelFor(op);},
    async dispatch(op,payload){
      const transport=transports.get(policy.modelFor(op));
      if(!transport)throw Error("unavailable_transport");
      return await transport(payload);
    }
  });
}
