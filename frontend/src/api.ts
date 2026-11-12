export type Opportunity={id:string;route:string;buy:string;sell:string;amount:number;intermediate:number;returned:number;premium:number;gas_reserve:number;net:number;block:number;profitable:boolean};
export type Simulation={id:string;status:string;gas:number;expires_at:number;opportunity:Opportunity;transaction:Record<string,string>};
export type Execution={id:string;status:string;tx_hash:string|null;opportunity:Opportunity;created_at:string;error:string|null};
export type Health={status:string;chain_id:number;submission_enabled:boolean;database:string;deployment:Record<string,string>};
export const units=(value:string):number=>{
 if(!/^\d+(\.\d{1,6})?$/.test(value))throw Error('Use up to 6 decimal places');
 const [whole,fraction='']=value.split('.');const n=Number(whole)*1e6+Number(fraction.padEnd(6,'0'));
 if(!Number.isSafeInteger(n)||n<100e6||n>100000e6)throw Error('Amount must be 100–100,000 dUSDC');return n;
};
export const usd=(n:number)=>new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:2}).format(n/1e6);
export async function api<T>(path:string,token:string,body?:unknown,headers:Record<string,string>={}):Promise<T>{
 const res=await fetch('/api/v1'+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+token,...(body===undefined?{}:{'Content-Type':'application/json'}),...headers},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const text=await res.text();let value;try{value=JSON.parse(text)}catch{throw Error(res.status===429?'Too many requests. Wait a moment and retry.':'Service returned an unexpected response ('+res.status+')');}if(!res.ok)throw Error(value.error||'Request failed');return value;
}
