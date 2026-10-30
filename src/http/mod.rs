//! The HTTP layer: routes, the security headers and panic catching.

pub mod headers;

use axum::Router;
use axum::extract::State;
use axum::http::{HeaderName, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use sqlx::PgPool;
use tower_http::catch_panic::CatchPanicLayer;
use tower_http::set_header::SetResponseHeaderLayer;
use tracing::error;

use crate::db;
use crate::web;
use headers::SECURITY_HEADERS;

/// The repository, where the source of a build without a commit is offered.
const REPOSITORY_URL: &str = "https://github.com/nemesis398/phyllon";

/// What every handler can reach.
#[derive(Clone)]
pub struct AppState {
    /// The database pool, which connects on first use.
    pub pool: PgPool,
    /// Which build is running.
    pub build: BuildInfo,
    /// Where the running version's source code is offered. Computed once by
    /// [`source_url`].
    pub source_url: String,
}

/// Which build is running.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BuildInfo {
    /// The crate version.
    pub version: &'static str,
    /// The git commit the build was made from, when the build environment set
    /// `PHYLLON_GIT_COMMIT`.
    pub commit: Option<&'static str>,
}

impl BuildInfo {
    /// The build this binary came from, read at compile time.
    #[must_use]
    pub fn current() -> BuildInfo {
        BuildInfo {
            version: env!("CARGO_PKG_VERSION"),
            commit: option_env!("PHYLLON_GIT_COMMIT"),
        }
    }
}

/// The one error type of the HTTP layer.
///
/// It turns into a response that says nothing about the cause, so no internal
/// detail reaches a client.
#[derive(Debug, thiserror::Error)]
pub enum AppError {
    /// Something failed on the server. The response is a generic 500.
    #[error("internal server error")]
    Internal,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        match self {
            AppError::Internal => web::error_page(),
        }
    }
}

/// Where the running version's source code is offered.
///
/// This is the configured URL when there is one. Otherwise it is the
/// repository's tree at the build's commit, or the repository itself when the
/// build has no commit.
#[must_use]
pub fn source_url(configured: Option<&str>, build: &BuildInfo) -> String {
    match (configured, build.commit) {
        (Some(url), _) => url.to_owned(),
        (None, Some(commit)) => format!("{REPOSITORY_URL}/tree/{commit}"),
        (None, None) => REPOSITORY_URL.to_owned(),
    }
}

/// All routes, a 404 fallback, and the security layers around them.
///
/// `/healthz` answers 200 without touching the database. `/readyz` answers 200
/// or 503 depending on [`db::ready`]. Both answer HEAD too.
pub fn router(state: AppState) -> Router {
    let routes = Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .merge(web::routes())
        .fallback(web::not_found)
        .with_state(state);
    with_security_layers(routes)
}

/// Wraps `router` so that every response carries [`SECURITY_HEADERS`] and a
/// panicking handler becomes a generic 500 instead of a dropped connection.
///
/// The panic layer sits inside the header layers, so the 500 it produces gets
/// the headers too. The panic message never reaches the client; it stays in
/// the panic hook's output.
pub fn with_security_layers(router: Router) -> Router {
    let router = router.layer(CatchPanicLayer::custom(|_panic| {
        error!("a handler panicked; answering 500");
        AppError::Internal.into_response()
    }));
    SECURITY_HEADERS
        .into_iter()
        .filter_map(|(name, value)| {
            Some(SetResponseHeaderLayer::overriding(
                HeaderName::from_bytes(name.as_bytes()).ok()?,
                HeaderValue::from_str(value).ok()?,
            ))
        })
        .fold(router, Router::layer)
}

async fn healthz() -> &'static str {
    "ok\n"
}

async fn readyz(State(state): State<AppState>) -> Response {
    if db::ready(&state.pool).await {
        (StatusCode::OK, "ok\n").into_response()
    } else {
        (StatusCode::SERVICE_UNAVAILABLE, "database unavailable\n").into_response()
    }
}
