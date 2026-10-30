//! The `phyllon` binary. All of its behavior lives in [`phyllon::cli`].

fn main() -> std::process::ExitCode {
    phyllon::cli::run()
}
