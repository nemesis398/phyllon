//! The command line: `serve`, `healthcheck` and the probe behind it.
//!
//! The config file is the only configuration, so the commands take one option,
//! `--config` (or `PHYLLON_CONFIG`), and nothing else.

use std::io::{self, Read, Write};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, Instant};

use clap::{Args, CommandFactory, FromArgMatches, Parser, Subcommand};
use tokio::net::TcpListener;
use tokio::signal::unix::{SignalKind, signal};
use tracing::{Level, info};

use crate::config::{Config, ConfigError};
use crate::db;
use crate::http::{AppState, BuildInfo, router, source_url};

/// How long `healthcheck` waits for the whole probe.
const HEALTHCHECK_TIMEOUT: Duration = Duration::from_secs(3);

/// The most of the answer [`probe`] reads. The status line it needs is
/// `HTTP/1.1 200`, 12 bytes, so 64 is room for a reason phrase, and a server
/// that sends more cannot make the probe buffer more.
const MAX_ANSWER_BYTES: usize = 64;

/// The one request [`probe`] sends.
const PROBE_REQUEST: &[u8] =
    b"GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";

#[derive(Parser)]
#[command(name = "phyllon", about = "Phyllon keeps a library of learning tasks")]
struct Cli {
    #[command(subcommand)]
    action: Action,
}

#[derive(Subcommand)]
enum Action {
    /// Run the server until SIGTERM or Ctrl-C
    Serve(ConfigArgs),
    /// Ask the server on this host whether it is up; exit 0 if it is
    Healthcheck(ConfigArgs),
}

#[derive(Args)]
struct ConfigArgs {
    /// The TOML config file
    #[arg(long, env = "PHYLLON_CONFIG", value_name = "FILE")]
    config: PathBuf,
}

/// Why a command failed. Each message is shown to the operator as it is, so
/// none of them carries a secret.
#[derive(Debug, thiserror::Error)]
enum CliError {
    #[error(
        "PGOPTIONS is set, so serve will not start: sqlx cannot clear it, it can change any \
         setting of the database sessions, and the config file is the only configuration. \
         Unset PGOPTIONS."
    )]
    PgOptions,
    #[error("{0}")]
    Config(#[from] ConfigError),
    #[error("cannot start the async runtime: {0}")]
    Runtime(io::Error),
    #[error("cannot listen for signals: {0}")]
    Signals(io::Error),
    #[error("cannot set up logging: {0}")]
    Logging(String),
    #[error("cannot listen on {addr}: {source}")]
    Bind { addr: SocketAddr, source: io::Error },
    #[error("the server failed: {0}")]
    Serve(io::Error),
    #[error("the health check of {addr} failed: {source}")]
    Probe {
        addr: SocketAddr,
        source: ProbeError,
    },
}

/// Runs the command in the process's arguments and environment.
///
/// Returns success when the command did what it was asked. A usage error
/// gives exit code 2, as clap defines it. Any other failure prints
/// `phyllon: <reason>` on stderr, the reason being the error's own message,
/// and gives exit code 1.
#[must_use]
pub fn run() -> ExitCode {
    let build = BuildInfo::current();
    let cli = match parse(&build) {
        Ok(cli) => cli,
        Err(error) => {
            let code = u8::try_from(error.exit_code()).unwrap_or(2);
            // Nobody is left to tell when stdout or stderr is closed.
            error.print().ok();
            return ExitCode::from(code);
        }
    };
    let result = match cli.action {
        Action::Serve(args) => serve(&args.config, build),
        Action::Healthcheck(args) => healthcheck(&args.config),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("phyllon: {error}");
            ExitCode::FAILURE
        }
    }
}

/// Parses the arguments, with `--version` showing the build.
fn parse(build: &BuildInfo) -> Result<Cli, clap::Error> {
    let version = match build.commit {
        Some(commit) => format!("{} ({commit})", build.version),
        None => build.version.to_owned(),
    };
    let matches = Cli::command().version(version).try_get_matches()?;
    Cli::from_arg_matches(&matches)
}

/// Runs the server. Blocks until SIGTERM or SIGINT (Ctrl-C), then lets the
/// requests in flight finish and closes the pool.
fn serve(config_path: &Path, build: BuildInfo) -> Result<(), CliError> {
    if std::env::var_os("PGOPTIONS").is_some() {
        return Err(CliError::PgOptions);
    }
    let config = Config::load(config_path)?;
    let password = config.database.password()?;
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .with_writer(io::stderr)
        .try_init()
        .map_err(|error| CliError::Logging(error.to_string()))?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(CliError::Runtime)?;
    runtime.block_on(async {
        // Install both handlers before listening, so a signal that arrives
        // during start-up is not lost and a failure to install is reported.
        let mut interrupt = signal(SignalKind::interrupt()).map_err(CliError::Signals)?;
        let mut terminate = signal(SignalKind::terminate()).map_err(CliError::Signals)?;
        let bind_error = |source| CliError::Bind {
            addr: config.listen,
            source,
        };
        let listener = TcpListener::bind(config.listen).await.map_err(bind_error)?;
        let listening = listener.local_addr().map_err(bind_error)?;
        let state = AppState {
            pool: db::pool(&config.database, &password),
            build,
            source_url: source_url(config.source_url.as_deref(), &build),
        };
        let pool = state.pool.clone();
        info!(
            version = build.version,
            commit = build.commit,
            listen = %listening,
            "phyllon is listening"
        );
        axum::serve(listener, router(state))
            .with_graceful_shutdown(async move {
                tokio::select! {
                    _ = interrupt.recv() => info!("received SIGINT, shutting down"),
                    _ = terminate.recv() => info!("received SIGTERM, shutting down"),
                }
            })
            .await
            .map_err(CliError::Serve)?;
        pool.close().await;
        info!("phyllon stopped");
        Ok(())
    })
}

/// Probes the server this config makes. Reads the config file and nothing
/// else: not the password file, not the database.
fn healthcheck(config_path: &Path) -> Result<(), CliError> {
    let addr = probe_addr(Config::load(config_path)?.listen);
    probe(addr, HEALTHCHECK_TIMEOUT).map_err(|source| CliError::Probe { addr, source })
}

/// Why [`probe`] did not get a `200`.
#[derive(Debug, thiserror::Error)]
pub enum ProbeError {
    /// The connection could not be made, or not within the time limit.
    #[error("cannot connect: {0}")]
    Connect(io::Error),
    /// Writing the request or reading the answer failed.
    #[error("cannot talk to the server: {0}")]
    Io(io::Error),
    /// The server connected but did not finish its status line in time.
    #[error("the server did not answer in time")]
    Timeout,
    /// The server answered with this status instead of 200.
    #[error("the server answered with status {0}")]
    Status(u16),
    /// The answer does not start with an `HTTP/1.1` status line.
    #[error("the answer is not an HTTP/1.1 status line")]
    NotHttp,
}

/// Asks the server at `addr` for `/healthz` and succeeds only on a `200`.
///
/// Blocking, std only. The whole call, connecting included, takes about
/// `timeout` at most, even when the server answers one byte at a time. A
/// `timeout` of zero fails. The probe reads at most 64 bytes of the answer and
/// ignores the rest, so a server cannot make it buffer or wait for more. The
/// status line must start `HTTP/1.1` followed by a three-digit code.
///
/// # Errors
///
/// Returns a [`ProbeError`] that says whether the connection, the exchange,
/// the time limit, the status or the format of the answer failed.
pub fn probe(addr: SocketAddr, timeout: Duration) -> Result<(), ProbeError> {
    let started = Instant::now();
    let left = || {
        timeout
            .checked_sub(started.elapsed())
            .filter(|left| !left.is_zero())
            .ok_or(ProbeError::Timeout)
    };
    let mut stream = TcpStream::connect_timeout(&addr, timeout).map_err(ProbeError::Connect)?;
    stream
        .set_write_timeout(Some(left()?))
        .map_err(ProbeError::Io)?;
    stream.write_all(PROBE_REQUEST).map_err(io_error)?;

    let mut answer = Vec::with_capacity(MAX_ANSWER_BYTES);
    while answer.len() < MAX_ANSWER_BYTES && !answer.contains(&b'\n') {
        stream
            .set_read_timeout(Some(left()?))
            .map_err(ProbeError::Io)?;
        let mut chunk = [0_u8; MAX_ANSWER_BYTES];
        let room = MAX_ANSWER_BYTES - answer.len();
        let read = match stream.read(chunk.get_mut(..room).unwrap_or_default()) {
            Ok(0) => break,
            Ok(read) => read,
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(io_error(error)),
        };
        answer.extend_from_slice(chunk.get(..read).unwrap_or_default());
    }
    check_status_line(&answer)
}

/// A socket timeout is reported by the operating system as `WouldBlock` or
/// `TimedOut`.
fn io_error(error: io::Error) -> ProbeError {
    match error.kind() {
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut => ProbeError::Timeout,
        _ => ProbeError::Io(error),
    }
}

/// Accepts `HTTP/1.1 200` followed by a space, a line ending or the end.
fn check_status_line(answer: &[u8]) -> Result<(), ProbeError> {
    let line = answer
        .split(|byte| matches!(byte, b'\r' | b'\n'))
        .next()
        .unwrap_or_default();
    let mut parts = line.split(|byte| *byte == b' ');
    let (Some(b"HTTP/1.1"), Some(code)) = (parts.next(), parts.next()) else {
        return Err(ProbeError::NotHttp);
    };
    let status = if code.len() == 3 && code.iter().all(u8::is_ascii_digit) {
        std::str::from_utf8(code)
            .ok()
            .and_then(|digits| digits.parse::<u16>().ok())
    } else {
        None
    };
    match status {
        Some(200) => Ok(()),
        Some(other) => Err(ProbeError::Status(other)),
        None => Err(ProbeError::NotHttp),
    }
}

/// The address to probe for a server that listens on `listen`: the loopback
/// address of the same family when `listen` is unspecified (`0.0.0.0` or
/// `::`), because a connection to an unspecified address is not defined.
/// Any other address, and the port, stay as they are.
#[must_use]
pub fn probe_addr(listen: SocketAddr) -> SocketAddr {
    let ip = match listen.ip() {
        IpAddr::V4(ip) if ip.is_unspecified() => IpAddr::V4(Ipv4Addr::LOCALHOST),
        IpAddr::V6(ip) if ip.is_unspecified() => IpAddr::V6(Ipv6Addr::LOCALHOST),
        other => other,
    };
    SocketAddr::new(ip, listen.port())
}
