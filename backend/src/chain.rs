use alloy_primitives::{Address, U256};
use alloy_sol_types::{sol, SolCall};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::Duration;

sol! {
    struct Plan {
        address asset; address intermediate; address buyRouter; address sellRouter;
        uint256 amount; uint256 minIntermediate; uint256 minReturn; uint256 minProfit; uint256 deadline;
    }
    function execute(Plan p);
    function getAmountsOut(uint256 amount, address[] path) external view returns (uint256[] amounts);
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}
#[derive(Clone, Deserialize, Serialize)]
pub struct Deployment {
    pub asset: Address,
    pub intermediate: Address,
    pub pool: Address,
    pub executor: Address,
    pub buy_router: Address,
    pub sell_router: Address,
    pub operator: Address,
}
#[derive(Clone)]
pub struct Chain {
    pub url: String,
    pub http: reqwest::Client,
    pub deployment: Deployment,
}
impl Chain {
    pub fn new(url: String, deployment: Deployment) -> Result<Self, String> {
        Ok(Self {
            url,
            deployment,
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .build()
                .map_err(|e| e.to_string())?,
        })
    }
    pub async fn rpc(&self, method: &str, params: Value) -> Result<Value, String> {
        let value: Value = self
            .http
            .post(&self.url)
            .json(&json!({"jsonrpc":"2.0","id":1,"method":method,"params":params}))
            .send()
            .await
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?
            .json()
            .await
            .map_err(|e| e.to_string())?;
        if let Some(err) = value.get("error") {
            return Err(err.to_string());
        }
        value
            .get("result")
            .cloned()
            .ok_or_else(|| "missing RPC result".into())
    }
    pub async fn chain_id(&self) -> Result<u64, String> {
        hex_u64(&self.rpc("eth_chainId", json!([])).await?)
    }
    pub async fn block(&self) -> Result<u64, String> {
        hex_u64(&self.rpc("eth_blockNumber", json!([])).await?)
    }
    pub async fn quote(
        &self,
        router: Address,
        amount: u64,
        a: Address,
        b: Address,
        block: u64,
    ) -> Result<u64, String> {
        let call = getAmountsOutCall {
            amount: U256::from(amount),
            path: vec![a, b],
        };
        let result=self.rpc("eth_call",json!([{"to":router,"data":format!("0x{}",alloy_primitives::hex::encode(call.abi_encode()))},format!("0x{block:x}")])).await?;
        let bytes = alloy_primitives::hex::decode(result.as_str().ok_or("invalid RPC bytes")?)
            .map_err(|e| e.to_string())?;
        let decoded = getAmountsOutCall::abi_decode_returns(&bytes).map_err(|e| e.to_string())?;
        decoded
            .last()
            .ok_or("empty quote")?
            .try_into()
            .map_err(|_| "quote overflow".into())
    }
    pub async fn premium_bps(&self, block: u64) -> Result<u64, String> {
        let data = FLASHLOAN_PREMIUM_TOTALCall {}.abi_encode();
        let result=self.rpc("eth_call",json!([{"to":self.deployment.pool,"data":format!("0x{}",alloy_primitives::hex::encode(data))},format!("0x{block:x}")])).await?;
        let bytes = alloy_primitives::hex::decode(result.as_str().ok_or("invalid premium")?)
            .map_err(|e| e.to_string())?;
        let n =
            FLASHLOAN_PREMIUM_TOTALCall::abi_decode_returns(&bytes).map_err(|e| e.to_string())?;
        u64::try_from(n).map_err(|_| "premium overflow".into())
    }
    pub fn transaction(
        &self,
        route: &str,
        amount: u64,
        first: u64,
        last: u64,
        profit: u64,
        deadline: u64,
    ) -> Value {
        let d = &self.deployment;
        let (buy, sell) = if route == "a-b" {
            (d.buy_router, d.sell_router)
        } else {
            (d.sell_router, d.buy_router)
        };
        let call = executeCall {
            p: Plan {
                asset: d.asset,
                intermediate: d.intermediate,
                buyRouter: buy,
                sellRouter: sell,
                amount: U256::from(amount),
                minIntermediate: U256::from(first),
                minReturn: U256::from(last),
                minProfit: U256::from(profit),
                deadline: U256::from(deadline),
            },
        };
        json!({"from":d.operator,"to":d.executor,"data":format!("0x{}",alloy_primitives::hex::encode(call.abi_encode()))})
    }
}
pub fn hex_u64(value: &Value) -> Result<u64, String> {
    u64::from_str_radix(
        value
            .as_str()
            .ok_or("invalid hex")?
            .trim_start_matches("0x"),
        16,
    )
    .map_err(|e| e.to_string())
}
