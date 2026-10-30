//! The TOML configuration file and the secrets it points to.
//!
//! The file holds no secret itself. A secret such as the database password
//! lives in its own file, and the config names that file, so the config can sit
//! in a repository or a log without leaking anything.

use std::fmt;
use std::fs;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};

use serde::Deserialize;

/// The TOML key whose file a [`ConfigError::Secret`] reports.
const PASSWORD_FILE_KEY: &str = "database.password_file";

/// Why the configuration could not be loaded.
///
/// No variant carries or prints the content of a secret file.
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
    /// holds a value of the wrong type.
    #[error("invalid config: {0}")]
    Parse(#[from] toml::de::Error),
    /// `public_url` does not start with `https://` or `http://`. Holds the
    /// offending value, which is not a secret.
    #[error("public_url must start with https:// or http://, got {0:?}")]
    PublicUrl(String),
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
    /// sets it.
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
    /// [`ConfigError::PublicUrl`] when `public_url` has no HTTP(S) scheme.
    pub fn load(path: &Path) -> Result<Config, ConfigError> {
        let text = fs::read_to_string(path).map_err(|source| ConfigError::Read {
            path: path.to_path_buf(),
            source,
        })?;
        let config: Config = toml::from_str(&text)?;
        if !(config.public_url.starts_with("https://") || config.public_url.starts_with("http://"))
        {
            return Err(ConfigError::PublicUrl(config.public_url));
        }
        Ok(config)
    }
}

fn default_listen() -> SocketAddr {
    SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 8080)
}

fn default_database_port() -> u16 {
    5432
}
