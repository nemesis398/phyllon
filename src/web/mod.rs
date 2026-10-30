//! The web UI shell: the start page, the branded error pages and the assets
//! that style them.
//!
//! Pages are Askama templates rendered to a `String`. Assets are compiled into
//! the binary and looked up by name in a fixed table, so a request path never
//! becomes a file path.

pub mod strings;

use askama::Template;
use axum::Router;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::http::header::{CACHE_CONTROL, CONTENT_TYPE};
use axum::response::{Html, IntoResponse, Response};
use axum::routing::get;
use tracing::error;

use crate::http::AppState;

/// How long a browser may reuse an asset without asking again.
const ASSET_CACHE_CONTROL: &str = "public, max-age=3600";

/// One file compiled into the binary.
struct Asset {
    /// The name after `/assets/`.
    name: &'static str,
    content_type: &'static str,
    body: &'static [u8],
}

const CSS: &str = "text/css; charset=utf-8";
const SVG: &str = "image/svg+xml";
const WOFF2: &str = "font/woff2";
const TEXT: &str = "text/plain; charset=utf-8";

/// Everything under `/assets/`. The palette and the logos are the files in
/// `brand/` itself, so the brand keeps one source.
const ASSETS: [Asset; 10] = [
    Asset {
        name: "phyllon.css",
        content_type: CSS,
        body: include_bytes!("../../assets/phyllon.css"),
    },
    Asset {
        name: "palette.css",
        content_type: CSS,
        body: include_bytes!("../../brand/palette.css"),
    },
    Asset {
        name: "logo.svg",
        content_type: SVG,
        body: include_bytes!("../../brand/logo.svg"),
    },
    Asset {
        name: "logo-dark.svg",
        content_type: SVG,
        body: include_bytes!("../../brand/logo-dark.svg"),
    },
    Asset {
        name: "favicon.svg",
        content_type: SVG,
        body: include_bytes!("../../brand/favicon.svg"),
    },
    Asset {
        name: "fonts/atkinson-hyperlegible-next-400.woff2",
        content_type: WOFF2,
        body: include_bytes!("../../assets/fonts/atkinson-hyperlegible-next-400.woff2"),
    },
    Asset {
        name: "fonts/atkinson-hyperlegible-next-700.woff2",
        content_type: WOFF2,
        body: include_bytes!("../../assets/fonts/atkinson-hyperlegible-next-700.woff2"),
    },
    Asset {
        name: "fonts/fraunces-600.woff2",
        content_type: WOFF2,
        body: include_bytes!("../../assets/fonts/fraunces-600.woff2"),
    },
    Asset {
        name: "fonts/OFL-AtkinsonHyperlegibleNext.txt",
        content_type: TEXT,
        body: include_bytes!("../../assets/fonts/OFL-AtkinsonHyperlegibleNext.txt"),
    },
    Asset {
        name: "fonts/OFL-Fraunces.txt",
        content_type: TEXT,
        body: include_bytes!("../../assets/fonts/OFL-Fraunces.txt"),
    },
];

/// What the footer says about the running build. Error pages have no build at
/// hand, so they leave it out.
struct Source<'a> {
    version: &'a str,
    url: &'a str,
}

/// What every page shares.
struct Shell<'a> {
    source: Option<Source<'a>>,
}

#[derive(Template)]
#[template(path = "index.html")]
struct StartPage<'a> {
    shell: Shell<'a>,
}

#[derive(Template)]
#[template(path = "error.html")]
struct ErrorPage<'a> {
    shell: Shell<'a>,
    heading: &'a str,
    text: &'a str,
}

/// The routes of the shell: the start page and the assets. The caller adds the
/// state and the fallback.
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(start_page))
        .route("/assets/{*path}", get(asset))
}

/// The branded 404 page, also the answer for an unknown asset.
pub async fn not_found() -> Response {
    page(
        StatusCode::NOT_FOUND,
        &ErrorPage {
            shell: Shell { source: None },
            heading: strings::NOT_FOUND_HEADING,
            text: strings::NOT_FOUND_TEXT,
        },
    )
}

/// The branded generic 500 page. It says nothing about the cause.
///
/// If even this page fails to render, the answer is a plain-text 500, since
/// nothing else is left to try.
#[must_use]
pub fn error_page() -> Response {
    let template = ErrorPage {
        shell: Shell { source: None },
        heading: strings::ERROR_HEADING,
        text: strings::ERROR_TEXT,
    };
    match template.render() {
        Ok(body) => (StatusCode::INTERNAL_SERVER_ERROR, Html(body)).into_response(),
        Err(err) => {
            error!(%err, "the error page failed to render");
            (StatusCode::INTERNAL_SERVER_ERROR, "internal server error\n").into_response()
        }
    }
}

/// Renders `template` with `status`, or answers with the branded 500 when
/// rendering fails.
fn page(status: StatusCode, template: &impl Template) -> Response {
    match template.render() {
        Ok(body) => (status, Html(body)).into_response(),
        Err(err) => {
            error!(%err, "a page failed to render");
            error_page()
        }
    }
}

async fn start_page(State(state): State<AppState>) -> Response {
    page(
        StatusCode::OK,
        &StartPage {
            shell: Shell {
                source: Some(Source {
                    version: state.build.version,
                    url: &state.source_url,
                }),
            },
        },
    )
}

async fn asset(Path(path): Path<String>) -> Response {
    match ASSETS.iter().find(|asset| asset.name == path) {
        Some(asset) => (
            [
                (CONTENT_TYPE, asset.content_type),
                (CACHE_CONTROL, ASSET_CACHE_CONTROL),
            ],
            asset.body,
        )
            .into_response(),
        None => not_found().await,
    }
}
