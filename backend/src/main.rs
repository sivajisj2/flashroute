mod chain;
use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use chain::{hex_u64, Chain};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{postgres::PgPoolOptions, PgPool, Row};
use std::{
    env,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Duration,
};
use subtle::ConstantTimeEq;
use tokio::sync::Mutex;
use tower_http::{limit::RequestBodyLimitLayer, trace::TraceLayer};
use uuid::Uuid;

type ApiResult<T> = Result<Json<T>, ApiError>;
#[derive(Clone)]
struct App {
    db: PgPool,
    chain: Chain,
    api_key: Arc<String>,
    local_execution: bool,
    requests: Arc<AtomicU64>,
    scans: Arc<AtomicU64>,
    scan_lock: Arc<Mutex<()>>,
}
#[derive(Debug)]
struct ApiError(StatusCode, String);
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({"error":self.1}))).into_response()
    }
}
fn internal(e: impl std::fmt::Display) -> ApiError {
    tracing::error!(error=%e,"request failed");
    ApiError(
        StatusCode::BAD_GATEWAY,
        "Upstream operation failed. Check service logs.".into(),
    )
}
fn bad(e: impl Into<String>) -> ApiError {
    ApiError(StatusCode::UNPROCESSABLE_ENTITY, e.into())
}
#[derive(Deserialize)]
struct ScanParams {
    amount: Option<u64>,
}
#[derive(Clone, Serialize, Deserialize)]
struct Opportunity {
    id: String,
    route: String,
    buy: String,
    sell: String,
    amount: u64,
    intermediate: u64,
    returned: u64,
    premium: u64,
    gas_reserve: u64,
    net: i64,
    block: u64,
    profitable: bool,
}
#[derive(Deserialize)]
struct SimulateRequest {
    route: String,
    amount: u64,
    slippage_bps: u64,
    min_profit: u64,
}
#[derive(Serialize)]
struct Simulation {
    id: Uuid,
    status: String,
    gas: u64,
    expires_at: i64,
    opportunity: Opportunity,
    transaction: Value,
}

async fn auth(State(app): State<App>, request: axum::extract::Request, next: Next) -> Response {
    app.requests.fetch_add(1, Ordering::Relaxed);
    let provided = request
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    let expected = format!("Bearer {}", app.api_key);
    if provided.len() != expected.len()
        || !bool::from(provided.as_bytes().ct_eq(expected.as_bytes()))
    {
        return ApiError(StatusCode::UNAUTHORIZED, "Operator token required".into())
            .into_response();
    }
    next.run(request).await
}
fn validate_amount(amount: u64) -> Result<(), ApiError> {
    if !(100_000_000..=100_000_000_000).contains(&amount) {
        return Err(bad(
            "Amount must be 100–100,000 demo USDC in 6-decimal base units",
        ));
    }
    Ok(())
}
fn economics(amount: u64, returned: u64, premium_bps: u64) -> Result<(u64, i64), ApiError> {
    let premium = amount
        .checked_mul(premium_bps)
        .and_then(|v| v.checked_add(5000))
        .ok_or_else(|| bad("premium overflow"))?
        / 10000;
    let net = i128::from(returned) - i128::from(amount) - i128::from(premium) - 20_000_000;
    Ok((
        premium,
        i64::try_from(net).map_err(|_| bad("net overflow"))?,
    ))
}
async fn quote(
    app: &App,
    route: &str,
    amount: u64,
    block: u64,
    bps: u64,
) -> Result<Opportunity, ApiError> {
    let d = &app.chain.deployment;
    let (buy, sell, buy_name, sell_name) = match route {
        "a-b" => (d.buy_router, d.sell_router, "DemoSwap A", "DemoSwap B"),
        "b-a" => (d.sell_router, d.buy_router, "DemoSwap B", "DemoSwap A"),
        _ => return Err(bad("Unknown route")),
    };
    let first = app
        .chain
        .quote(buy, amount, d.asset, d.intermediate, block)
        .await
        .map_err(internal)?;
    let returned = app
        .chain
        .quote(sell, first, d.intermediate, d.asset, block)
        .await
        .map_err(internal)?;
    let (premium, net) = economics(amount, returned, bps)?;
    Ok(Opportunity {
        id: route.into(),
        route: route.into(),
        buy: buy_name.into(),
        sell: sell_name.into(),
        amount,
        intermediate: first,
        returned,
        premium,
        gas_reserve: 20_000_000,
        net,
        block,
        profitable: net > 0,
    })
}
async fn opportunities(
    State(app): State<App>,
    Query(params): Query<ScanParams>,
) -> ApiResult<Value> {
    let _guard = app.scan_lock.try_lock().map_err(|_| {
        ApiError(
            StatusCode::TOO_MANY_REQUESTS,
            "Scan already in progress".into(),
        )
    })?;
    let amount = params.amount.unwrap_or(10_000_000_000);
    validate_amount(amount)?;
    let block = app.chain.block().await.map_err(internal)?;
    let bps = app.chain.premium_bps(block).await.map_err(internal)?;
    let (a, b) = tokio::try_join!(
        quote(&app, "a-b", amount, block, bps),
        quote(&app, "b-a", amount, block, bps)
    )?;
    app.scans.fetch_add(1, Ordering::Relaxed);
    Ok(Json(
        json!({"items":[a,b],"block":block,"mode":"local deterministic markets","gas_reserve_note":"20 demo USDC policy reserve; not a live ETH/USD gas conversion"}),
    ))
}
async fn simulate(
    State(app): State<App>,
    Json(req): Json<SimulateRequest>,
) -> ApiResult<Simulation> {
    validate_amount(req.amount)?;
    if req.slippage_bps > 100 || req.min_profit == 0 || req.min_profit > 1_000_000_000 {
        return Err(bad(
            "Slippage must be 0–100 bps; minimum profit must be 1–1,000,000,000 base units",
        ));
    }
    let block = app.chain.block().await.map_err(internal)?;
    let bps = app.chain.premium_bps(block).await.map_err(internal)?;
    let opportunity = quote(&app, &req.route, req.amount, block, bps).await?;
    if opportunity.net < i64::try_from(req.min_profit).map_err(|_| bad("profit overflow"))? {
        return Err(bad(
            "Route does not cover premium, gas reserve and minimum profit",
        ));
    }
    let expires = chrono::Utc::now().timestamp() + 90;
    let first = opportunity.intermediate * (10_000 - req.slippage_bps) / 10_000;
    let last = opportunity.returned * (10_000 - req.slippage_bps) / 10_000;
    // The contract profit floor includes the gas policy reserve so submitted routes must cover it.
    let tx = app.chain.transaction(
        &req.route,
        req.amount,
        first,
        last,
        req.min_profit + opportunity.gas_reserve,
        expires as u64,
    );
    app.chain
        .rpc("eth_call", json!([tx, "latest"]))
        .await
        .map_err(|e| bad(format!("Simulation reverted: {e}")))?;
    let gas = hex_u64(
        &app.chain
            .rpc("eth_estimateGas", json!([tx]))
            .await
            .map_err(internal)?,
    )
    .map_err(internal)?;
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO executions(id,status,transaction,opportunity,gas,expires_at) VALUES($1,'ready',$2,$3,$4,$5)")
        .bind(id).bind(&tx).bind(serde_json::to_value(&opportunity).map_err(internal)?).bind(gas as i64).bind(expires).execute(&app.db).await.map_err(internal)?;
    Ok(Json(Simulation {
        id,
        status: "ready".into(),
        gas,
        expires_at: expires,
        opportunity,
        transaction: tx,
    }))
}
async fn execute_simulation(
    State(app): State<App>,
    Path(id): Path<Uuid>,
    headers: HeaderMap,
) -> ApiResult<Value> {
    if !app.local_execution || app.chain.chain_id().await.map_err(internal)? != 31337 {
        return Err(ApiError(
            StatusCode::FORBIDDEN,
            "Server submission is enabled only for local chain 31337".into(),
        ));
    }
    let key = headers
        .get("idempotency-key")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| bad("Idempotency-Key must equal simulation id"))?;
    if key != id.to_string() {
        return Err(bad("Idempotency-Key must equal simulation id"));
    }
    // Atomic database claim prevents concurrent duplicate submissions across API replicas.
    let row=sqlx::query("UPDATE executions SET status='submitting',updated_at=now() WHERE id=$1 AND status='ready' AND expires_at>$2 RETURNING transaction")
        .bind(id).bind(chrono::Utc::now().timestamp()).fetch_optional(&app.db).await.map_err(internal)?;
    let Some(row) = row else {
        let existing = sqlx::query("SELECT status,tx_hash FROM executions WHERE id=$1")
            .bind(id)
            .fetch_optional(&app.db)
            .await
            .map_err(internal)?;
        return match existing {
            Some(r) => Ok(Json(
                json!({"id":id,"status":r.get::<String,_>("status"),"tx_hash":r.get::<Option<String>,_>("tx_hash"),"replayed":true}),
            )),
            None => Err(ApiError(
                StatusCode::NOT_FOUND,
                "Simulation not found".into(),
            )),
        };
    };
    let mut tx: Value = row.get("transaction");
    let estimate = app.chain.rpc("eth_estimateGas", json!([tx])).await;
    match estimate {
        Ok(gas) => {
            let g = hex_u64(&gas).map_err(internal)?;
            tx["gas"] = json!(format!("0x{:x}", g + g / 5));
        }
        Err(e) => {
            sqlx::query("UPDATE executions SET status='failed',error='Preflight reverted',updated_at=now() WHERE id=$1").bind(id).execute(&app.db).await.map_err(internal)?;
            return Err(bad(format!("Preflight reverted: {e}")));
        }
    }
    // No private keys: Anvil's unlocked local operator only. Never expose this RPC publicly.
    match app.chain.rpc("eth_sendTransaction", json!([tx])).await {
        Ok(hash) => {
            let hash = hash
                .as_str()
                .ok_or_else(|| internal("invalid transaction hash"))?;
            sqlx::query(
                "UPDATE executions SET status='submitted',tx_hash=$2,updated_at=now() WHERE id=$1",
            )
            .bind(id)
            .bind(hash)
            .execute(&app.db)
            .await
            .map_err(internal)?;
            Ok(Json(json!({"id":id,"status":"submitted","tx_hash":hash})))
        }
        Err(e) => {
            tracing::error!(%id,error=%e,"submission outcome unknown; do not retry");
            sqlx::query("UPDATE executions SET status='unknown',error='RPC submission outcome unknown; reconcile manually',updated_at=now() WHERE id=$1").bind(id).execute(&app.db).await.map_err(internal)?;
            Err(ApiError(
                StatusCode::BAD_GATEWAY,
                "Submission outcome unknown. Inspect chain before creating another execution."
                    .into(),
            ))
        }
    }
}
async fn history(State(app): State<App>) -> ApiResult<Value> {
    let rows=sqlx::query("SELECT id,status,tx_hash,opportunity,gas,expires_at,error,created_at FROM executions ORDER BY created_at DESC LIMIT 100").fetch_all(&app.db).await.map_err(internal)?;
    let items:Vec<Value>=rows.iter().map(|r|json!({"id":r.get::<Uuid,_>("id"),"status":r.get::<String,_>("status"),"tx_hash":r.get::<Option<String>,_>("tx_hash"),"opportunity":r.get::<Value,_>("opportunity"),"gas":r.get::<i64,_>("gas"),"expires_at":r.get::<i64,_>("expires_at"),"error":r.get::<Option<String>,_>("error"),"created_at":r.get::<chrono::DateTime<chrono::Utc>,_>("created_at")})).collect();
    Ok(Json(json!({"items":items})))
}
async fn health(State(app): State<App>) -> ApiResult<Value> {
    sqlx::query("SELECT 1")
        .execute(&app.db)
        .await
        .map_err(internal)?;
    let id = app.chain.chain_id().await.map_err(internal)?;
    Ok(Json(
        json!({"status":"ok","database":"connected","chain_id":id,"mode":"local","submission_enabled":app.local_execution,"deployment":app.chain.deployment}),
    ))
}
async fn metrics(State(app): State<App>) -> String {
    format!("# HELP flashroute_requests_total Authenticated API requests attempted\n# TYPE flashroute_requests_total counter\nflashroute_requests_total {}\n# HELP flashroute_scans_total Completed scans\n# TYPE flashroute_scans_total counter\nflashroute_scans_total {}\n",app.requests.load(Ordering::Relaxed),app.scans.load(Ordering::Relaxed))
}
async fn reconcile(app: App) {
    let mut interval = tokio::time::interval(Duration::from_secs(2));
    loop {
        interval.tick().await;
        let rows = match sqlx::query(
            "SELECT id,tx_hash FROM executions WHERE status='submitted' LIMIT 100",
        )
        .fetch_all(&app.db)
        .await
        {
            Ok(r) => r,
            Err(e) => {
                tracing::error!(%e,"receipt query failed");
                continue;
            }
        };
        for row in rows {
            let id: Uuid = row.get("id");
            let hash: Option<String> = row.get("tx_hash");
            if let Some(hash) = hash {
                match app
                    .chain
                    .rpc("eth_getTransactionReceipt", json!([hash]))
                    .await
                {
                    Ok(v) if !v.is_null() => {
                        let status = if v["status"] == "0x1" {
                            "confirmed"
                        } else {
                            "reverted"
                        };
                        if let Err(e)=sqlx::query("UPDATE executions SET status=$2,receipt=$3,updated_at=now() WHERE id=$1 AND status='submitted'").bind(id).bind(status).bind(v).execute(&app.db).await{tracing::error!(%e,"receipt persistence failed");}
                    }
                    Err(e) => tracing::warn!(%e,"receipt unavailable"),
                    _ => {}
                }
            }
        }
        // Submitting at crash time is ambiguous. Never automatically resend.
        if let Err(e)=sqlx::query("UPDATE executions SET status='unknown',error='Submission interrupted; reconcile manually',updated_at=now() WHERE status='submitting' AND updated_at<now()-interval '2 minutes'").execute(&app.db).await{tracing::warn!(%e,"stale submission cleanup failed");}
        if let Err(e)=sqlx::query("UPDATE executions SET status='expired',updated_at=now() WHERE status='ready' AND expires_at<$1").bind(chrono::Utc::now().timestamp()).execute(&app.db).await{tracing::warn!(%e,"expiry cleanup failed");}
    }
}
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tower_http=info".into()),
        )
        .init();
    let key = env::var("OPERATOR_API_KEY")?;
    if key.len() < 24 {
        return Err("OPERATOR_API_KEY must contain at least 24 characters".into());
    }
    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&env::var("DATABASE_URL")?)
        .await?;
    sqlx::raw_sql(include_str!("../schema.sql"))
        .execute(&db)
        .await?;
    let deployment = serde_json::from_str(&std::fs::read_to_string(
        env::var("DEPLOYMENT_FILE").unwrap_or_else(|_| "contracts/deployments/local.json".into()),
    )?)?;
    let chain = Chain::new(
        env::var("RPC_URL").unwrap_or_else(|_| "http://127.0.0.1:8545".into()),
        deployment,
    )?;
    if chain.chain_id().await? != 31337 {
        return Err("This release supports backend operation only on chain 31337; production signer is intentionally absent".into());
    }
    let app = App {
        db,
        chain,
        api_key: Arc::new(key),
        local_execution: env::var("ALLOW_LOCAL_EXECUTION").as_deref() == Ok("true"),
        requests: Arc::new(AtomicU64::new(0)),
        scans: Arc::new(AtomicU64::new(0)),
        scan_lock: Arc::new(Mutex::new(())),
    };
    tokio::spawn(reconcile(app.clone()));
    let api = Router::new()
        .route("/health", get(health))
        .route("/opportunities", get(opportunities))
        .route("/simulations", post(simulate))
        .route("/simulations/{id}/execute", post(execute_simulation))
        .route("/executions", get(history))
        .route_layer(middleware::from_fn_with_state(app.clone(), auth));
    let router = Router::new()
        .nest("/api/v1", api)
        .route("/livez", get(|| async { "ok" }))
        .route("/metrics", get(metrics))
        .layer(RequestBodyLimitLayer::new(8192))
        .layer(TraceLayer::new_for_http())
        .with_state(app);
    let listener = tokio::net::TcpListener::bind(
        env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into()),
    )
    .await?;
    tracing::info!(address=%listener.local_addr()?,"FlashRoute API listening");
    axum::serve(listener, router)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn premium_and_net_include_costs() {
        assert_eq!(
            economics(10_000_000_000, 10_250_000_000, 5).unwrap(),
            (5_000_000, 225_000_000)
        );
    }
    #[test]
    fn losing_route_stays_negative() {
        assert!(economics(10_000_000_000, 9_900_000_000, 5).unwrap().1 < 0);
    }
    #[test]
    fn rejects_out_of_range_amounts() {
        assert!(validate_amount(0).is_err());
        assert!(validate_amount(u64::MAX).is_err());
        assert!(validate_amount(10_000_000_000).is_ok());
    }
    #[test]
    fn premium_rounds_half_up() {
        assert_eq!(economics(1000, 1000, 5).unwrap().0, 1);
    }
}
