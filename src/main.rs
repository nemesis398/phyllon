//! The `phyllon` binary. All of its behavior lives in [`phyllon::cli`].

fn main() -> std::process::ExitCode {
    let _probe: u16 = "80".parse().unwrap();
    phyllon::cli::run()
}
