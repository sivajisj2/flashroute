#!/usr/bin/env python3
"""End-to-end checks against running services. Executes demo funds on chain 31337 only."""
import concurrent.futures,json,os,time,urllib.request,urllib.error
base=os.environ.get('BASE_URL','http://localhost:3000').rstrip('/')+'/api/v1'
token=os.environ['OPERATOR_API_KEY']
def request(path,body=None,extra=None,auth=True):
    headers={'Content-Type':'application/json'}
    if auth: headers['Authorization']='Bearer '+token
    if extra: headers.update(extra)
    req=urllib.request.Request(base+path,data=None if body is None else json.dumps(body).encode(),headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=30) as r:return r.status,json.load(r)
    except urllib.error.HTTPError as e:return e.code,json.loads(e.read())
assert request('/health',auth=False)[0]==401,'authentication boundary'
code,health=request('/health');assert code==200 and health['chain_id']==31337,'local chain only'
assert request('/opportunities?amount=0')[0]==422,'amount validation'
code,scan=request('/opportunities');assert code==200,scan
winning=next(r for r in scan['items'] if r['profitable'])
losing=next(r for r in scan['items'] if not r['profitable'])
assert request('/simulations',{'route':losing['route'],'amount':losing['amount'],'slippage_bps':10,'min_profit':5_000_000})[0]==422,'loss rejected'
assert request('/simulations',{'route':'a-b','amount':winning['amount'],'slippage_bps':500,'min_profit':1})[0]==422,'slippage validation'
code,sim=request('/simulations',{'route':winning['route'],'amount':winning['amount'],'slippage_bps':10,'min_profit':5_000_000})
assert code==200,sim
assert sim['gas']>0 and sim['status']=='ready'
path='/simulations/'+sim['id']+'/execute'
assert request(path,{}, {'Idempotency-Key':'wrong'})[0]==422
headers={'Idempotency-Key':sim['id']}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    responses=list(pool.map(lambda _:request(path,{},headers),range(2)))
assert all(code==200 for code,_ in responses),responses
assert sum(not data.get('replayed',False) for _,data in responses)==1,'one atomic submission'
for _ in range(20):
    code,history=request('/executions')
    item=next(h for h in history['items'] if h['id']==sim['id'])
    if item['status']=='confirmed':break
    time.sleep(.5)
assert item['status']=='confirmed',item
_,replay=request(path,{},headers)
assert replay['replayed'] and replay['tx_hash']==item['tx_hash'],'idempotent retry'
print(json.dumps({'result':'PASS','chain_id':health['chain_id'],'simulation':sim['id'],'tx_hash':item['tx_hash'],'status':item['status'],'gas_estimate':sim['gas'],'checks':['auth','input bounds','losing route rejection','simulation','atomic concurrent claim','receipt confirmation','idempotent replay']},indent=2))
