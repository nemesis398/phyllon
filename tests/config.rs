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

    /// Loads `body`, which must fail as a parse error, and returns the error's
    /// one-line message. Fails if `marker` shows in any form of the error,
    /// since a parse error must carry no text of the file.
    pub fn parse_error(name: &str, body: &str, marker: &str) -> String {
        let error = load(name, body).unwrap_err();
        for form in [
            format!("{error}"),
            format!("{error:?}"),
            format!("{error:#?}"),
        ] {
            assert!(!form.contains(marker), "{marker:?} leaked into: {form}");
        }
        assert!(matches!(error, ConfigError::Parse(_)), "got {error:?}");
        error.to_string()
    }

    /// A complete config with `extra` as line 2, before the `[database]` table.
    pub fn config(extra: &str) -> String {
        config_with(extra, "https://p.example")
    }

    /// A complete config with `line` added as line 8, at the end of the
    /// `[database]` table.
    pub fn database_with(line: &str) -> String {
        format!("{}{line}\n", config_with("", "https://p.example"))
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
    // The root table spans nothing, so no line is given.
    assert_eq!(
        error.to_string(),
        "invalid config: missing field `database`"
    );
}

#[test]
fn an_empty_file_lacks_the_public_url() {
    let text = parse_error("empty", "", "line");

    assert_eq!(text, "invalid config: missing field `public_url`");
}

#[test]
fn a_parse_error_is_a_std_error() {
    let error = load("std-error", "x = 1\n").unwrap_err();
    let ConfigError::Parse(inner) = error else {
        panic!("expected ConfigError::Parse, got {error:?}");
    };
    let inner: &dyn std::error::Error = &inner;

    assert!(inner.source().is_none());
    assert!(
        inner.to_string().starts_with("unknown field `x`"),
        "{inner}"
    );
    // A top-level key has no dotted path but keeps its position.
    assert!(inner.to_string().ends_with("(line 1, column 1)"), "{inner}");
}

#[test]
fn a_parse_error_cuts_a_long_key_name() {
    let key = format!("{}m-long-tail", "k".repeat(64));
    let body = config_with(&format!("{key} = 1"), "https://p.example");
    let text = parse_error("long-key", &body, "m-long-tail");

    assert!(
        text.starts_with(&format!(
            "invalid config: unknown field `{}…`, expected",
            "k".repeat(64)
        )),
        "{text}"
    );

    let exact = "k".repeat(64);
    let body = config_with(&format!("{exact} = 1"), "https://p.example");
    let text = load("exact-key", &body).unwrap_err().to_string();
    assert!(text.contains(&format!("`{exact}`,")), "{text}");
}

#[test]
fn real_syntax_errors_keep_their_description() {
    // (body, the message after `invalid config: `)
    let cases = [
        (
            "a = 1\na.b = 2\n",
            "cannot extend value of type integer with a dotted key (line 2, column 1)",
        ),
        (
            "when = 1979-05-27T07:32:00X\n",
            "invalid offset, expected `Z`, +OFFSET, -OFFSET (line 1, column 8)",
        ),
        (
            "when = 1979-02-30\n",
            "invalid date, expected day between 01 and 28 (line 1, column 8)",
        ),
        (
            "when = 07:3\n",
            "invalid time, expected a two-digit minute (MM) (line 1, column 8)",
        ),
        (
            "= 1\n",
            "unquoted keys cannot be empty, expected letters, numbers, `-`, `_` (line 1, column 1)",
        ),
        (
            "x = 1__2\n",
            "`_` may only go between digits, expected nothing (line 1, column 6)",
        ),
        (
            "x = tru\n",
            "invalid boolean, expected `true` (line 1, column 5)",
        ),
        (
            "[[a]\n",
            "unclosed array table, expected `]` (line 1, column 5)",
        ),
        // The column counts characters, not bytes: `ä` is two bytes.
        (
            "host = \"äöü\" x\n",
            "unexpected key or value, expected newline, `#` (line 1, column 14)",
        ),
        (
            "x = 1\r\ny = 2\r\nz = = 3\r\n",
            "extra `=`, expected nothing (line 3, column 5)",
        ),
    ];
    for (index, (body, expected)) in cases.iter().enumerate() {
        let error = load(&format!("syntax-{index}"), body).unwrap_err();
        assert_eq!(
            error.to_string(),
            format!("invalid config: {expected}"),
            "case {index}"
        );
    }
}

#[test]
fn a_parse_error_names_an_unknown_key_but_not_its_value() {
    let text = parse_error(
        "leak-unknown",
        &database_with("password = \"s3cr3t-unknown\""),
        "s3cr3t-unknown",
    );

    assert_eq!(
        text,
        "invalid config: unknown field `password`, expected one of `host`, \
         `port`, `name`, `user`, `password_file` (in `database`, line 8, column 1)"
    );
}

#[test]
fn a_parse_error_names_the_type_but_not_the_value() {
    let text = parse_error(
        "leak-type",
        &database_with("port = \"s3cr3t-type\""),
        "s3cr3t-type",
    );

    assert_eq!(
        text,
        "invalid config: invalid type: string, expected u16 \
         (in `database.port`, line 8, column 8)"
    );
}

#[test]
fn a_parse_error_names_the_key_of_a_value_out_of_range() {
    let text = parse_error("leak-range", &database_with("port = 70000"), "70000");

    assert_eq!(
        text,
        "invalid config: invalid value: integer, expected u16 \
         (in `database.port`, line 8, column 8)"
    );
}

#[test]
fn a_parse_error_names_a_missing_key() {
    let body = "public_url = \"https://p.example\"\n\
                [database]\n\
                host = \"db\"\n\
                user = \"phyllon_runtime\"\n\
                password_file = \"pw\"\n";
    let text = parse_error("missing-db-key", body, "phyllon_runtime");

    assert_eq!(
        text,
        "invalid config: missing field `name` (in `database`, line 2, column 1)"
    );
}

#[test]
fn a_syntax_error_does_not_quote_an_unterminated_string() {
    let body = config_with("source_url = \"s3cr3t-syntax", "https://p.example");
    let text = parse_error("leak-syntax", &body, "s3cr3t-syntax");

    assert_eq!(
        text,
        "invalid config: invalid basic string, expected `\"` (line 2, column 28)"
    );
}

#[test]
fn a_syntax_error_does_not_quote_a_string_with_a_bad_escape() {
    let body = config_with("source_url = \"s3cr3t-\\q-escape\"", "https://p.example");
    let text = parse_error("leak-escape", &body, "s3cr3t-");

    assert_eq!(
        text,
        "invalid config: missing escaped value, expected `b`, `e`, `f`, `n`, \
         `r`, `\\`, `\"`, `x`, `u`, `U` (line 2, column 23)"
    );
}

#[test]
fn no_parse_error_carries_text_of_the_file() {
    let withheld = "details withheld";
    // (body, a marker that only the file holds, a part of the message)
    let cases = [
        (
            database_with("api_token = \"m-01\""),
            "m-01",
            "field `api_token`, expected",
        ),
        (
            database_with("\"m-02`, expected `x\" = 1"),
            "m-02",
            withheld,
        ),
        (database_with("\"m-03 key\" = 1"), "m-03", withheld),
        (database_with("\"m-04\\nin `x\" = 1"), "m-04", withheld),
        (
            database_with("port = \"m-05, expected u16\""),
            "m-05",
            "string, expected u16 (",
        ),
        (
            database_with("port = 15.25"),
            "15.25",
            "type: floating point, expected u16",
        ),
        (
            database_with("port = [\"m-06\"]"),
            "m-06",
            "type: sequence, expected u16",
        ),
        (
            database_with("port = { m-07 = 1 }"),
            "m-07",
            "type: map, expected u16",
        ),
        (
            database_with("host = m-08"),
            "m-08",
            "must be quoted, expected literal string (line 8, column 8)",
        ),
        (
            database_with("host = 'm-09"),
            "m-09",
            "invalid literal string, expected `'` (line 8, column 13)",
        ),
        (
            database_with("host = \"\"\"m-10"),
            "m-10",
            "invalid multi-line basic string, expected `\"` (line 9, column 1)",
        ),
        (
            database_with("host = \"m-11\""),
            "m-11",
            "duplicate key (line 8, column 1)",
        ),
        (
            database_with("password: m-12"),
            "m-12",
            "no value, expected `=` (line 8, column 11)",
        ),
        (
            database_with("m-13"),
            "m-13",
            "no value, expected `=` (line 8, column 5)",
        ),
        (
            database_with("[m-14"),
            "m-14",
            "unclosed table, expected `]` (line 8, column 6)",
        ),
        (
            database_with("host = \"\\uZZZZ m-15\""),
            "m-15",
            "digits, expected unicode hexadecimal value (line 8, column 11)",
        ),
        (
            database_with("when = 1979-13-27"),
            "1979-13",
            "invalid date, expected month between 01 and 12 (line 8, column 8)",
        ),
        (
            config("listen = \"m-16\""),
            "m-16",
            "address syntax (in `listen`, line 2",
        ),
        (
            config("source_url = true"),
            "true",
            "boolean, expected a string",
        ),
        (config("m-17 = \"m-18\""), "m-18", "field `m-17`, expected"),
    ];
    for (index, (body, marker, part)) in cases.iter().enumerate() {
        let text = parse_error(&format!("leak-table-{index}"), body, marker);
        assert!(text.contains(part), "case {index}: {text}");
    }
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
fn accepts_an_http_source_url_and_rejects_anything_else() {
    let extra = |url: &str| format!("source_url = \"{url}\"");
    let config = load(
        "source-ok",
        &config_with(&extra("https://git.example/phyllon"), "https://p.example"),
    )
    .unwrap();
    assert_eq!(
        config.source_url.as_deref(),
        Some("https://git.example/phyllon")
    );

    for rejected in ["", "javascript:alert(1)"] {
        let error = load(
            "source-bad",
            &config_with(&extra(rejected), "https://p.example"),
        )
        .unwrap_err();
        assert!(
            matches!(&error, ConfigError::SourceUrl(value) if value == rejected),
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
