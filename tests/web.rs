//! Tests for the web UI shell: the start page, the branded error pages and the
//! compiled-in assets. They drive the router in process and touch no network.

use std::fs;
use std::path::PathBuf;

use axum::Router;
use axum::body::Body;
use axum::http::header::{CACHE_CONTROL, CONTENT_TYPE};
use axum::http::{Method, Request, Response, StatusCode};
use axum::routing::get;
use http_body_util::BodyExt;
use phyllon::config::DatabaseConfig;
use phyllon::db;
use phyllon::http::headers::SECURITY_HEADERS;
use phyllon::http::{AppState, BuildInfo, router, source_url, with_security_layers};
use tower::ServiceExt;

/// The helpers sit in a `cfg(test)` module so that Clippy's
/// `allow-unwrap-in-tests` covers them, the way it covers `#[test]` functions.
#[cfg(test)]
mod support {
    use super::*;

    /// A build with a version and a commit, so the footer has both to show.
    pub const BUILD: BuildInfo = BuildInfo {
        version: "1.2.3",
        commit: Some("abc123"),
    };

    /// Makes an empty directory for one test under the target directory, so tests
    /// that run in parallel never share a file.
    pub fn test_dir(name: &str) -> PathBuf {
        let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR"))
            .join("web")
            .join(name);
        if dir.exists() {
            fs::remove_dir_all(&dir).unwrap();
        }
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// The application state of a build whose database is not there: nothing
    /// listens on port 1, and the shell never asks it anything.
    pub fn state(name: &str) -> AppState {
        let password_file = test_dir(name).join("password");
        fs::write(&password_file, "unused").unwrap();
        let cfg = DatabaseConfig {
            host: "127.0.0.1".to_owned(),
            port: 1,
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

    /// Sends a GET request to `path` and returns the answer.
    pub async fn get_path(app: &Router, path: &str) -> Response<Body> {
        let request = Request::builder()
            .method(Method::GET)
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

    /// Whether a response body has no bytes. The assets may be binary, so this
    /// does not decode them as text.
    pub async fn text_is_empty(response: Response<Body>) -> bool {
        response
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .is_empty()
    }

    /// The value of a response header, as text.
    pub fn header<'a>(response: &'a Response<Body>, name: &str) -> &'a str {
        response
            .headers()
            .get(name)
            .unwrap_or_else(|| panic!("no {name} header"))
            .to_str()
            .unwrap()
    }
}
use support::*;

#[tokio::test]
async fn start_page_names_phyllon_and_links_the_source() {
    let app = router(state("start_page"));

    let response = get_path(&app, "/").await;

    assert_eq!(response.status(), StatusCode::OK);
    assert!(header(&response, "content-type").starts_with("text/html"));
    let body = text(response).await;
    assert!(body.contains("Phyllon"), "{body}");
    assert!(body.contains("1.2.3"), "the version is missing: {body}");
    assert!(
        body.contains(r#"href="https://github.com/nemesis398/phyllon/tree/abc123""#),
        "the source link is missing: {body}"
    );
}

#[tokio::test]
async fn the_shell_carries_the_security_headers() {
    let app = router(state("shell_headers"));

    for path in ["/", "/assets/phyllon.css"] {
        let response = get_path(&app, path).await;
        assert_eq!(response.status(), StatusCode::OK, "{path}");
        for (name, value) in SECURITY_HEADERS {
            let values: Vec<_> = response.headers().get_all(name).iter().collect();
            assert_eq!(values, [value], "{name} on {path}");
        }
    }
}

#[tokio::test]
async fn assets_have_their_types_and_cache_headers() {
    let app = router(state("assets"));

    for (path, content_type) in [
        ("/assets/phyllon.css", "text/css; charset=utf-8"),
        ("/assets/palette.css", "text/css; charset=utf-8"),
        (
            "/assets/fonts/atkinson-hyperlegible-next-400.woff2",
            "font/woff2",
        ),
        (
            "/assets/fonts/atkinson-hyperlegible-next-700.woff2",
            "font/woff2",
        ),
        ("/assets/fonts/fraunces-600.woff2", "font/woff2"),
        (
            "/assets/fonts/OFL-Fraunces.txt",
            "text/plain; charset=utf-8",
        ),
        ("/assets/logo.svg", "image/svg+xml"),
        ("/assets/logo-dark.svg", "image/svg+xml"),
        ("/assets/favicon.svg", "image/svg+xml"),
    ] {
        let response = get_path(&app, path).await;
        assert_eq!(response.status(), StatusCode::OK, "{path}");
        assert_eq!(
            header(&response, CONTENT_TYPE.as_str()),
            content_type,
            "{path}"
        );
        assert_eq!(
            header(&response, CACHE_CONTROL.as_str()),
            "public, max-age=3600",
            "{path}"
        );
        assert!(!text_is_empty(response).await, "{path} is empty");
    }

    for path in [
        "/assets/no-such-file.css",
        "/assets/fonts/",
        "/assets/../Cargo.toml",
        "/assets/fonts/../phyllon.css",
    ] {
        let response = get_path(&app, path).await;
        assert_eq!(response.status(), StatusCode::NOT_FOUND, "{path}");
        assert!(text(response).await.contains("Page not found"), "{path}");
    }
}

#[tokio::test]
async fn pages_load_nothing_from_other_origins() {
    let app = router(state("origins"));

    for path in ["/", "/no-such-page"] {
        let body = text(get_path(&app, path).await).await;
        assert!(!body.contains("<script"), "a script on {path}: {body}");
        assert!(!body.contains("<style"), "a style block on {path}: {body}");
        assert!(
            !body.contains("style=\""),
            "an inline style on {path}: {body}"
        );
        for (start, _) in body.match_indices("src=") {
            let rest = body.get(start..).unwrap();
            assert!(
                !rest.starts_with("src=\"http://") && !rest.starts_with("src=\"https://"),
                "an external src on {path}: {body}"
            );
        }
        for tag in body.split("<link").skip(1) {
            let tag = tag.split('>').next().unwrap();
            assert!(
                !tag.contains("href=\"http://") && !tag.contains("href=\"https://"),
                "an external link on {path}: {tag}"
            );
        }
    }
}

#[tokio::test]
async fn the_not_found_page_is_branded() {
    let app = router(state("not_found"));

    let response = get_path(&app, "/no-such-page").await;

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    assert!(header(&response, "content-type").starts_with("text/html"));
    let body = text(response).await;
    assert!(body.contains("Page not found"), "{body}");
    assert!(
        body.contains(r#"href="/""#),
        "no link back to the start: {body}"
    );
}

#[tokio::test]
async fn a_panic_shows_the_branded_error_page() {
    async fn boom() -> &'static str {
        panic!("secret detail");
    }
    let app = with_security_layers(Router::new().route("/boom", get(boom)));

    let response = get_path(&app, "/boom").await;

    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);
    assert!(header(&response, "content-type").starts_with("text/html"));
    let body = text(response).await;
    assert!(body.contains("Something went wrong"), "{body}");
    assert!(
        !body.contains("secret detail"),
        "the panic message leaked: {body}"
    );
}
