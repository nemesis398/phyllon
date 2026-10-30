//! The PostgreSQL connection pool and the readiness check.

use std::time::Duration;

use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use sqlx::{Connection, PgPool};
use tokio::time::timeout;
use tracing::warn;

use crate::config::{DatabaseConfig, Secret};

/// How long a request may wait for a connection from the pool.
const ACQUIRE_TIMEOUT: Duration = Duration::from_secs(2);

/// How long the whole readiness check, connecting and pinging, may take.
const READY_TIMEOUT: Duration = Duration::from_secs(2);

/// Builds a pool for the configured database without connecting to it.
///
/// The first connection opens when the pool is first used, so a database that
/// is down at start-up does not stop the server from starting, and `/readyz`
/// reports it instead. A request that waits more than two seconds for a
/// connection gets an error, so a hung database cannot pile up requests.
///
/// The password reaches sqlx only through the connect options, which are not
/// logged.
///
/// Call it from inside a Tokio runtime: the pool starts its upkeep task on
/// the current runtime.
#[must_use]
pub fn pool(cfg: &DatabaseConfig, password: &Secret) -> PgPool {
    let options = PgConnectOptions::new()
        .host(&cfg.host)
        .port(cfg.port)
        .database(&cfg.name)
        .username(&cfg.user)
        .password(password.expose());
    PgPoolOptions::new()
        .acquire_timeout(ACQUIRE_TIMEOUT)
        .connect_lazy_with(options)
}

/// Tells whether the database answers, within two seconds in total.
///
/// Takes a connection from the pool and pings it. Any error, and a database
/// that accepts the connection but never answers, gives `false`; the check
/// never waits longer than the budget.
pub async fn ready(pool: &PgPool) -> bool {
    let check = async {
        let mut connection = pool.acquire().await?;
        connection.ping().await
    };
    match timeout(READY_TIMEOUT, check).await {
        Ok(Ok(())) => true,
        Ok(Err(error)) => {
            warn!(%error, "the database is not ready");
            false
        }
        Err(_elapsed) => {
            warn!("the database did not answer within {READY_TIMEOUT:?}");
            false
        }
    }
}
