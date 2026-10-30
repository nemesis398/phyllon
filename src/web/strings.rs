//! Every English string the pages show, in one place, so that phase 2 can move
//! them into Fluent files without searching the templates.

/// The product name, also the wordmark.
pub const SITE_NAME: &str = "Phyllon";

/// The page language, for the `lang` attribute.
pub const LANGUAGE: &str = "en";

/// The heading of the start page.
pub const START_HEADING: &str = "A library of learning tasks";

/// What Phyllon is, on the start page.
pub const START_ABOUT: &str =
    "Phyllon keeps a library of learning tasks and serves it to MCP clients.";

/// What the visitor can do, on the start page.
pub const START_NOTHING_YET: &str = "There is nothing to sign in to yet.";

/// The title and heading of the 404 page.
pub const NOT_FOUND_HEADING: &str = "Page not found";

/// The text of the 404 page.
pub const NOT_FOUND_TEXT: &str = "There is nothing at this address.";

/// The title and heading of the generic 500 page.
pub const ERROR_HEADING: &str = "Something went wrong";

/// The text of the generic 500 page. It says nothing about the cause.
pub const ERROR_TEXT: &str = "Phyllon could not show this page. Try again in a moment.";

/// The link from an error page back to the start page.
pub const BACK_TO_START: &str = "Back to the start page";

/// The label before the version in the footer.
pub const VERSION_LABEL: &str = "Version";

/// The license, as an SPDX identifier, in the footer.
pub const LICENSE: &str = "AGPL-3.0-or-later";

/// The text of the source link in the footer.
pub const SOURCE_LINK: &str = "Source code";
