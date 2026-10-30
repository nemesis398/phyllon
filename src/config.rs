//! The TOML configuration file and the secrets it points to.
//!
//! The file holds no secret itself. A secret such as the database password
//! lives in its own file, and the config names that file, so the config can sit
//! in a repository or a log without leaking anything.

use std::fmt;
use std::fs;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::ops::Range;
use std::path::{Path, PathBuf};

use serde::Deserialize;

/// The TOML key whose file a [`ConfigError::Secret`] reports.
const PASSWORD_FILE_KEY: &str = "database.password_file";

/// Why the configuration could not be loaded.
///
/// No variant carries or prints the content of a secret file, and only
/// [`ConfigError::PublicUrl`] and [`ConfigError::SourceUrl`] carry a value from
/// the config file.
#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    /// The config file could not be read.
    #[error("cannot read the config file {}: {source}", .path.display())]
    Read {
        /// The path that was opened.
        path: PathBuf,
        /// The operating system's reason.
        source: std::io::Error,
    },
    /// The file is not valid TOML, has an unknown key, lacks a required key or
    /// holds a value of the wrong type. Carries no value from the file.
    #[error("invalid config: {0}")]
    Parse(ParseError),
    /// `public_url` does not start with `https://` or `http://`. Holds the
    /// offending value, which is not a secret.
    #[error("public_url must start with https:// or http://, got {0:?}")]
    PublicUrl(String),
    /// `source_url` is set but does not start with `https://` or `http://`, so
    /// an empty value and a `javascript:` link are refused. Holds the offending
    /// value, which is not a secret.
    #[error("source_url must start with https:// or http://, got {0:?}")]
    SourceUrl(String),
    /// A secret file named by the config could not be read as text.
    #[error("cannot read the secret file for {key} at {}: {source}", .path.display())]
    Secret {
        /// The config key that names the file, for example
        /// `database.password_file`.
        key: &'static str,
        /// The path of the secret file.
        path: PathBuf,
        /// The operating system's reason, which never contains the file's
        /// content.
        source: std::io::Error,
    },
}

/// Why the config file does not parse, told without quoting the file.
///
/// The `toml` error quotes the offending line in `Display`, holds the whole
/// file in `Debug`, and serde's messages quote the value they reject, so a
/// password pasted into the file would reach the log. This type keeps only the
/// line and column, the dotted key, and a message rebuilt from shapes known to
/// hold no value: TOML syntax messages, which `toml` and `toml_parser` build
/// from static text alone, and serde's `unknown field`, `missing field`,
/// `invalid type` and `invalid value` with the value cut out. Any other
/// message is withheld, so a shape this code does not know cannot leak.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    /// What went wrong, with no text of the file but key names.
    message: String,
    /// The dotted key the error is about, when there is one.
    key: Option<String>,
    /// The 1-based line and column the error points at.
    position: Option<(usize, usize)>,
}

/// The message for a serde error whose shape is not known to be free of values.
const WITHHELD: &str = "invalid key or value (details withheld because they could quote the file)";

impl ParseError {
    /// Wraps a TOML syntax error. Its message comes from static text in the
    /// parser, so it is kept whole.
    fn syntax(text: &str, error: &toml::de::Error) -> Self {
        ParseError {
            message: error.message().to_owned(),
            key: None,
            position: position(text, error.span()),
        }
    }

    /// Wraps an error from fitting the TOML to [`Config`]. Its message may
    /// quote a value, so only known shapes survive, with the value cut out.
    fn schema(text: &str, error: &toml::de::Error) -> Self {
        ParseError {
            message: safe_message(error.message()).unwrap_or_else(|| WITHHELD.to_owned()),
            key: key_path(error),
            position: position(text, error.span()),
        }
    }
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)?;
        match (&self.key, self.position) {
            (Some(key), Some((line, column))) => {
                write!(f, " (in `{key}`, line {line}, column {column})")
            }
            (Some(key), None) => write!(f, " (in `{key}`)"),
            (None, Some((line, column))) => write!(f, " (line {line}, column {column})"),
            (None, None) => Ok(()),
        }
    }
}

/// Turns the start of `span` into a 1-based line and column of `text`.
fn position(text: &str, span: Option<Range<usize>>) -> Option<(usize, usize)> {
    let before = text.get(..span?.start)?;
    let line_start = before.rfind('\n').map_or(0, |newline| newline + 1);
    let column = before.get(line_start..)?.chars().count();
    Some((before.matches('\n').count() + 1, column + 1))
}

/// Whether `name` is a bare TOML key, so that it holds no quote, space,
/// backtick or line break.
fn is_bare_key(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// The dotted key of a serde error. `toml` exposes it only in `Display`, which
/// without the file's text is the message, then `in `, the key in backticks.
fn key_path(error: &toml::de::Error) -> Option<String> {
    let shown = error.to_string();
    let key = shown
        .strip_prefix(error.message())?
        .strip_prefix("\nin `")?
        .strip_suffix("`\n")?;
    key.split('.').all(is_bare_key).then(|| key.to_owned())
}

/// Rebuilds a serde message from the shapes that serde produces for
/// [`Config`], or `None` for any other shape.
fn safe_message(message: &str) -> Option<String> {
    if let Some(rest) = message.strip_prefix("unknown field `") {
        // The name ends at the first backtick. A quoted key holding a backtick
        // would end it early, and then the rest holds a second `, expected `.
        let (name, expected) = rest.split_once('`')?;
        let one_list =
            expected.starts_with(", expected ") && expected.matches(", expected ").count() == 1;
        return (is_bare_key(name) && one_list).then(|| message.to_owned());
    }
    if let Some(name) = message
        .strip_prefix("missing field `")
        .and_then(|rest| rest.strip_suffix('`'))
    {
        return is_bare_key(name).then(|| message.to_owned());
    }
    for kind in ["invalid type: ", "invalid value: "] {
        if let Some(rest) = message.strip_prefix(kind) {
            // What serde expected comes last and never holds `, expected `.
            let (found, expected) = rest.rsplit_once(", expected ")?;
            let found = value_kind(found)?;
            let plain = expected
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == ' ');
            return plain.then(|| format!("{kind}{found}, expected {expected}"));
        }
    }
    (message == "invalid socket address syntax").then(|| message.to_owned())
}

/// The kind of a TOML value as serde names it, without the value itself.
fn value_kind(found: &str) -> Option<&'static str> {
    const WITH_VALUE: [(&str, &str); 4] = [
        ("string \"", "string"),
        ("integer `", "integer"),
        ("floating point `", "floating point"),
        ("boolean `", "boolean"),
    ];
    if let Some((_, kind)) = WITH_VALUE
        .iter()
        .find(|(prefix, _)| found.starts_with(prefix))
    {
        return Some(kind);
    }
    ["sequence", "map"].into_iter().find(|kind| found == *kind)
}

/// A secret value that cannot leak through `Debug`.
///
/// Printing it with `{:?}` gives `Secret([redacted])`. The only way to get the
/// text is [`Secret::expose`], so every use of the value is easy to find.
pub struct Secret(String);

impl Secret {
    /// Returns the secret text. Do not log it.
    #[must_use]
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Secret([redacted])")
    }
}

/// The settings for the PostgreSQL connection.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DatabaseConfig {
    /// The server's host name or address.
    pub host: String,
    /// The server's port. Defaults to 5432.
    #[serde(default = "default_database_port")]
    pub port: u16,
    /// The database name.
    pub name: String,
    /// The role to connect as.
    pub user: String,
    /// The file that holds the role's password. The file is read by
    /// [`DatabaseConfig::password`], not when the config loads.
    pub password_file: PathBuf,
}

impl DatabaseConfig {
    /// Reads the database password from `password_file`.
    ///
    /// Strips one trailing `\n` or `\r\n` and nothing else, so a password may
    /// start or end with spaces and a second line ending stays.
    ///
    /// # Errors
    ///
    /// Returns [`ConfigError::Secret`] when the file cannot be read or is not
    /// UTF-8. The error names the key and the path, never the content.
    pub fn password(&self) -> Result<Secret, ConfigError> {
        let mut text =
            fs::read_to_string(&self.password_file).map_err(|source| ConfigError::Secret {
                key: PASSWORD_FILE_KEY,
                path: self.password_file.clone(),
                source,
            })?;
        let kept = text
            .strip_suffix("\r\n")
            .or_else(|| text.strip_suffix('\n'))
            .map_or(text.len(), str::len);
        text.truncate(kept);
        Ok(Secret(text))
    }
}

/// The whole configuration of the server.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    /// The address to listen on. Defaults to `0.0.0.0:8080`.
    #[serde(default = "default_listen")]
    pub listen: SocketAddr,
    /// The address the public reaches the site at. [`Config::load`] guarantees
    /// that it starts with `https://` or `http://`.
    pub public_url: String,
    /// Where the running version's source code is offered, if the operator
    /// sets it. [`Config::load`] guarantees that a set value starts with
    /// `https://` or `http://`, because the site links to it.
    #[serde(default)]
    pub source_url: Option<String>,
    /// The database connection.
    pub database: DatabaseConfig,
}

impl Config {
    /// Reads and validates the config file at `path`.
    ///
    /// Unknown keys in any table are errors, so a misspelled key cannot pass
    /// silently. The secret files are not read here.
    ///
    /// # Errors
    ///
    /// Returns [`ConfigError::Read`] when the file cannot be read,
    /// [`ConfigError::Parse`] when it is not a valid config, and
    /// [`ConfigError::PublicUrl`] or [`ConfigError::SourceUrl`] when
    /// `public_url` or a set `source_url` has no HTTP(S) scheme.
    pub fn load(path: &Path) -> Result<Config, ConfigError> {
        let text = fs::read_to_string(path).map_err(|source| ConfigError::Read {
            path: path.to_path_buf(),
            source,
        })?;
        // Parsing first and fitting the result to `Config` second tells a
        // syntax error from a serde error, which needs more care.
        let table = toml::de::DeTable::parse(&text)
            .map_err(|error| ConfigError::Parse(ParseError::syntax(&text, &error)))?;
        let config = Config::deserialize(toml::de::Deserializer::from(table))
            .map_err(|error| ConfigError::Parse(ParseError::schema(&text, &error)))?;
        if !has_http_scheme(&config.public_url) {
            return Err(ConfigError::PublicUrl(config.public_url));
        }
        if let Some(url) = config.source_url.as_deref()
            && !has_http_scheme(url)
        {
            return Err(ConfigError::SourceUrl(url.to_owned()));
        }
        Ok(config)
    }
}

fn has_http_scheme(url: &str) -> bool {
    url.starts_with("https://") || url.starts_with("http://")
}

fn default_listen() -> SocketAddr {
    SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 8080)
}

fn default_database_port() -> u16 {
    5432
}
