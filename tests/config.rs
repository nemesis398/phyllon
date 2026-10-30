//! Tests for loading the TOML configuration and reading its secrets.

use std::fs;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};

use phyllon::config::{Config, ConfigError, Secret};

/// The helpers sit in a `cfg(test)` module so that Clippy's
/// `allow-unwrap-in-tests` covers them, the way it covers `#[test]` functions.
#[cfg(test)]
mod support {
    use super::*;

    /// Makes an empty directory for one test under the target directory, so tests
    /// that run in parallel never share a file.
    pub fn test_dir(name: &str) -> PathBuf {
        let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
            .join("config")
            .join(name);
        if dir.exists() {
            fs::remove_dir_all(&dir).unwrap();
        }
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// Writes `config.toml` with `body` into the test's directory and loads it.
    pub fn load(name: &str, body: &str) -> Result<Config, ConfigError> {
        let path = test_dir(name).join("config.toml");
        fs::write(&path, body).unwrap();
        Config::load(&path)
    }

    /// A complete config with the given extra top-level lines, which must come
    /// before the first table header.
    pub fn config_with(extra: &str, public_url: &str) -> String {
        format!(
            "public_url = \"{public_url}\"\n{extra}\n\
             [database]\n\
             host = \"db\"\n\
             name = \"phyllon\"\n\
             user = \"phyllon_runtime\"\n\
             password_file = \"/run/secrets/db_runtime_password\"\n"
        )
    }

    /// Loads a config in `dir` whose database password lives in `password_file`.
    pub fn load_with_password_file(dir: &Path, password_file: &Path) -> Config {
        let body = format!(
            "public_url = \"https://phyllon.example\"\n\
             [database]\n\
             host = \"db\"\n\
             name = \"phyllon\"\n\
             user = \"phyllon_runtime\"\n\
             password_file = {:?}\n",
            password_file.to_str().unwrap()
        );
        let path = dir.join("config.toml");
        fs::write(&path, body).unwrap();
        Config::load(&path).unwrap()
    }

    /// Reads the password out of a file holding exactly `content`.
    pub fn password_from(name: &str, content: &[u8]) -> String {
        let dir = test_dir(name);
        let file = dir.join("password");
        fs::write(&file, content).unwrap();
        let config = load_with_password_file(&dir, &file);
        config.database.password().unwrap().expose().to_owned()
    }
}
use support::*;

#[test]
fn loads_a_minimal_config() {
    let config = load("minimal", &config_with("", "https://phyllon.example")).unwrap();

    assert_eq!(config.listen, "0.0.0.0:8080".parse::<SocketAddr>().unwrap());
    assert_eq!(config.public_url, "https://phyllon.example");
    assert_eq!(config.source_url, None);
    assert_eq!(config.database.host, "db");
    assert_eq!(config.database.port, 5432);
    assert_eq!(config.database.name, "phyllon");
    assert_eq!(config.database.user, "phyllon_runtime");
    assert_eq!(
        config.database.password_file,
        PathBuf::from("/run/secrets/db_runtime_password")
    );
}

#[test]
fn loads_every_optional_key() {
    let body = "listen = \"127.0.0.1:9000\"\n\
                public_url = \"http://localhost:9000\"\n\
                source_url = \"https://example.org/src\"\n\
                [database]\n\
                host = \"db\"\n\
                port = 6543\n\
                name = \"phyllon\"\n\
                user = \"phyllon_runtime\"\n\
                password_file = \"pw\"\n";
    let config = load("full", body).unwrap();

    assert_eq!(
        config.listen,
        "127.0.0.1:9000".parse::<SocketAddr>().unwrap()
    );
    assert_eq!(config.public_url, "http://localhost:9000");
    assert_eq!(
        config.source_url.as_deref(),
        Some("https://example.org/src")
    );
    assert_eq!(config.database.port, 6543);
}

#[test]
fn rejects_an_unknown_key() {
    let body = config_with("listn = \"0.0.0.0:80\"", "https://p.example");
    let error = load("unknown-key", &body).unwrap_err();

    match error {
        ConfigError::Parse(inner) => {
            assert!(
                inner.to_string().contains("unknown field `listn`"),
                "message was: {inner}"
            );
        }
        other => panic!("expected ConfigError::Parse, got {other:?}"),
    }
}

#[test]
fn rejects_an_unknown_key_in_the_database_table() {
    let body = format!("{}passwrd = \"x\"\n", config_with("", "https://p.example"));
    let error = load("unknown-db-key", &body).unwrap_err();

    match error {
        ConfigError::Parse(inner) => {
            assert!(
                inner.to_string().contains("unknown field `passwrd`"),
                "message was: {inner}"
            );
        }
        other => panic!("expected ConfigError::Parse, got {other:?}"),
    }
}

#[test]
fn rejects_a_missing_required_key() {
    let error = load("missing-key", "public_url = \"https://p.example\"\n").unwrap_err();

    assert!(matches!(error, ConfigError::Parse(_)), "got {error:?}");
}

#[test]
fn rejects_a_missing_config_file() {
    let path = test_dir("missing-file").join("nope.toml");
    let error = Config::load(&path).unwrap_err();

    match &error {
        ConfigError::Read { path: reported, .. } => assert_eq!(reported, &path),
        other => panic!("expected ConfigError::Read, got {other:?}"),
    }
    assert!(error.to_string().contains(path.to_str().unwrap()));
}

#[test]
fn rejects_a_public_url_without_an_http_scheme() {
    let error = load("bad-url", &config_with("", "phyllon.example")).unwrap_err();

    assert!(matches!(error, ConfigError::PublicUrl(_)), "got {error:?}");
}

#[test]
fn accepts_http_and_https_public_urls_and_nothing_else() {
    for accepted in ["https://a.example", "http://a.example"] {
        load("scheme-ok", &config_with("", accepted)).unwrap();
    }
    for rejected in [
        "",
        "ftp://a.example",
        "HTTPS://a.example",
        " https://a.example",
        "https:/a.example",
        "http:a.example",
    ] {
        let error = load("scheme-bad", &config_with("", rejected)).unwrap_err();
        assert!(
            matches!(error, ConfigError::PublicUrl(_)),
            "{rejected:?} gave {error:?}"
        );
    }
}

#[test]
fn reads_the_password_without_its_line_ending() {
    assert_eq!(password_from("pw-lf", b"s3cret\n"), "s3cret");
    assert_eq!(password_from("pw-crlf", b"s3cret\r\n"), "s3cret");
}

#[test]
fn strips_exactly_one_line_ending_and_nothing_else() {
    assert_eq!(password_from("pw-none", b"s3cret"), "s3cret");
    assert_eq!(password_from("pw-two-lf", b"s3cret\n\n"), "s3cret\n");
    assert_eq!(password_from("pw-lf-crlf", b"s3cret\n\r\n"), "s3cret\n");
    assert_eq!(password_from("pw-crlf-lf", b"s3cret\r\n\n"), "s3cret\r\n");
    assert_eq!(password_from("pw-lone-cr", b"s3cret\r"), "s3cret\r");
    assert_eq!(password_from("pw-spaces", b"  s3 cret  \n"), "  s3 cret  ");
    assert_eq!(password_from("pw-inner", b"s3\ncret\n"), "s3\ncret");
    assert_eq!(password_from("pw-only-lf", b"\n"), "");
    assert_eq!(password_from("pw-only-crlf", b"\r\n"), "");
    assert_eq!(password_from("pw-empty", b""), "");
}

#[test]
fn a_password_error_names_the_key_not_the_content() {
    let dir = test_dir("pw-missing");
    let missing = dir.join("no-such-password");
    let config = load_with_password_file(&dir, &missing);

    let error = config.database.password().unwrap_err();
    let text = error.to_string();

    assert!(matches!(error, ConfigError::Secret { .. }), "got {error:?}");
    assert!(
        text.contains("database.password_file"),
        "message was: {text}"
    );
    assert!(
        text.contains(missing.to_str().unwrap()),
        "message was: {text}"
    );
}

#[test]
fn a_password_that_is_not_utf8_fails_without_echoing_it() {
    let dir = test_dir("pw-binary");
    let file = dir.join("password");
    fs::write(&file, b"hunter2\xff\xfe").unwrap();
    let config = load_with_password_file(&dir, &file);

    let error = config.database.password().unwrap_err();
    let text = format!("{error} {error:?}");

    assert!(matches!(error, ConfigError::Secret { .. }), "got {error:?}");
    assert!(!text.contains("hunter2"), "message was: {text}");
}

#[test]
fn secret_debug_is_redacted() {
    let dir = test_dir("pw-debug");
    let file = dir.join("password");
    fs::write(&file, "s3cret\n").unwrap();
    let config = load_with_password_file(&dir, &file);
    let secret: Secret = config.database.password().unwrap();

    assert_eq!(format!("{secret:?}"), "Secret([redacted])");
    assert_eq!(format!("{secret:#?}"), "Secret([redacted])");
}
