//! Tests for the HTTP layer: health and readiness, the security headers and
//! panic catching. They drive the router in process and touch no network
//! beyond 127.0.0.1.

use std::fs;
use std::net::TcpListener;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use axum::Router;
use axum::body::Body;
use axum::http::{Method, Request, Response, StatusCode};
use axum::routing::get;
use http_body_util::BodyExt;
use phyllon::config::DatabaseConfig;
use phyllon::db;
use phyllon::http::headers::SECURITY_HEADERS;
use phyllon::http::{AppState, BuildInfo, router, source_url, with_security_layers};
use sqlx::postgres::PgSslMode;
use tower::ServiceExt;

/// The helpers sit in a `cfg(test)` module so that Clippy's
/// `allow-unwrap-in-tests` covers them, the way it covers `#[test]` functions.
#[cfg(test)]
mod support {
    use super::*;

    /// A build as `cargo build` makes it when no commit is known.
    pub const BUILD: BuildInfo = BuildInfo {
        version: "0.0.0",
        commit: None,
    };

    /// Makes an empty directory for one test under the target directory, so tests
    /// that run in parallel never share a file.
    pub fn test_dir(name: &str) -> PathBuf {
        let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR"))
            .join("http")
            .join(name);
        if dir.exists() {
            fs::remove_dir_all(&dir).unwrap();
        }
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// Builds the application state for a database at `host:port`, with the
    /// password file in the test's own directory.
    pub fn state_for(name: &str, host: &str, port: u16, password: &str) -> AppState {
        let password_file = test_dir(name).join("password");
        fs::write(&password_file, password).unwrap();
        let cfg = DatabaseConfig {
            host: host.to_owned(),
            port,
            name: "phyllon".to_owned(),
            user: "postgres".to_owned(),
            password_file,
        };
        let secret = cfg.password().unwrap();
        AppState {
            pool: db::pool(&cfg, &secret),
            build: BUILD,
            source_url: source_url(None, &BUILD),
        }
    }

    /// State whose database is not there: nothing listens on port 1.
    pub fn unreachable_state(name: &str) -> AppState {
        state_for(name, "127.0.0.1", 1, "unused")
    }

    /// Sends one request with the given method to `path` and returns the answer.
    pub async fn send(app: &Router, method: Method, path: &str) -> Response<Body> {
        let request = Request::builder()
            .method(method)
            .uri(path)
            .body(Body::empty())
            .unwrap();
        app.clone().oneshot(request).await.unwrap()
    }

    /// Reads a whole response body as text.
    pub async fn text(response: Response<Body>) -> String {
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        String::from_utf8(bytes.to_vec()).unwrap()
    }

    /// Asserts that `response` carries all five security headers, exactly.
    pub fn assert_security_headers(response: &Response<Body>, context: &str) {
        for (name, value) in SECURITY_HEADERS {
            let values: Vec<_> = response.headers().get_all(name).iter().collect();
            assert_eq!(values, [value], "{name} on {context}");
        }
    }
}
use support::*;

#[tokio::test]
async fn healthz_answers_200() {
    let app = router(unreachable_state("healthz"));

    let response = send(&app, Method::GET, "/healthz").await;

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(text(response).await, "ok\n");
}

#[tokio::test]
async fn head_healthz_answers_200() {
    let app = router(unreachable_state("head_healthz"));

    let response = send(&app, Method::HEAD, "/healthz").await;

    assert_eq!(response.status(), StatusCode::OK);
    assert_security_headers(&response, "HEAD /healthz");
    assert_eq!(text(response).await, "");
}

#[tokio::test]
async fn readyz_is_503_when_the_database_is_unreachable() {
    let app = router(unreachable_state("readyz_unreachable"));

    let response = send(&app, Method::GET, "/readyz").await;

    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(text(response).await, "database unavailable\n");
}

#[tokio::test]
async fn head_readyz_answers_503_when_the_database_is_unreachable() {
    let app = router(unreachable_state("head_readyz"));

    let response = send(&app, Method::HEAD, "/readyz").await;

    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
}

#[tokio::test]
async fn readyz_is_503_within_2s_when_the_database_hangs() {
    // A server that takes the connection and never writes a byte.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let accepted = std::thread::spawn(move || {
        let held: Vec<_> = listener.incoming().take(1).collect();
        std::thread::sleep(Duration::from_secs(5));
        held
    });
    let app = router(state_for("readyz_hangs", "127.0.0.1", port, "unused"));

    let started = Instant::now();
    let response = send(&app, Method::GET, "/readyz").await;
    let elapsed = started.elapsed();

    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
    assert!(
        elapsed < Duration::from_secs(3),
        "took {elapsed:?}, more than the 2 s budget plus slack"
    );
    drop(accepted);
}

#[tokio::test]
async fn the_ready_check_fails_when_the_database_is_unreachable() {
    let state = unreachable_state("ready_unreachable");

    assert!(!db::ready(&state.pool).await);
}

#[tokio::test]
async fn the_pool_takes_its_connection_options_from_the_config_alone() {
    // sqlx reads PGSSLMODE, PGAPPNAME and others from the process environment
    // unless the pool sets them, so each must be pinned. Reading them back
    // shows that the pool sets them, whatever the environment holds.
    let state = state_for("pool_options", "db.example", 6543, "unused");

    let options = state.pool.connect_options();

    assert_eq!(options.get_host(), "db.example");
    assert_eq!(options.get_port(), 6543);
    assert_eq!(options.get_username(), "postgres");
    assert_eq!(options.get_database(), Some("phyllon"));
    assert!(
        matches!(options.get_ssl_mode(), PgSslMode::Disable),
        "ssl mode was {:?}",
        options.get_ssl_mode()
    );
    assert_eq!(options.get_application_name(), Some("phyllon"));
}

#[tokio::test]
async fn every_response_carries_the_security_headers() {
    let app = router(unreachable_state("headers"));

    for method in [Method::GET, Method::HEAD] {
        for path in ["/healthz", "/readyz", "/no-such-page"] {
            let response = send(&app, method.clone(), path).await;
            assert_security_headers(&response, &format!("{method} {path}"));
        }
    }
}

#[tokio::test]
async fn an_unknown_path_is_404() {
    let app = router(unreachable_state("not_found"));

    let response = send(&app, Method::GET, "/no-such-page").await;

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    assert!(text(response).await.contains("Page not found"));
}

#[tokio::test]
async fn a_panicking_handler_returns_a_generic_500_and_the_server_keeps_serving() {
    async fn boom() -> &'static str {
        panic!("boom");
    }
    let app = with_security_layers(
        Router::new()
            .route("/boom", get(boom))
            .route("/ok", get(|| async { "fine" })),
    );

    let response = send(&app, Method::GET, "/boom").await;
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    assert_security_headers(&response, "the 500 of a caught panic");
    let body = text(response).await;
    assert!(!body.contains("boom"), "the panic message leaked: {body}");
    assert!(body.contains("Something went wrong"), "{body}");

    let response = send(&app, Method::GET, "/ok").await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(text(response).await, "fine");
}

#[test]
fn source_url_prefers_the_config() {
    let build = BuildInfo {
        version: "0.0.0",
        commit: Some("abc123"),
    };

    assert_eq!(
        source_url(Some("https://code.example/phyllon"), &build),
        "https://code.example/phyllon"
    );
}

#[test]
fn source_url_without_a_commit_points_at_the_repository() {
    assert_eq!(
        source_url(None, &BUILD),
        "https://github.com/nemesis398/phyllon"
    );
}

#[test]
fn source_url_with_a_commit_points_at_that_tree() {
    let build = BuildInfo {
        version: "0.0.0",
        commit: Some("abc123"),
    };

    assert_eq!(
        source_url(None, &build),
        "https://github.com/nemesis398/phyllon/tree/abc123"
    );
}

#[test]
fn build_info_reports_the_package_version() {
    assert_eq!(BuildInfo::current().version, env!("CARGO_PKG_VERSION"));
}

#[test]
fn the_security_headers_have_the_exact_values() {
    assert_eq!(
        SECURITY_HEADERS,
        [
            (
                "Content-Security-Policy",
                "default-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
            ),
            ("X-Content-Type-Options", "nosniff"),
            ("Referrer-Policy", "no-referrer"),
            ("Strict-Transport-Security", "max-age=31536000"),
            (
                "Permissions-Policy",
                "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
            ),
        ]
    );
}

/// Needs the PostgreSQL that CI starts, reached through the standard `PG*`
/// variables. The password goes through a file, as it does in production.
#[tokio::test]
#[ignore = "needs PostgreSQL"]
async fn readyz_is_200_with_a_database() {
    let var = |key: &str| std::env::var(key).unwrap();
    let password_file = test_dir("readyz_database").join("password");
    fs::write(&password_file, var("PGPASSWORD")).unwrap();
    let cfg = DatabaseConfig {
        host: var("PGHOST"),
        port: var("PGPORT").parse().unwrap(),
        name: var("PGDATABASE"),
        user: var("PGUSER"),
        password_file,
    };
    let secret = cfg.password().unwrap();
    let app = router(AppState {
        pool: db::pool(&cfg, &secret),
        build: BUILD,
        source_url: source_url(None, &BUILD),
    });

    let response = send(&app, Method::GET, "/readyz").await;

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(text(response).await, "ok\n");
}
