//! The PostgreSQL connection pool and the readiness check.

use std::time::Duration;

use sqlx::postgres::{PgConnectOptions, PgPoolOptions, PgSslMode};
use sqlx::{Connection, PgPool};
use tokio::time::timeout;
use tracing::warn;

use crate::config::{DatabaseConfig, Secret};

/// The application name the server shows for our connections.
const APPLICATION_NAME: &str = "phyllon";

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
/// The config is the only source of the connection settings. The options start
/// from [`PgConnectOptions::new_without_pgpass`], which skips `~/.pgpass`, and
/// every setting that sqlx would otherwise read from a `PG*` environment
/// variable is set here: host, port, user, database, password, TLS mode and
/// application name. The exceptions are `PGOPTIONS` and the TLS certificate
/// paths, which sqlx 0.9.0 offers no way to clear. The certificate paths do
/// nothing with TLS off. `PGOPTIONS` reaches the server in the startup packet
/// and can change any session setting, such as `search_path` or
/// `default_transaction_read_only`, so `serve` refuses to start while it is
/// set.
///
/// The password reaches sqlx only through the connect options, which are not
/// logged.
///
/// # Panics
///
/// Panics when called outside a Tokio runtime, because the pool starts its
/// upkeep task on the current runtime.
#[must_use]
pub fn pool(cfg: &DatabaseConfig, password: &Secret) -> PgPool {
    // TLS is not compiled in (sqlx has no TLS feature), so the mode is
    // Disable. The default, Prefer, would also work, but a stray PGSSLMODE
    // of require or verify-full would make every connection fail.
    let options = PgConnectOptions::new_without_pgpass()
        .host(&cfg.host)
        .port(cfg.port)
        .database(&cfg.name)
        .username(&cfg.user)
        .password(password.expose())
        .ssl_mode(PgSslMode::Disable)
        .application_name(APPLICATION_NAME);
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
