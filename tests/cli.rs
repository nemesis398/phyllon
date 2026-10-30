//! Tests for the command line: the health probe in process, and the binary's
//! `serve` and `healthcheck` commands as child processes. They touch no network
//! beyond 127.0.0.1, and the database they name is never there (port 1).

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use phyllon::cli::{probe, probe_addr};

/// The helpers sit in a `cfg(test)` module so that Clippy's
/// `allow-unwrap-in-tests` covers them, the way it covers `#[test]` functions.
#[cfg(test)]
mod support {
    use super::*;

    /// The password every test config points to. No output may contain it.
    pub const PASSWORD: &str = "s3cret-pw-4711";

    /// What the probe must send, byte for byte.
    pub const REQUEST: &[u8] =
        b"GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n";

    /// An address nothing listens on and nothing can bind without privileges.
    pub const NEVER_BOUND: &str = "127.0.0.1:1";

    /// Makes an empty directory for one test under the target directory, so tests
    /// that run in parallel never share a file.
    pub fn test_dir(name: &str) -> PathBuf {
        let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
            .join("cli")
            .join(name);
        if dir.exists() {
            fs::remove_dir_all(&dir).unwrap();
        }
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// A port nothing listens on right now: bind to port 0, note it, let go.
    pub fn free_addr() -> SocketAddr {
        TcpListener::bind((Ipv4Addr::LOCALHOST, 0))
            .unwrap()
            .local_addr()
            .unwrap()
    }

    /// Writes `config.toml` into `dir`, listening on `listen`, with the
    /// password in `dir/password` unless `password_file` says otherwise.
    pub fn write_config(dir: &Path, listen: &str, password_file: &Path) -> PathBuf {
        fs::write(dir.join("password"), PASSWORD).unwrap();
        let path = dir.join("config.toml");
        let body = format!(
            "listen = \"{listen}\"\n\
             public_url = \"http://localhost\"\n\
             [database]\n\
             host = \"127.0.0.1\"\n\
             port = 1\n\
             name = \"phyllon\"\n\
             user = \"phyllon_runtime\"\n\
             password_file = {:?}\n",
            password_file.to_str().unwrap()
        );
        fs::write(&path, body).unwrap();
        path
    }

    /// A config in a fresh directory of its own, with its password file.
    pub fn config_at(name: &str, listen: &str) -> PathBuf {
        let dir = test_dir(name);
        write_config(&dir, listen, &dir.join("password"))
    }

    /// The binary, without the variables that would change what it does.
    pub fn phyllon() -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_phyllon"));
        command
            .env_remove("PGOPTIONS")
            .env_remove("PHYLLON_CONFIG")
            .stdin(Stdio::null());
        command
    }

    /// What a finished child printed and how it ended.
    pub struct Finished {
        pub code: Option<i32>,
        pub stdout: String,
        pub stderr: String,
    }

    /// Polls `child` until it exits, killing it and failing the test after ten
    /// seconds.
    pub fn wait_bounded(child: &mut Child) -> ExitStatus {
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                return status;
            }
            if Instant::now() > deadline {
                child.kill().unwrap();
                child.wait().unwrap();
                panic!("the child did not exit within 10 s");
            }
            thread::sleep(Duration::from_millis(10));
        }
    }

    /// Reads a finished child's pipe to the end.
    pub fn read_all(mut pipe: impl Read) -> String {
        let mut text = String::new();
        pipe.read_to_string(&mut text).unwrap();
        text
    }

    /// Runs the binary with `args` and `envs` to the end.
    pub fn run(args: &[&str], envs: &[(&str, &str)]) -> Finished {
        let mut child = phyllon()
            .args(args)
            .envs(envs.iter().copied())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        let status = wait_bounded(&mut child);
        let mut stdout = String::new();
        let mut stderr = String::new();
        child
            .stdout
            .take()
            .unwrap()
            .read_to_string(&mut stdout)
            .unwrap();
        child
            .stderr
            .take()
            .unwrap()
            .read_to_string(&mut stderr)
            .unwrap();
        Finished {
            code: status.code(),
            stdout,
            stderr,
        }
    }

    /// Runs `phyllon <command> --config <config>` to the end.
    pub fn run_with_config(command: &str, config: &Path) -> Finished {
        run(&[command, "--config", config.to_str().unwrap()], &[])
    }

    /// A running `phyllon serve`, killed when the guard drops so that a failed
    /// assertion never leaves a server behind.
    pub struct Server {
        child: Child,
        /// A config that names the address the server really listens on.
        pub config: PathBuf,
        /// The address the server bound.
        pub listen: SocketAddr,
        /// The server's stderr, one line at a time, from a thread that keeps
        /// reading until the pipe closes, so the child never blocks on it.
        stderr: Receiver<String>,
        seen: Vec<String>,
    }

    impl Drop for Server {
        fn drop(&mut self) {
            // The child may have exited already; then there is nothing to do.
            if self.child.kill().is_ok() {
                self.child.wait().unwrap();
            }
        }
    }

    /// The address in serve's `phyllon is listening ... listen=<addr>` line.
    fn listening_addr(line: &str) -> Option<SocketAddr> {
        if !line.contains("phyllon is listening") {
            return None;
        }
        line.split("listen=")
            .nth(1)?
            .split_whitespace()
            .next()?
            .parse()
            .ok()
    }

    impl Server {
        /// Starts `phyllon serve` on port 0 and waits for its "listening" log
        /// line, which names the port the kernel gave it, so no test ever
        /// guesses a free port. Fails the test after five seconds or 50 lines,
        /// or when the server exits first.
        pub fn start(name: &str) -> Server {
            let dir = test_dir(name);
            let password = dir.join("password");
            let config = write_config(&dir, "127.0.0.1:0", &password);
            let mut child = phyllon()
                .args(["serve", "--config", config.to_str().unwrap()])
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .unwrap();
            let pipe = child.stderr.take().unwrap();
            let (sender, stderr) = mpsc::channel();
            thread::spawn(move || {
                for line in BufReader::new(pipe).lines() {
                    if line.is_err() || sender.send(line.unwrap()).is_err() {
                        break;
                    }
                }
            });
            let mut server = Server {
                child,
                config,
                listen: SocketAddr::from((Ipv4Addr::UNSPECIFIED, 0)),
                stderr,
                seen: Vec::new(),
            };
            let deadline = Instant::now() + Duration::from_secs(5);
            while server.seen.len() < 50 {
                let left = deadline.saturating_duration_since(Instant::now());
                let line = server.stderr.recv_timeout(left).unwrap_or_else(|error| {
                    panic!("no listening line ({error}); stderr: {:?}", server.seen)
                });
                let found = listening_addr(&line);
                server.seen.push(line);
                if let Some(listen) = found {
                    server.listen = listen;
                    // The server has read its config; a copy that names the real
                    // port serves `healthcheck`.
                    server.config = write_config(&dir, &listen.to_string(), &password);
                    return server;
                }
            }
            panic!("no listening line in 50 lines: {:?}", server.seen);
        }

        /// Sends `signal` (`TERM`, `INT`) through `kill(1)`, waits for the exit
        /// and returns what the server printed.
        pub fn stop(&mut self, signal: &str) -> Finished {
            let sent = Command::new("kill")
                .args([format!("-{signal}"), self.child.id().to_string()])
                .status()
                .unwrap();
            assert!(sent.success(), "kill -{signal} failed");
            let status = wait_bounded(&mut self.child);
            while let Ok(line) = self.stderr.recv_timeout(Duration::from_secs(2)) {
                self.seen.push(line);
            }
            Finished {
                code: status.code(),
                stdout: read_all(self.child.stdout.take().unwrap()),
                stderr: self.seen.join("\n"),
            }
        }
    }

    /// Accepts one connection and hands it to `serve_one` after reading the
    /// client's request up to the blank line. Returns the address and the
    /// thread, which yields the request bytes.
    pub fn serve_once(
        serve_one: impl FnOnce(&mut TcpStream) + Send + 'static,
    ) -> (SocketAddr, JoinHandle<Vec<u8>>) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let addr = listener.local_addr().unwrap();
        let handle = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut request = Vec::new();
            let mut chunk = [0_u8; 256];
            while !request.ends_with(b"\r\n\r\n") {
                let n = stream.read(&mut chunk).unwrap();
                if n == 0 {
                    break;
                }
                request.extend_from_slice(&chunk[..n]);
            }
            serve_one(&mut stream);
            request
        });
        (addr, handle)
    }

    /// Like [`serve_once`], answering with exactly `answer` and closing.
    pub fn answer_once(answer: &'static [u8]) -> (SocketAddr, JoinHandle<Vec<u8>>) {
        serve_once(move |stream| stream.write_all(answer).unwrap())
    }
    /// A server that writes `prefix`, then keeps the connection open until the
    /// returned sender fires (or ten seconds pass), like one that ignores
    /// `Connection: close`.
    pub fn open_server(
        prefix: &'static [u8],
    ) -> (SocketAddr, mpsc::Sender<()>, JoinHandle<Vec<u8>>) {
        let (release, wait) = mpsc::channel::<()>();
        let (addr, handle) = serve_once(move |stream| {
            stream.write_all(prefix).unwrap();
            wait.recv_timeout(Duration::from_secs(10)).ok();
        });
        (addr, release, handle)
    }
}
use support::*;

#[test]
fn probe_succeeds_against_a_running_server() {
    let answers: [&'static [u8]; 2] = [
        b"HTTP/1.1 200 OK\r\ncontent-length: 3\r\n\r\nok\n",
        b"HTTP/1.1 200",
    ];
    for answer in answers {
        let (addr, server) = answer_once(answer);

        probe(addr, Duration::from_secs(3)).unwrap();

        assert_eq!(server.join().unwrap(), REQUEST);
    }
}

#[test]
fn probe_fails_when_nothing_listens() {
    let started = Instant::now();

    let error = probe(free_addr(), Duration::from_secs(3)).unwrap_err();

    assert_eq!(format!("{error:?}").split('(').next(), Some("Connect"));
    assert!(started.elapsed() < Duration::from_secs(3));
}

#[test]
fn probe_fails_within_3s_when_the_server_never_answers() {
    let (addr, release, server) = open_server(b"");
    let started = Instant::now();

    let error = probe(addr, Duration::from_secs(3)).unwrap_err();
    let took = started.elapsed();

    release.send(()).unwrap();
    server.join().unwrap();
    assert_eq!(format!("{error:?}"), "Timeout");
    assert!(took >= Duration::from_secs(2), "gave up after {took:?}");
    assert!(took < Duration::from_secs(4), "took {took:?}");
}

#[test]
fn probe_bounds_the_whole_answer_not_each_read() {
    // One byte every 200 ms and never a line ending: each read succeeds, so
    // only a deadline over the whole probe stops it.
    let (addr, server) = serve_once(|stream| {
        for _ in 0..40 {
            if stream.write_all(b"x").is_err() {
                return;
            }
            thread::sleep(Duration::from_millis(200));
        }
    });
    let started = Instant::now();

    let error = probe(addr, Duration::from_secs(1)).unwrap_err();

    assert_eq!(format!("{error:?}"), "Timeout");
    assert!(started.elapsed() < Duration::from_secs(2));
    server.join().unwrap();
}

#[test]
fn probe_returns_at_the_end_of_the_status_line_without_waiting_for_the_close() {
    let (addr, release, server) = open_server(b"HTTP/1.1 200 OK\r\n");
    let started = Instant::now();

    let result = probe(addr, Duration::from_secs(3));
    let took = started.elapsed();

    release.send(()).unwrap();
    server.join().unwrap();
    result.unwrap();
    assert!(took < Duration::from_secs(1), "took {took:?}");
}

#[test]
fn probe_fails_on_an_answer_that_is_not_http() {
    // Every answer that is not a 200, with the error the probe must give. The
    // 503 is a well-formed HTTP answer, the rest are not HTTP/1.1 status lines.
    let cases: [(&'static [u8], &str); 7] = [
        (b"HTTP/1.1 503 Service Unavailable\r\n\r\n", "Status(503)"),
        (b"garbage\r\n", "NotHttp"),
        (b"", "NotHttp"),
        (b"HTTP/1.0 200 OK\r\n\r\n", "NotHttp"),
        (b"HTTP/1.1 2000 OK\r\n\r\n", "NotHttp"),
        (b"HTTP/1.1 20x OK\r\n\r\n", "NotHttp"),
        (b"HTTP/1.1\r\n\r\n", "NotHttp"),
    ];
    for (answer, expected) in cases {
        let (addr, server) = answer_once(answer);

        let error = probe(addr, Duration::from_secs(3)).unwrap_err();

        assert_eq!(format!("{error:?}"), expected, "answer {answer:?}");
        server.join().unwrap();
    }
}

#[test]
fn probe_stops_reading_an_answer_that_never_ends_its_first_line() {
    // The server never closes and never ends the line, so a reader without a
    // size limit would wait for the 3 s timeout instead.
    let (addr, server) = serve_once(|stream| {
        stream
            .set_write_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        while Instant::now() < deadline && stream.write_all(&[b'x'; 1024]).is_ok() {}
    });
    let started = Instant::now();

    let error = probe(addr, Duration::from_secs(3)).unwrap_err();
    let took = started.elapsed();

    assert_eq!(format!("{error:?}"), "NotHttp");
    assert!(took < Duration::from_secs(1), "took {took:?}");
    server.join().unwrap();
}

#[test]
fn probe_addr_maps_unspecified_addresses_to_loopback() {
    let map = |text: &str| probe_addr(text.parse().unwrap());

    assert_eq!(map("0.0.0.0:8080"), "127.0.0.1:8080".parse().unwrap());
    assert_eq!(map("[::]:8080"), "[::1]:8080".parse().unwrap());
    assert_eq!(map("10.0.0.5:9000"), "10.0.0.5:9000".parse().unwrap());
    assert_eq!(
        map("[2001:db8::1]:9000"),
        "[2001:db8::1]:9000".parse().unwrap()
    );
}

#[test]
fn serve_and_healthcheck_work_end_to_end() {
    // Once per signal: Ctrl-C and `docker stop` must both end the server
    // cleanly, with exit code 0, after the log has named the address.
    for signal in ["TERM", "INT"] {
        let mut server = Server::start(&format!("e2e-{signal}"));

        let healthy = run_with_config("healthcheck", &server.config);
        assert_eq!(healthy.code, Some(0), "stderr: {}", healthy.stderr);

        // The probe needs the config's address and nothing else: not the
        // password file, not the database. The path also comes in through the
        // environment.
        let dir = test_dir(&format!("e2e-no-password-{signal}"));
        let config = write_config(
            &dir,
            &server.listen.to_string(),
            &dir.join("no-such-password-file"),
        );
        let result = run(
            &["healthcheck"],
            &[("PHYLLON_CONFIG", config.to_str().unwrap())],
        );
        assert_eq!(result.code, Some(0), "stderr: {}", result.stderr);

        let finished = server.stop(signal);
        assert_eq!(finished.code, Some(0), "stderr: {}", finished.stderr);
        assert!(finished.stderr.contains(&format!("received SIG{signal}")));
        assert!(finished.stderr.contains(&server.listen.to_string()));
        assert!(finished.stderr.contains(env!("CARGO_PKG_VERSION")));
        assert!(!finished.stderr.contains(PASSWORD));
        assert_eq!(finished.stdout, "");
    }
}

#[test]
fn healthcheck_fails_when_nothing_listens() {
    let listen = free_addr();
    let config = config_at("healthcheck-down", &listen.to_string());

    let result = run_with_config("healthcheck", &config);

    assert_eq!(result.code, Some(1));
    assert!(result.stderr.starts_with("phyllon: "), "{}", result.stderr);
    assert!(
        result.stderr.contains(&listen.to_string()),
        "{}",
        result.stderr
    );
    assert_eq!(result.stdout, "");
}

#[test]
fn serve_refuses_to_start_while_pgoptions_is_set() {
    let config = config_at("pgoptions", NEVER_BOUND);

    let result = run(
        &["serve", "--config", config.to_str().unwrap()],
        &[("PGOPTIONS", "-c search_path=evil")],
    );

    assert_eq!(result.code, Some(1));
    assert!(result.stderr.starts_with("phyllon: "), "{}", result.stderr);
    assert!(result.stderr.contains("PGOPTIONS"), "{}", result.stderr);
    assert!(!result.stderr.contains("search_path"), "{}", result.stderr);
}

#[test]
fn serve_reports_a_start_failure_in_one_line() {
    // Held while the test runs, so the port is taken for certain.
    let holder = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let taken = holder.local_addr().unwrap().to_string();
    let dir = test_dir("no-password");
    let no_password = write_config(&dir, NEVER_BOUND, &dir.join("no-such-file"));
    let missing = test_dir("missing-config").join("config.toml");

    // (config, what the one line must contain)
    let cases = [
        (missing.clone(), missing.to_str().unwrap().to_owned()),
        (no_password, "database.password_file".to_owned()),
        (config_at("port-taken", &taken), taken),
    ];
    for (config, needle) in cases {
        let result = run_with_config("serve", &config);

        assert_eq!(result.code, Some(1), "{}", result.stderr);
        assert!(result.stderr.contains(&needle), "{}", result.stderr);
        assert_eq!(result.stderr.lines().count(), 1, "{}", result.stderr);
    }
}

#[test]
fn version_prints_the_version_and_the_commit_when_there_is_one() {
    let result = run(&["--version"], &[]);

    let version = env!("CARGO_PKG_VERSION");
    let expected = match option_env!("PHYLLON_GIT_COMMIT") {
        Some(commit) => format!("phyllon {version} ({commit})\n"),
        None => format!("phyllon {version}\n"),
    };
    assert_eq!(result.code, Some(0));
    assert_eq!(result.stdout, expected);
}

#[test]
fn a_missing_command_or_config_is_a_usage_error() {
    assert_eq!(run(&[], &[]).code, Some(2));
    let result = run(&["serve"], &[]);
    assert_eq!(result.code, Some(2));
    assert!(result.stderr.contains("--config"), "{}", result.stderr);
}
