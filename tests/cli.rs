//! Tests for the command line: the health probe in process, and the binary's
//! `serve` and `healthcheck` commands as child processes. They touch no network
//! beyond 127.0.0.1, and the database they name is never there (port 1).

use std::fs;
use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, mpsc};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use phyllon::cli::{ProbeError, probe, probe_addr};

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

    /// The ports `free_addr` has handed out. The tests of this file run in
    /// parallel and the kernel may hand a released port to the next bind to
    /// port 0, so every bind to port 0 here skips these.
    static HANDED_OUT: Mutex<Vec<u16>> = Mutex::new(Vec::new());

    /// Binds a listener on a loopback port that no test holds or was given.
    pub fn bind_loopback() -> TcpListener {
        loop {
            let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
            let port = listener.local_addr().unwrap().port();
            if !HANDED_OUT.lock().unwrap().contains(&port) {
                return listener;
            }
        }
    }

    /// A port nothing listens on, which no other test of this file will get.
    pub fn free_addr() -> SocketAddr {
        let listener = bind_loopback();
        let addr = listener.local_addr().unwrap();
        HANDED_OUT.lock().unwrap().push(addr.port());
        addr
    }

    /// Writes `config.toml` into `dir`, listening on `listen`, with the
    /// password in `dir/password` unless `password_file` says otherwise.
    pub fn write_config(dir: &Path, listen: SocketAddr, password_file: &Path) -> PathBuf {
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

    /// A config for a fresh test directory and a free port, with its password
    /// file in place.
    pub fn fresh_config(name: &str) -> (PathBuf, SocketAddr) {
        let dir = test_dir(name);
        let listen = free_addr();
        (write_config(&dir, listen, &dir.join("password")), listen)
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
    /// seconds, and returns what it printed.
    pub fn finish(child: &mut Child) -> Finished {
        let deadline = Instant::now() + Duration::from_secs(10);
        let status = loop {
            if let Some(status) = child.try_wait().unwrap() {
                break status;
            }
            if Instant::now() > deadline {
                child.kill().unwrap();
                child.wait().unwrap();
                panic!("the child did not exit within 10 s");
            }
            thread::sleep(Duration::from_millis(10));
        };
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

    /// Runs the binary with `args` and `envs` to the end.
    pub fn run(args: &[&str], envs: &[(&str, &str)]) -> Finished {
        let mut child = phyllon()
            .args(args)
            .envs(envs.iter().copied())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        finish(&mut child)
    }

    /// Runs `phyllon <command> --config <config>` to the end.
    pub fn run_with_config(command: &str, config: &Path) -> Finished {
        run(&[command, "--config", config.to_str().unwrap()], &[])
    }

    /// A running `phyllon serve`, killed when the guard drops so that a failed
    /// assertion never leaves a server behind.
    pub struct Server {
        pub child: Child,
        pub config: PathBuf,
        pub listen: SocketAddr,
    }

    impl Drop for Server {
        fn drop(&mut self) {
            // The child may have exited already; then there is nothing to do.
            if self.child.kill().is_ok() {
                self.child.wait().unwrap();
            }
        }
    }

    impl Server {
        /// Starts `phyllon serve` on a free port and returns once the port
        /// accepts connections. Fails the test after five seconds, or when the
        /// server exits first.
        pub fn start(name: &str) -> Server {
            let (config, listen) = fresh_config(name);
            let child = phyllon()
                .args(["serve", "--config", config.to_str().unwrap()])
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
                .unwrap();
            let mut server = Server {
                child,
                config,
                listen,
            };
            let deadline = Instant::now() + Duration::from_secs(5);
            while TcpStream::connect(listen).is_err() {
                assert!(
                    server.child.try_wait().unwrap().is_none(),
                    "the server exited before it listened"
                );
                assert!(Instant::now() < deadline, "the server never listened");
                thread::sleep(Duration::from_millis(25));
            }
            server
        }

        /// Sends SIGTERM through `kill(1)` and waits for the exit.
        pub fn terminate(&mut self) -> Finished {
            let sent = Command::new("kill")
                .args(["-TERM", &self.child.id().to_string()])
                .status()
                .unwrap();
            assert!(sent.success(), "kill -TERM failed");
            finish(&mut self.child)
        }
    }

    /// Accepts one connection on a free port and hands it to `serve_one`
    /// together with whatever the client sent up to the blank line. Returns the
    /// address and the thread, which yields the request bytes.
    pub fn serve_once(
        serve_one: impl FnOnce(&mut TcpStream) + Send + 'static,
    ) -> (SocketAddr, JoinHandle<Vec<u8>>) {
        let listener = bind_loopback();
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
}
use support::*;

#[test]
fn probe_succeeds_against_a_running_server() {
    let (addr, server) = answer_once(b"HTTP/1.1 200 OK\r\ncontent-length: 3\r\n\r\nok\n");

    probe(addr, Duration::from_secs(3)).unwrap();

    assert_eq!(server.join().unwrap(), REQUEST);
}

#[test]
fn probe_accepts_a_status_line_without_a_reason() {
    let (addr, server) = answer_once(b"HTTP/1.1 200");

    probe(addr, Duration::from_secs(3)).unwrap();
    server.join().unwrap();
}

#[test]
fn probe_fails_when_nothing_listens() {
    let started = Instant::now();

    let error = probe(free_addr(), Duration::from_secs(3)).unwrap_err();

    assert!(matches!(error, ProbeError::Connect(_)), "got {error:?}");
    assert!(started.elapsed() < Duration::from_secs(3));
}

#[test]
fn probe_fails_within_3s_when_the_server_never_answers() {
    let (release, wait) = mpsc::channel::<()>();
    let (addr, server) = serve_once(move |_stream| {
        // Keep the connection open and silent until the probe has given up.
        wait.recv_timeout(Duration::from_secs(10)).ok();
    });
    let started = Instant::now();

    let error = probe(addr, Duration::from_secs(3)).unwrap_err();
    let took = started.elapsed();

    release.send(()).unwrap();
    server.join().unwrap();
    assert!(matches!(error, ProbeError::Timeout), "got {error:?}");
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

    assert!(matches!(error, ProbeError::Timeout), "got {error:?}");
    assert!(started.elapsed() < Duration::from_secs(2));
    server.join().unwrap();
}

#[test]
fn probe_returns_at_the_end_of_the_status_line_without_waiting_for_the_close() {
    // A server that ignores `Connection: close` and keeps the connection open.
    let (release, wait) = mpsc::channel::<()>();
    let (addr, server) = serve_once(move |stream| {
        stream.write_all(b"HTTP/1.1 200 OK\r\n").unwrap();
        wait.recv_timeout(Duration::from_secs(10)).ok();
    });
    let started = Instant::now();

    let result = probe(addr, Duration::from_secs(3));
    let took = started.elapsed();

    release.send(()).unwrap();
    server.join().unwrap();
    result.unwrap();
    assert!(took < Duration::from_secs(1), "took {took:?}");
}

#[test]
fn probe_fails_on_a_status_that_is_not_200() {
    let (addr, server) = answer_once(b"HTTP/1.1 503 Service Unavailable\r\n\r\n");

    let error = probe(addr, Duration::from_secs(3)).unwrap_err();

    assert!(matches!(error, ProbeError::Status(503)), "got {error:?}");
    server.join().unwrap();
}

#[test]
fn probe_fails_on_an_answer_that_is_not_http() {
    let answers: [&'static [u8]; 6] = [
        b"garbage\r\n",
        b"",
        b"HTTP/1.0 200 OK\r\n\r\n",
        b"HTTP/1.1 2000 OK\r\n\r\n",
        b"HTTP/1.1 20x OK\r\n\r\n",
        b"HTTP/1.1\r\n\r\n",
    ];
    for answer in answers {
        let (addr, server) = answer_once(answer);

        let error = probe(addr, Duration::from_secs(3)).unwrap_err();

        assert!(
            matches!(error, ProbeError::NotHttp),
            "{answer:?} gave {error:?}"
        );
        server.join().unwrap();
    }
}

#[test]
fn probe_stops_reading_a_long_answer_that_never_ends_a_line() {
    let long: &'static [u8] = &[b'x'; 4096];
    let (addr, server) = answer_once(long);

    let error = probe(addr, Duration::from_secs(3)).unwrap_err();

    assert!(matches!(error, ProbeError::NotHttp), "got {error:?}");
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
    let server = Server::start("e2e");

    let healthy = run_with_config("healthcheck", &server.config);
    assert_eq!(healthy.code, Some(0), "stderr: {}", healthy.stderr);

    // The probe needs the config's address and nothing else: not the password
    // file, not the database. The path also comes in through the environment.
    let dir = test_dir("e2e-no-password");
    let config = write_config(&dir, server.listen, &dir.join("no-such-password-file"));
    let result = run(
        &["healthcheck"],
        &[("PHYLLON_CONFIG", config.to_str().unwrap())],
    );
    assert_eq!(result.code, Some(0), "stderr: {}", result.stderr);
}

#[test]
fn healthcheck_fails_when_nothing_listens() {
    let (config, listen) = fresh_config("healthcheck-down");

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
fn serve_exits_cleanly_on_sigterm_and_logs_without_the_password() {
    let mut server = Server::start("sigterm");

    let finished = server.terminate();

    assert_eq!(finished.code, Some(0), "stderr: {}", finished.stderr);
    assert!(finished.stderr.contains(&server.listen.to_string()));
    assert!(finished.stderr.contains(env!("CARGO_PKG_VERSION")));
    assert!(!finished.stderr.contains(PASSWORD));
    assert_eq!(finished.stdout, "");
}

#[test]
fn serve_refuses_to_start_while_pgoptions_is_set() {
    let (config, _) = fresh_config("pgoptions");

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
fn serve_reports_a_missing_config_in_one_line() {
    let missing = test_dir("missing-config").join("config.toml");

    let result = run_with_config("serve", &missing);

    assert_eq!(result.code, Some(1));
    assert!(result.stderr.contains(missing.to_str().unwrap()));
    assert_eq!(result.stderr.lines().count(), 1, "{}", result.stderr);
}

#[test]
fn serve_reports_a_missing_password_file() {
    let dir = test_dir("missing-password");
    let config = write_config(&dir, free_addr(), &dir.join("no-such-file"));

    let result = run_with_config("serve", &config);

    assert_eq!(result.code, Some(1));
    assert!(result.stderr.contains("database.password_file"));
    assert_eq!(result.stderr.lines().count(), 1, "{}", result.stderr);
}

#[test]
fn serve_reports_a_port_that_is_taken() {
    // Held from the start, because a port that is only free can be taken by
    // the source port of any other test's connection in between.
    let holder = bind_loopback();
    let listen = holder.local_addr().unwrap();
    let dir = test_dir("port-taken");
    let config = write_config(&dir, listen, &dir.join("password"));

    let result = run_with_config("serve", &config);

    assert_eq!(result.code, Some(1));
    assert!(
        result.stderr.contains(&listen.to_string()),
        "{}",
        result.stderr
    );
    assert_eq!(result.stderr.lines().count(), 1, "{}", result.stderr);
}

#[test]
fn version_prints_the_version_and_the_commit_when_there_is_one() {
    let result = run(&["--version"], &[]);

    let expected = match option_env!("PHYLLON_GIT_COMMIT") {
        Some(commit) => format!("phyllon {} ({commit})\n", env!("CARGO_PKG_VERSION")),
        None => format!("phyllon {}\n", env!("CARGO_PKG_VERSION")),
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
