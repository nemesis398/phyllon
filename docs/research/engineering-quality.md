# Engineering Quality

Checked on 2026-10-29 against primary sources (papers, official docs, repos, registries, changelogs). Version numbers come from the crates.io API and the GitHub API on the check date. Confidence labels:

- **primary**: read in the paper, the official docs or the repo.
- **secondary**: vendor report, blog, or a summary of a primary source.
- **unverified**: inferred, not found, or not checked. Treat as a hypothesis.

Unless a line says otherwise, a figure comes from the linked source and was read on the check date.

## 1. Summary

1. AI-written code is flawed often and does not get safer with newer models. Veracode: 45% of samples failed security tests in 2025, and the 2026 report puts the average pass rate at 56% across 100+ models over four years and says it "hasn't moved". On SusVibes, 82.8% of the functionally correct solutions from the best agent setup were insecure.
2. Self-review by the same model does not work reliably. Models fix an error that is shown as external input but miss the same error in their own output (64.5% blind spot). Review has to come from outside the model: compiler, tests, analyzers, a fresh context, ideally a different model.
3. What measurably helps is external feedback: compiler errors (RustAssistant fixed about 74% of real Rust compile errors), static-analysis loops (security issues fell from over 40% to 13% in one Python study), and tests that exist before the code. Instructions alone help little: a security hint in the prompt changed nothing on SusVibes, and an AGENTS.md raised no success rate in the ETH study.
4. Rust removes one defect class (memory safety; Google measured 1000x lower vulnerability density than C/C++) but not logic, authorization, injection or denial-of-service bugs. No study measured vulnerability rates of AI-written Rust. **unverified** that the Python/Java/JS results transfer, but nothing suggests they do not.
5. Rust has a supply-chain problem that bites agents: `build.rs` and proc macros run on `cargo build`, `check` and `test`. On 2026-08-20 three popular crates were poisoned that way. Commit `Cargo.lock`, use `--locked`, run `cargo-deny`, delay dependency updates by a cooldown, and never give a compile step any secret.
6. CI placement: run almost everything on GitHub-hosted runners. Standard Linux x64 and arm64 runners (4 vCPU, 16 GB) are free and unlimited for public repositories. GitHub says self-hosted runners "should almost never be used for public repositories". Keep the homelab for GPU and local-model jobs, driven from Forgejo, never from GitHub pull request events.
7. The paid-API battery runs on a GitHub-hosted runner, on `schedule` and `workflow_dispatch` only, with the keys in a protected environment (deployment branch restricted to `main`, or a required reviewer), a compile job without secrets, and a spending cap at the provider.
8. The maintainer is learning. An Anthropic randomized trial (n=52) found that delegating to AI cut comprehension by 17% (quiz 50% vs 67%) while asking for explanations did not. Rule 15 makes agents explain.

## 2. Evidence on AI-written bugs

### 2.1 Baseline: how often AI output is wrong

| Practice | Evidence | Effect | Source |
|---|---|---|---|
| Unreviewed completion (2021, Copilot) | 89 scenarios, 1,689 programs | About 40% vulnerable. Old model, but the method is the reference. | [Pearce et al.](https://arxiv.org/abs/2108.09293) |
| Developers using an assistant | User study, codex-davinci-002 | Assistant users wrote significantly less secure code and were more confident it was secure. | [Perry et al.](https://arxiv.org/abs/2211.03622) |
| LLM code security benchmark (vendor) | 100+ models, 4 languages | 45% of samples failed security tests (Java 72%, C# 45%, JS 43%, Python 38%). XSS defenses failed in 86% of relevant samples. Size and recency did not help. | [Veracode 2025](https://www.veracode.com/blog/genai-code-security-report/) |
| Same benchmark, 2026 edition | 100+ models over four years, 11 new models, 80 tasks | Average pass rate 56%, "hasn't moved". Secondary: vendor report; how it checks the code is **unverified**. | [Veracode 2026](https://www.veracode.com/resources/analyst-reports/2026-genai-code-security-report/) |
| Backend generation benchmark | BaxBench, 392 tasks (28 scenarios, 14 frameworks, 6 languages) | Site headline: 62% of the best model's solutions are incorrect or insecure. On average about half of the correct solutions are insecure. | [BaxBench](https://baxbench.com/), [paper](https://arxiv.org/abs/2502.11844) |
| Coding agents on real repos | SusVibes, about 200 tasks, Claude 4 Sonnet era | SWE-agent: 61.0% functional, 10.5% secure. 82.8% of its functional solutions were insecure. Newer models **unverified**. | [SusVibes](https://arxiv.org/html/2512.03262v1) |
| AI co-authored PRs vs human PRs (vendor) | 470 PRs (320 AI, 150 human), authorship inferred | 10.83 vs 6.45 issues per PR (1.7x). Logic errors 1.75x, security up to 2.74x, readability over 3x, excessive I/O about 8x. | [CodeRabbit](https://www.coderabbit.ai/blog/state-of-ai-vs-human-code-generation-report) |
| Cursor adoption, observational | 807 repos vs 1,380 controls | Lines added +28.6% but transient (about two months). Static-analysis warnings +29.7% and complexity +40.7% persisted (the paper also cites about 25%, inconsistent). | [Cursor DiD](https://arxiv.org/html/2511.04427v2) |
| Code structure drift (vendor) | 211M changed lines, 2020 to 2024 | Copy/pasted lines 8.3% to 12.3%. Refactoring (moved lines) 25% to under 10%. | [GitClear](https://www.gitclear.com/ai_assistant_code_quality_2025_research) |
| Delivery metrics | DORA 2025 | "AI is an amplifier" of existing strengths and weaknesses. The 2024 figure (25% more AI adoption, 7.2% less delivery stability) is **secondary**, from a third-party summary. | [DORA 2025](https://dora.dev/dora-report-2025/) |
| Invented dependencies | 576,000 samples, 16 models, Python and JS | Hallucinated packages: at least 5.2% (commercial models), 21.7% (open models). 205,474 unique fake names. Rust not tested (**unverified** for crates). | [Spracklen et al.](https://arxiv.org/abs/2406.10279) |
| Outdated APIs | RustEvo^2, 588 API changes | Success 56.1% on APIs older than the model's cutoff, 32.5% on newer ones. Retrieval of docs gave +13.5% on newer APIs. | [RustEvo^2](https://arxiv.org/abs/2503.16922) |
| Language choice | Android, about 5M lines of Rust | 1000x lower memory-safety vulnerability density than C/C++, 4x lower rollback rate, 25% less review time. Not AI-specific. | [Google](https://blog.google/security/rust-in-android-move-fast-fix-things/) |
| Real incident: poisoned crates | arrayref, internment, append-only-vec, 2026-08-20 | Each added a typosquatted dependency whose `build.rs` downloaded and ran malware during `cargo build`, `check` and `test`. Live for 86 to 107 minutes each. | [The Hacker News](https://thehackernews.com/2026/08/rust-supply-chain-attack-puts-build.html), [Socket](https://socket.dev/blog/popular-rust-crates-compromised) |

### 2.2 What reduces defects (evidence table)

| Practice | Evidence | Effect | Source |
|---|---|---|---|
| Same-model self-correction (no external signal) | Survey and experiments | Performance can degrade after self-correction. No prior work shows success with feedback from prompted LLMs alone, except on tasks suited to it. | [Huang et al.](https://arxiv.org/abs/2310.01798), [Kamoi et al.](https://arxiv.org/abs/2406.01297) |
| Self-correction blind spot | 14 open non-reasoning models | 64.5% blind spot: errors are fixed when shown as external input, missed in the model's own output. Appending "Wait" cut it by 89.3%. Old model class. | [Self-Correction Bench](https://arxiv.org/abs/2507.02778) |
| Iterating "improve this" with no tools | 400 samples, 40 rounds | Critical vulnerabilities rose 37.6% after five iterations. | [Security degradation](https://arxiv.org/abs/2506.11022) |
| Compiler feedback loop | Rust, real compile errors | Iterating LLM and rustc fixed up to about 74% of real-world compile errors (model and sample size not on the abstract page). | [RustAssistant](https://arxiv.org/abs/2308.05177) |
| Static-analysis feedback loop | GPT-4o, PythonSecurityEval, 10 iterations of Bandit and Pylint feedback | Security issues over 40% to 13%, readability violations over 80% to 11%, reliability warnings over 50% to 11%. One model, Python, preprint. | [Static analysis as feedback](https://arxiv.org/abs/2508.14419) |
| Tests before code (TDD) | MBPP, HumanEval, GPT-4 and Llama 3 | Giving tests with the task "consistently" raised success. No numbers on the abstract page. Function-level only. | [Mathews and Nagappan](https://arxiv.org/abs/2402.13521) |
| Red/green discipline | Practitioner guide | Watching the test fail first proves it exercises the new code. Guards against unneeded code and regressions. No measurement. | [Willison](https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/) |
| A near-perfect verifier | 16 parallel agents, Rust C compiler | "The task verifier must be nearly perfect, otherwise Claude will solve the wrong problem." New features kept breaking old ones until CI blocked regressions. | [Carlini](https://www.anthropic.com/research/building-c-compiler) |
| Property-based tests by an agent | 100 popular Python packages | 56% of the agent's bug reports valid, 32% reportable. Top-ranked 21: 86% valid, 81% reportable. 5 reported, 4 patched. | [Agentic PBT](https://arxiv.org/abs/2510.09907) |
| Mutation testing | Meta, 10,795 classes, 9,095 mutants | Engineers accepted 73% of the generated tests. No defect-reduction measure. A 2026 study finds coverage and mutation scores unreliable when the code under test is buggy. | [Meta ACH](https://arxiv.org/abs/2501.12862), [2607.22880](https://arxiv.org/abs/2607.22880) |
| Reviewer is a different model | 116 LiveCodeBench tasks, reviewer cannot run code | Codex draft: 71.6% solo, 84.5% with Codex review (+12.9), 89.7% with Claude review (+18.1). Claude draft: 91.4% solo, 91.4% with Claude review (0), 82.8% with Codex review (-8.6). Asymmetric, one preprint, one benchmark. | [Cross-model review](https://arxiv.org/abs/2607.21656) |
| Judge prefers its own style | GPT-4 as judge | Significant self-preference, explained by lower perplexity of familiar text. | [Self-preference bias](https://arxiv.org/abs/2410.21819) |
| AI review agents in practice | AIDev, 3,109 PRs | PRs reviewed only by review agents merged 45.20% vs 68.37% for human-only. 60.2% of 98 closed agent-only PRs had a signal ratio of 0 to 30%. Authors: augment, not replace. | [From industry claims to reality](https://arxiv.org/abs/2604.03196) |
| Security instruction in the prompt | SusVibes hint ablation | Generic reminder 10.5% secure, self-selected CWE hint 9.5%, oracle CWE hint 10.5%. Functional pass dropped 5.5 to 8.5 points. | [SusVibes](https://arxiv.org/html/2512.03262v1) |
| Security prompting techniques | GPT-3, 3.5, 4, 150 prompts | Recursive criticism and improvement reduced weaknesses. No figures on the abstract page. Old models. | [Prompting for secure code](https://arxiv.org/abs/2407.07064) |
| AGENTS.md / CLAUDE.md | ETH, SWE-bench and real repos | No general gain in task success, over 20% higher inference cost. Agents follow the instructions, repo overviews do not help. Use for non-standard practices only. | [Gloaguen et al.](https://arxiv.org/abs/2602.11988) |
| AGENTS.md efficiency | 10 repos, 124 PRs | Median runtime -28.64%, output tokens -16.58%, comparable completion. | [Lulla et al.](https://arxiv.org/abs/2601.20404) |
| Hooks that enforce checks | Vendor docs only | A prompt rule "works most of the time, not every time". A `Stop` hook that exits 2 keeps the agent working until the check passes (capped at eight consecutive blocks). No controlled study. | [Claude Code best practices](https://code.claude.com/docs/en/best-practices) |
| Docs retrieval for new APIs | RustEvo^2 | +13.5% success on post-cutoff APIs. | [RustEvo^2](https://arxiv.org/abs/2503.16922) |
| Small diffs | 2,500 reviews, 3.2M lines (pre-AI) | Review catches most defects at 200 to 400 lines and 300 to 500 lines per hour. Detection falls beyond that. No AI-specific measurement found. | [SmartBear/Cisco via Ruzora](https://www.ruzora.com/blog/the-right-size-for-a-code-review) |
| Spec-first work | Practitioner paper | Defines spec-first, spec-anchored, spec-as-source. No controlled measurement. | [SDD paper](https://arxiv.org/abs/2602.00180) |
| Humans keep their skills | RCT, n=52, Trio library | Quiz 50% (AI) vs 67% (no AI), p=0.01. Delegation and AI debugging scored under 40%. Conceptual questions and code-plus-explanation scored 65% or more. Not an agentic setup. | [Anthropic](https://www.anthropic.com/research/AI-assistance-coding-skills) |
| AI as bug finder | Claude on open-source code | Over 500 high-severity vulnerabilities validated, using fuzzers, debuggers and sanitizers, then triaged by humans. Memory corruption only. No false-positive rate. | [Anthropic](https://www.anthropic.com/research/zero-days) |
| AI bug reports without validation | curl | curl ended its bug bounty in January 2026, citing AI-generated noise. | [Stenberg](https://daniel.haxx.se/blog/2026/01/26/the-end-of-the-curl-bug-bounty/) |

### 2.3 What the evidence says together

- **Why AI finds bugs but also writes them.** The blind-spot result fits the maintainer's observation: a model reads code it did not write as external input, so it spots errors there, but it reads its own output as its own. A fresh context is a cheap approximation of "someone else". Findings that a tool can confirm (a crash, a failing test, a sanitizer hit) are worth acting on. Findings that nothing can confirm are noise until proven (curl).
- **Reviewer choice matters and is asymmetric.** In the one cross-model experiment, a stronger model reviewing a weaker one helped and the reverse hurt. Do not assume a second opinion from a weaker model adds safety. Verify every review finding with a test or a tool.
- **Instructions are cheap and weak; gates are strong.** Prompts and AGENTS.md shape style and save tokens. They did not raise correctness or security in the studies above. Hooks and CI do not depend on the model's compliance.
- **Loops without a verifier get worse.** Iterating on its own output with no external signal can degrade security (+37.6% critical issues). Always attach a tool: compiler, tests, analyzers.

### 2.4 Where the evidence is thin

- **Rust:** no study of vulnerability rates in AI-written Rust. Most data is Python, Java, JS and C/C++.
- **Current models:** SusVibes and the self-correction study use 2025-era models. Veracode says no improvement through 2026. No agent-level security benchmark for current frontier models was found. **unverified**.
- **Hooks, spec-first, small diffs, test-first for agents:** practitioner reports and vendor docs. No controlled effect sizes. The small-diff data predates AI.
- **Cross-model review:** one preprint, 116 competitive-programming tasks, a reviewer that cannot run code, no replication.
- **Mutation testing for AI code:** one industrial report with no defect-reduction number.
- **Vendor reports** (Veracode, CodeRabbit, GitClear) have commercial interest and weaker methods (inferred authorship, undisclosed checkers).

## 3. Rust deterministic tooling

Versions and dates from crates.io on 2026-10-29. Current stable Rust is 1.99.1 (2026-10-16). "Cost" is CPU time and maintainer attention.

### 3.1 Lints, formatting, dependencies

| Tool | What it catches | Cost | Verdict for Phyllon |
|---|---|---|---|
| rustc lints via `[lints]` in `Cargo.toml` | Anything rustc can deny. `forbid` cannot be lowered by an `#[allow]` in code (rustc docs), only by `--cap-lints`, which Cargo uses for non-path dependencies. Cargo applies `[lints]` per package, not to dependencies. Respected since Rust 1.74; the release that added `[workspace.lints]` inheritance is **unverified**. | Free | Use. Forbid `unsafe` in own crates. |
| rustfmt | Formatting drift. Removes noise from diffs. | Seconds | Use, enforced by hook and CI. |
| clippy | Default groups: `correctness` (deny), `suspicious`, `style`, `complexity`, `perf` (warn). Opt-in: `pedantic` (strict, some false positives), `nursery` (unfinished), `cargo` (manifest), `restriction` (project policy; the Clippy README says never enable it as a whole). | Seconds to a minute (compiles) | Use `-D warnings` in CI. Turn on `pedantic` as warn. Pick restriction lints by name (section 3.5). |
| cargo-deny 0.20.2 | Four checks: `advisories` (RustSec), `licenses`, `bans` (duplicates, named crates), `sources` (allowed registries). The RustSec site lists it as an auditor of `Cargo.lock`. | Seconds. Advisories need the DB fetch. | Use. Replaces cargo-audit for this project. |
| cargo-audit 0.22.2 | Same RustSec advisories only. | Seconds | Skip while cargo-deny runs `advisories`. Revisit for scanning built binaries (**unverified**: needs `cargo-auditable` 0.7.7). |
| cargo-vet 0.10.3 | Proves a trusted party audited each dependency version. Imports audits from other organizations. | High: audits or trust decisions per crate | Defer. Revisit when the dependency count is stable. |
| cargo-semver-checks 0.51.0 | Breaking API changes in a library crate. Depends on rustdoc JSON, an unstable format. | Minutes | Skip until Phyllon publishes a library crate to crates.io. |
| cargo-shear 1.14.0 | Unused and misplaced dependencies, unlinked source files. Parses with rust-analyzer's parser. `--deny-warnings` for CI. | Seconds | Use. |
| cargo-machete 0.9.2 | Unused dependencies by regex. Fast but imprecise, false positives. | Seconds | Alternative to shear. |
| cargo-udeps 0.1.61 | Unused dependencies by compiling. Needs nightly. cargo-shear's README says it no longer works with the latest cargo (**unverified**). | Minutes | Skip. |

### 3.2 Testing, coverage, mutation

| Tool | What it catches | Cost | Verdict for Phyllon |
|---|---|---|---|
| cargo-nextest 0.9.150 | Faster runs, process-per-test isolation, flaky-test retries, build archives. Does not run doctests: use `cargo test --doc` too. | Faster than `cargo test` | Use. The archive feature supports the secret-free build job in section 7. |
| proptest 1.12.0 | Invariant violations on random and shrunk inputs (roundtrips, idempotence, bounds). Stable Rust. | Seconds to minutes depending on cases | Use for parsers, ranking, template input, anything with an invariant. |
| cargo-fuzz 0.13.2 | Crashes, panics, hangs in parsers. libFuzzer needs nightly and Linux/macOS on x86-64 or aarch64. | Long runs, corpus to manage | Use for input parsers (uploads, docling output, MCP arguments) on a nightly job. |
| cargo-mutants 27.1.0 | Code changes that no test notices, so tests that run code but check nothing. `--in-diff` limits it to a PR. Semi-actively maintained (README, Aug 2026). | High: rebuilds and reruns per mutant | Use incremental on PRs, full run weekly. |
| cargo-llvm-cov 0.9.1 | Which lines tests reach. Does not show whether tests check anything. | Minutes | Report only. Do not gate on a percentage. Pair with mutants. |
| miri | Undefined behavior in `unsafe` code, data races, leaks, in the executions it runs. Nightly, no networking, limited FFI, cannot prove soundness. | Slow | Skip while own crates forbid `unsafe`. |
| loom 0.7.2 | Concurrency bugs in custom lock-free or sync code by permuting executions. Last crate release 2024-04, repo active 2026-02. | High effort | Skip. Only for hand-written synchronization. |
| sqlx 0.9.0 offline checks | `query!` macros check SQL against the schema at compile time. Commit `.sqlx` from `cargo sqlx prepare`; `cargo sqlx prepare --check` fails when it is stale. A set `DATABASE_URL` overrides `.sqlx`, so set `SQLX_OFFLINE=true`. | Needs a Postgres with the schema to refresh | Use, if Phyllon uses sqlx. Strong guard against AI-invented columns and types. |

### 3.3 Performance and size: finding slow code

For a Postgres-heavy app, look at the database before Rust CPU. Enable `pg_stat_statements` (needs `shared_preload_libraries` and a restart; PostgreSQL 18 docs) and run `EXPLAIN (ANALYZE, BUFFERS)` on slow queries. **unverified** here: pgvector index tuning.

| Tool | What it shows | Cost and limits | Verdict |
|---|---|---|---|
| samply 0.13.1 | Sampling CPU profile opened in the Firefox Profiler: call tree, flame graph, source view, per-thread timeline. Data stays local until you upload. On Linux only on-CPU samples, so time blocked on locks or I/O is invisible. Needs `perf_event_paranoid` lowered. Last crates.io release 2025-02, repo active (2026-10-24). | Low overhead | First choice for CPU hot spots. |
| cargo-flamegraph 0.6.14 | SVG flame graph from `perf` on Linux. With lld (default since Rust 1.90) you need `--no-rosegment`. | Low | Alternative to samply. |
| perf | Kernel-level counters and sampling. | Low-level | Use through the two above. |
| tokio-console 0.1.14 | Live view of async tasks: slow polls, tasks that never wake, stuck tasks. Needs `--cfg tokio_unstable` and a subscriber layer. | Overhead, development only | Use when async stalls are suspected. |
| dhat 0.3.3 | Heap profile (who allocates, peak, short-lived allocations) viewable in the DHAT viewer; can assert heap use in tests. Maintainer warns of slow responses; last release 2024-02. | Slows the program | Use for allocation questions. |
| heaptrack | Linux heap profiler: leaks, allocation hotspots, temporary allocations, flame graph in `heaptrack_gui`. | Overhead | Use for whole-process memory on Linux. |
| cargo-bloat 0.12.1 | Binary size per crate and function. Last release 2024-05. | Seconds | Occasional. |
| criterion 0.8.2 / divan 0.1.21 | Wall-clock micro-benchmarks. Noisy on shared CI runners. | Minutes | Local use. |
| gungraun 0.20.0 (formerly Iai-Callgrind) | Instruction counts and cycle estimates with Valgrind, one run per benchmark, stable in virtualized CI. Can emit flame-style charts. Linux. | Valgrind slowdown | Use for CI regression checks. |
| CodSpeed / Bencher | Benchmark history and PR regression reports. CodSpeed's free plan targets open source (600 macro runner minutes per month). Whether its CPU simulation counts instructions is **unverified**. | Service | Optional. |

### 3.4 Code scanning: CodeQL and Semgrep

- **CodeQL.** Rust support reached general availability on 2025-10-14. It is free for public repositories and runs through default setup. GitHub claims all OWASP Top 10 categories except A06 (outdated components, left to Dependabot). The query-help page lists 21 Rust queries on the check date, 20 of them security queries: database query built from user-controlled sources, path injection, SSRF, XSS, cleartext logging and storage, disabled TLS checks, regex injection, uncontrolled allocation size, weak crypto, log injection. It does not find logic or authorization bugs. CodeQL 2.27.2 (2026-10-09) improved Rust data flow for `async`/`await` and added summaries for `native-tls` crates. CodeQL also scans GitHub Actions workflows as a language. Sources: [GA notice](https://github.blog/changelog/2025-10-14-codeql-scanning-rust-and-c-c-without-builds-is-now-generally-available/), [query help](https://codeql.github.com/codeql-query-help/rust/), [2.27.2](https://github.blog/changelog/2026-10-09-codeql-2-27-2-improves-c-go-rust-and-javascript-analysis/).
- **Semgrep.** The docs list Rust as generally available for Semgrep Code and Supply Chain, with cross-function dataflow and 40+ Pro rules (paid). The community rules repo has one Rust folder, `lang/security`; its rule count is **unverified**. Best use here is writing your own rules that encode recurring agent mistakes (for example, `format!` passed to `sqlx::query`). Source: [supported languages](https://docs.semgrep.dev/supported-languages).
- **Verdict.** Turn on CodeQL default setup (free, no maintenance). Add Semgrep only when you have project-specific patterns worth encoding. Neither replaces tests, because both are pattern and dataflow tools.

### 3.5 Suggested lint baseline

```toml
# Cargo.toml (workspace root)
[workspace.lints.rust]
unsafe_code = "forbid"

[workspace.lints.clippy]
pedantic = { level = "warn", priority = -1 }
unwrap_used = "deny"
expect_used = "warn"
panic = "deny"
todo = "deny"
unimplemented = "deny"
dbg_macro = "deny"
indexing_slicing = "warn"
string_slice = "warn"
print_stdout = "warn"
let_underscore_must_use = "warn"
allow_attributes_without_reason = "deny"
```

All named lints exist in the current Clippy docs; `unwrap_used`, `expect_used`, `panic`, `todo`, `unimplemented`, `dbg_macro`, `indexing_slicing`, `string_slice`, `print_stdout`, `let_underscore_must_use` and `allow_attributes_without_reason` are `restriction`, `await_holding_lock` and `let_underscore_future` are `suspicious` (already warn by default), and `large_futures`, `unused_async` and `cast_possible_truncation` are `pedantic`. `clippy.toml` has `allow-unwrap-in-tests`, `allow-expect-in-tests`, `allow-panic-in-tests` and `allow-indexing-slicing-in-tests`, so tests stay readable. Pin the toolchain in `rust-toolchain.toml`, because new Clippy releases add lints and `-D warnings` then breaks CI on an unrelated change. Dependabot's cooldown docs list a "Rust toolchain" ecosystem, so the pin can be updated by bot.

## 4. Recommended toolchain per stage

| Stage | Where | Tools | What they catch |
|---|---|---|---|
| While editing (seconds) | Agent hook, editor | `PostToolUse` hook after every edit: `cargo fmt`, `cargo check --workspace --all-targets --locked` with `SQLX_OFFLINE=true`. rust-analyzer with clippy on save for the human. | Syntax, type and borrow errors, format drift. Immediate feedback for the model. |
| Before the agent says "done" and before commit (under 3 minutes) | `Stop` hook plus a git pre-commit hook running one script | `cargo fmt --check`; `cargo clippy --workspace --all-targets --locked -- -D warnings`; `cargo nextest run`; `cargo test --doc`; `cargo shear --deny-warnings`; `cargo deny check bans licenses sources`. | Lint violations, failing tests, unused or forbidden dependencies. The `Stop` hook is the only deterministic way to stop an agent finishing early. The git hook covers any tool (Codex hook support is **unverified**). |
| Every pull request (GitHub-hosted, no secrets, 10 to 15 minutes) | GitHub Actions `pull_request` | Everything above, plus: integration tests against a Postgres with pgvector service container; `cargo deny check` including advisories; `cargo sqlx prepare --check`; `cargo doc --no-deps` with warnings denied; zizmor and actionlint on workflow changes; CodeQL (Rust and Actions); dependency review (optional; the dependency graph reads `Cargo.lock`, but dependency-review behavior on Cargo is **unverified**); `cargo llvm-cov` as a report; `cargo mutants --in-diff` (non-blocking at first). | Regressions, SQL drift, known-vulnerable or wrongly licensed crates, workflow injection, weak tests on the changed lines. |
| Nightly or weekly (GitHub-hosted, or homelab for long jobs) | `schedule` | Full `cargo mutants` (sharded); proptest with a higher case count; `cargo fuzz` per target for 10 to 30 minutes with a cached corpus; `cargo deny check advisories` (new advisories appear without a code change); instruction-count benchmarks (gungraun) or CodSpeed; the paid-API battery (section 7); weekly dependency PRs behind a cooldown. | Weak tests, parser crashes, newly disclosed vulnerabilities, performance regressions, prompt and model drift. |
| On release (GitHub-hosted, tag or release PR merge) | Release workflow | Full gate again; build x64 and arm64 binaries on native runners; changelog from Conventional Commits; container with `provenance: mode=max` and `sbom: true`; provenance attestation by digest; `gh attestation verify` as the last step; `cargo-semver-checks` only if a library crate is published. | A tampered or unreproducible artifact, missing SBOM, accidental breaking API change. |

## 5. GitHub Actions hardening and releases

### 5.1 Workflow hardening

| Control | Fact | Source |
|---|---|---|
| zizmor | Static analysis for workflows. Audits include `template-injection`, `dangerous-triggers` (`pull_request_target`, `workflow_run`, `issue_comment`), `unpinned-uses`, `excessive-permissions`, `artipacked` (credentials left on disk), `cache-poisoning`, `known-vulnerable-actions`, `impostor-commit`, `dependabot-cooldown` (recommends 7 days). Some audits only show with the pedantic or auditor persona. | [zizmor audits](https://docs.zizmor.sh/audits/) |
| actionlint | Syntax and type checks for expressions, `with:` inputs, runner labels, cron syntax, shellcheck and pyflakes on `run:`, plus some script-injection and hard-coded-credential checks. Complements zizmor. | [actionlint](https://github.com/rhysd/actionlint) |
| Pin actions by SHA | GitHub recommends pinning to a full-length commit SHA, and an allowed-actions policy can make unpinned actions fail (set at enterprise, organization or repository level). Check the SHA belongs to the action's repository, not a fork. | [Secure use](https://docs.github.com/en/actions/reference/security/secure-use), [policy](https://github.blog/changelog/2025-08-15-github-actions-policy-now-supports-blocking-and-sha-pinning-actions/) |
| Workflow lockfiles | Generally available since 2026-10-28. `gh actions-lock` writes `.github/workflows/actions.lock`, pinning actions and their transitive dependencies to commits while workflows keep readable tags. Dependabot regenerates entries. A "Require lockfile" policy exists. Docs say lockfiles supersede SHA pinning. One day old at the check date, so maturity is **unverified**. | [Changelog](https://github.blog/changelog/2026-10-28-github-actions-workflow-lockfiles-are-generally-available/) |
| Least privilege | Grant the `GITHUB_TOKEN` minimum permissions, raise per job. Personal-account repositories default to read-only `contents` and `packages`. Put `permissions: {}` at the top of each workflow. | [Secure use](https://docs.github.com/en/actions/reference/security/secure-use), [settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository) |
| Untrusted input | Put `${{ }}` values into an environment variable instead of the script body. Avoid `pull_request_target`; never check out fork code in it. | [Secure use](https://docs.github.com/en/actions/reference/security/secure-use) |
| OIDC | Workflows request short-lived tokens, so no long-lived cloud secrets. Issuer `https://token.actions.githubusercontent.com`. Repositories created after 2026-07-15 use a newer immutable `sub` format with owner and repository IDs: copy the exact `sub` from a real token before writing trust rules for a new repository. Phyllon needs OIDC for attestations and, if used, crates.io trusted publishing (needs `id-token: write`; the first publish of a new crate cannot use it). | [OIDC](https://docs.github.com/en/actions/concepts/security/openid-connect), [release-plz](https://github.com/release-plz/release-plz/blob/HEAD/website/docs/github/quickstart.md) |
| Fork pull requests | Secrets are not passed (except a read-only `GITHUB_TOKEN`). By default all first-time contributors need approval. Set "Require approval for all external contributors". Review `.github/workflows/` changes before approving. | [Events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows), [approval](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/approve-runs-from-forks) |
| Free security features | Code scanning (CodeQL), secret scanning, push protection and dependency review are available by default on public repositories. Dependabot alerts, security updates and a security policy are free on every plan. | [Docs](https://docs.github.com/en/code-security/getting-started/github-security-features) |
| AI actions in CI | `claude-code-action` runs only for users with write access, blocks bots by default, restores `.claude/` and `CLAUDE.md` from the base branch on PRs, but leaves `package.json`, lockfiles and Makefiles PR-controlled. Avoid `allowed_non_write_users`. `show_full_output` can leak secrets into public logs. | [Security model](https://github.com/anthropics/claude-code-action/blob/main/docs/security.md) |

### 5.2 Dependency updates: Dependabot or Renovate

- **Dependabot** (GitHub-native, ecosystems `cargo`, `github-actions`, `docker`, Rust toolchain). Since 2026-07 it applies a default 3-day cooldown to version updates. Set it explicitly to 7 days (zizmor's recommendation). Security updates skip the cooldown. Source: [options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference), [cooldown post](https://github.blog/security/supply-chain-security/the-case-for-a-cooldown-why-dependabot-now-waits-before-issuing-version-updates/).
- **Renovate** has `minimumReleaseAge`, which works for crates.io (uses the index `pubtime` field). Security updates bypass it. It needs the Mend app or self-hosting. Source: [Renovate docs](https://docs.renovatebot.com/key-concepts/minimum-release-age/).
- **Recommendation:** Dependabot. It needs no hosting, handles Cargo, Actions and the lockfile, and regenerates the Actions lockfile entry. Choose Renovate only if you need grouped regex managers or want one tool on Forgejo and GitHub.
- A cooldown would have kept the August 2026 poisoned releases out for their 86 to 107 minute lifetime. That is a design argument, not a measurement.

### 5.3 Release tooling

| Tool | What it does | Fit |
|---|---|---|
| release-plz 0.4.2 (crates.io 2026-10-27) | Opens a release PR from Conventional Commits, bumps versions, writes the changelog with git-cliff, runs cargo-semver-checks, tags, creates GitHub/Gitea/GitLab releases, optionally publishes. With `git_only = true` it reads versions from git tags, not the registry, for packages that are not on crates.io. `publish = true` together with `git_only = true` is an error. | Best fit for a human-approved release: merging the release PR is the approval. |
| dist (formerly cargo-dist) 0.32.0 | `dist init` generates a GitHub release workflow (plan, build, publish, announce) that builds per-platform binaries and installers and uploads them to a GitHub Release. `github-attestations = true` adds artifact attestations (dist's docs still call GitHub's feature "public beta": stale or **unverified**). Verification is `gh attestation verify` only. | Good for binary artifacts. |
| release-please (googleapis) | Release PR plus tags plus GitHub release from Conventional Commits. Rust workspaces need manifest mode and the `cargo-workspace` plugin. Does not publish. | Equivalent to release-plz with more setup for Rust. |
| git-cliff 2.14.2 | Changelog generator only. | Already inside release-plz. |
| cargo-release 1.1.7 | Local CLI for version bump, tag, publish. dist uses it for its own releases. | Fallback, no PR flow. |

Recommendation: release-plz with `git_only = true` for the release PR, tag and changelog, and dist (or a short custom workflow) for the binaries. One trap: events created with the repository `GITHUB_TOKEN` do not start new workflow runs (only `workflow_dispatch` and `repository_dispatch` do). A tag pushed by release-plz with that token will not trigger the dist workflow, so give release-plz a fine-grained token or GitHub App token, or have it call the build workflow by `workflow_dispatch`. This combination was not tested here (**unverified**). Sources: [release-plz config](https://github.com/release-plz/release-plz/blob/HEAD/website/docs/config.md), [dist](https://github.com/axodotdev/cargo-dist), [release-please](https://github.com/googleapis/release-please), [GitHub trigger rules](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

### 5.4 Container images on GHCR: signatures, SBOM, provenance

- Build with `docker/build-push-action` and `push: true` (attestations need a registry push). Set `sbom: true` and `provenance: mode=max`. In public repositories `mode=max` is added by default, and it records build-arg values, so never pass secrets as build args; use secret mounts. [Docker docs](https://docs.docker.com/build/ci/github-actions/attestations/)
- Attest by digest with `actions/attest@v4`: `subject-name: ghcr.io/OWNER/IMAGE` (no tag), `subject-digest` from the build step output, `push-to-registry: true`. Permissions: `id-token: write`, `contents: read`, `attestations: write`, `packages: write`. Verify with `gh attestation verify oci://ghcr.io/OWNER/IMAGE:TAG -R OWNER/REPO`. [GitHub docs](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations)
- Level: artifact attestations give SLSA v1.0 Build Level 2; a shared reusable workflow can reach Level 3. Public repositories use the Sigstore public-good instance and a public transparency log. Attestations are free for public repositories on all current plans. [GitHub docs](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
- `actions/attest-build-provenance` v4 is a wrapper around `actions/attest`; new work should use `actions/attest`. [Repo](https://github.com/actions/attest-build-provenance)
- Cosign keyless signing is optional. It needs `id-token: write`, binds the signature to the workflow identity (Fulcio certificate, Rekor log), and verifies with `cosign verify IMAGE --certificate-identity=... --certificate-oidc-issuer=...`. For GitHub Actions the issuer is the token issuer above (the Sigstore page itself shows only the interactive GitHub login issuer). Choose cosign only if consumers need a verifier that is not the GitHub CLI. [Sigstore docs](https://docs.sigstore.dev/cosign/verifying/verify/)
- For crate-level SBOMs, `cargo-cyclonedx` (0.5.9) and `cargo-sbom` exist. How well BuildKit's scanner reads Rust binaries is **unverified**; `cargo-auditable` embeds the dependency list in the binary to help (**unverified**).

## 6. Where CI should run

### 6.1 Facts

| Topic | Fact |
|---|---|
| GitHub-hosted, public repo | "Use of the standard GitHub-hosted runners is free and unlimited on public repositories." Labels include `ubuntu-latest`, `ubuntu-24.04`, `ubuntu-26.04` (x64) and `ubuntu-24.04-arm`, `ubuntu-26.04-arm` (arm64): 4 vCPU, 16 GB RAM, 14 GB SSD each. Private repositories get 2 vCPU and 8 GB. [Runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) |
| Not free | Larger runners are billed even in public repositories. |
| Limits | Free plan: 20 concurrent jobs. 6 hours per job. 35 days per workflow run. 1,000 `GITHUB_TOKEN` API requests per hour per repository. [Limits](https://docs.github.com/en/actions/reference/limits) |
| Price changes | GitHub announced a $0.002 per minute platform charge for self-hosted runners for 2026-03-01 and postponed it; it is not in effect as of August 2026 (secondary). Public repositories are not charged either way. [GitHub](https://github.com/resources/insights/2026-pricing-changes-for-github-actions) |
| Self-hosted runners, public repo | "Self-hosted runners should almost never be used for public repositories": anyone who can fork and open a PR can run code on them. They lack clean-VM guarantees. Just-in-time runners run at most one job. Environment secrets protected by required reviewers "are still susceptible to the same risks" on self-hosted runners. [Secure use](https://docs.github.com/en/actions/reference/security/secure-use) |
| Runner groups | Available to organizations and enterprises (docs: enterprise accounts and organizations on Team or Free). A personal-account repository such as `nemesis398/phyllon` can add repository-level runners but, by this reading, no runner groups (**unverified**: not tested on a personal account). Public repositories cannot use group runners by default. [Manage access](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/manage-access) |
| Environments | On Free, public repositories get required reviewers (up to 6), prevent-self-review, wait timers, deployment branch and tag restrictions, and environment secrets. Environment secrets are unavailable to a job until a reviewer approves it. [Docs](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments) |
| Schedules | Default branch only. Minimum 5 minutes, often delayed at the top of the hour. In public repositories a schedule is disabled after 60 days without repository activity. `workflow_dispatch` needs the workflow file on the default branch and can then target any branch. [Events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) |
| Cache | 10 GB per repository by default (usage above is billed), entries unused for 7 days are evicted. A run restores from its branch, the default branch, and for PRs the base branch. PR caches are scoped to the merge ref. Low-trust triggers (`pull_request_target`, `issue_comment`, `workflow_run`) get read-only access to the default-branch cache. [Caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) |
| Rust cache action | `Swatinem/rust-cache` caches `~/.cargo` and `target` for dependencies, not workspace crates; sets `CARGO_INCREMENTAL=0`; use `save-if` to write only from the default branch; pin the nightly if you use one, because an unpinned nightly resets the cache daily. [Repo](https://github.com/Swatinem/rust-cache) |
| Forgejo Actions | Supports `push`, `pull_request`, `schedule`, `workflow_dispatch`; workflows live in `.forgejo/workflows`. Fork PRs get no secrets. Scheduled workflows run from the default branch only. Not identical to GitHub Actions ("familiarity instead of compatibility"): the default runner image is a slim Debian with Node.js, OIDC uses `enable-openid-connect`, some `permissions` keys are ignored. How Actions behave on mirrored repositories is **unverified**. [Differences](https://forgejo.org/docs/latest/user/actions/github-actions/), [reference](https://forgejo.org/docs/latest/user/actions/reference/) |

### 6.2 Placement recommendation

| Job | Where | Trigger | Secrets |
|---|---|---|---|
| fmt, clippy, tests, deny, shear, sqlx check, doc build, zizmor, actionlint | GitHub-hosted `ubuntu-latest` | `pull_request`, `push` to `main` | None |
| CodeQL | GitHub default setup | PR, push, weekly | None |
| `cargo mutants --in-diff` | GitHub-hosted | PR label or nightly on `main` | None |
| Fuzz, long proptest, full mutants | GitHub-hosted (6-hour job limit is enough); homelab if you want runs longer than that or a persistent corpus | `schedule` | None |
| Benchmarks | Instruction counts (gungraun) on GitHub-hosted; wall-clock on quiet homelab hardware (inference: shared runners are noisy) | `schedule`, `workflow_dispatch` | None |
| Release build, container, attestation | GitHub-hosted (attestations and OIDC are GitHub-native; arm64 runners are free for public repos, so no cross-compiling) | Tag or release PR merge | `GITHUB_TOKEN` only |
| Paid-API battery (MiniMax, Haiku) | GitHub-hosted. It only makes HTTPS calls and needs no GPU. | `schedule` and `workflow_dispatch` only, never `pull_request` | Environment secrets (section 7) |
| GPU and local-model jobs | Homelab Forgejo runner | Forgejo `schedule` or `workflow_dispatch` | Homelab-local only |
| docling-serve integration tests | Mock with recorded fixtures on GitHub-hosted. A real docling container may be large: check against the 14 GB runner disk (image size **unverified**). Real-container runs go to the homelab. | PR (mocks), nightly (real) | None |

Why the homelab stays out of public pull requests: a homelab runner on the home network reachable from GitHub is the exact case GitHub warns about, and a personal account has no runner groups to fence it. Let the homelab pull instead: a private Forgejo repo with a `schedule` workflow that runs `git clone https://github.com/nemesis398/phyllon` (public, no credentials), runs the GPU suite against the default branch, and reports through a channel you already use (ntfy, a Forgejo issue, or a GitHub issue created with a fine-grained token). A pull mirror may also work, but whether Actions fire on mirror syncs is **unverified**.

Cache plan: `rust-cache` with `save-if: ${{ github.ref == 'refs/heads/main' }}` so PRs only read. Expect the 10 GB cap to matter once Typst, embeddings and rmcp are in the tree: check cache size after the first month.

## 7. The paid-API battery without exposing money

1. **Trigger only on `schedule` and `workflow_dispatch`.** Nothing on `pull_request`, `pull_request_target`, `issue_comment` or `workflow_run`. Fork PRs get no secrets anyway; this also protects against a same-repo branch written by an agent.
2. **Two environments.** `llm-battery-scheduled`: deployment branches limited to `main`, no reviewer (a reviewer would leave the nightly job waiting). `llm-battery-manual`: any branch, one required reviewer (you), "prevent self-review" off since you are the only maintainer. Approve a manual run only after you read the diff of the code under test and `.github/`. Secrets live only in these environments, never at repository level.
3. **Separate compile from run.** Compile runs `build.rs` and proc macros, which executed malware in August 2026. Job A (no environment, no secrets): `cargo nextest archive --archive-file battery.tar.zst`, upload as artifact. Job B (`environment: llm-battery-*`): download, check out the same revision, `cargo nextest run --archive-file battery.tar.zst`. Nextest archives need the same source revision and nextest on the target; Cargo is not required there. Job B never compiles.
4. **Cap the damage.** Use dedicated keys. Anthropic: Claude Console organizations can set organization and workspace spend limits (API reference dated 2026-10-21). MiniMax spend controls: **unverified**. Set `timeout-minutes`, a `concurrency` group with `cancel-in-progress: false`, and a hard per-run request budget in the test harness.
5. **Keep tests offline by default.** `cargo test` and `cargo nextest run` must never touch the network. Battery tests sit behind a Cargo feature or `#[ignore]` and read keys only from the environment. Everything else uses recorded fixtures.
6. **Do not print.** Never enable debug logging of requests in the battery job (public repo, public logs). If `claude-code-action` is used anywhere, leave `show_full_output` off.
7. **Reactivate schedules.** GitHub disables schedules in public repositories after 60 days without repository activity. A quiet project will lose its nightly battery. Add a monthly `workflow_dispatch` reminder or accept the pause.

## 8. Rules for AI agents in this repo

Put these in `AGENTS.md` (Codex) and `CLAUDE.md` (Claude Code) as a short list. Rules 1 and 3 must also be enforced by hooks and CI, because the ETH study found instruction files do not raise correctness and Anthropic's docs say a prompt rule "works most of the time, not every time".

1. **Run the full gate before you say done, and show the output.** `scripts/check.sh` (fmt, clippy `-D warnings`, nextest, doctests, shear, deny). A `Stop` hook runs it too. *Reason:* models do not reliably find their own errors (64.5% blind spot); compiler and test feedback does fix them (RustAssistant about 74%).
2. **Write the failing test first, run it, watch it fail, then implement.** *Reason:* tests as input raise success; a test that never failed may not exercise your code; the verifier defines what the agent solves (Carlini).
3. **Never weaken a gate to get green.** No `#[allow]` without a written reason, no `#[ignore]`d or deleted tests, no loosened `deny.toml`, lint config, CI or hooks without the maintainer's explicit approval in the PR description. *Reason:* a verifier that can be edited by the agent stops being a verifier.
4. **No `unsafe`, `unwrap`, `expect`, `panic!`, `todo!` or unchecked indexing in non-test code.** Return typed errors. *Reason:* AI PRs had 1.75x more logic errors; a panic on request input is a denial-of-service bug; `unsafe` removes the Rust guarantee that Google measured at 1000x.
5. **SQL only through `sqlx::query!` and bind parameters.** Never build SQL with `format!`. Commit `.sqlx` and keep `cargo sqlx prepare --check` green. *Reason:* injection and XSS are the most common failures in the security benchmarks; compile-time checks catch invented columns.
6. **Treat every external input as hostile and validate at the boundary:** HTTP bodies, MCP tool arguments, uploaded files, docling output, URLs fetched on a user's behalf (SSRF), file paths, and model output. Add a size limit and a proptest or fuzz target for each new parser. *Reason:* BaxBench found about half of the correct programs exploitable; XSS defenses failed in 86% of relevant samples.
7. **Do not add or bump a dependency without justification in the PR:** name, purpose, license, maintainer, last release, and proof it exists on crates.io. No git or path dependencies. Commit `Cargo.lock`; use `--locked`. *Reason:* models invent packages (5.2% to 21.7%), and a poisoned crate runs code at build time (August 2026).
8. **Read the docs for the pinned version before using a crate API** (docs.rs or the source in `~/.cargo/registry`), especially `rmcp`, `sqlx` and `axum`. Do not write from memory. *Reason:* success fell from 56.1% to 32.5% on APIs newer than the model; reading docs recovered 13.5%.
9. **Keep diffs small:** one concern per PR, about 400 changed lines at most excluding `Cargo.lock`, generated files and snapshots. Split larger work. *Reason:* review quality drops beyond 200 to 400 lines (pre-AI data), and the maintainer is the only reviewer. Thin evidence, low cost.
10. **Plan before code for anything beyond a small fix.** Write a short spec in the PR or `docs/`: behavior, edge cases, non-goals, the list of tests, and the sources consulted with URLs. Wait for approval on design-level choices (schema, public API, auth). *Reason:* design and security judgment came from humans in the Cloudflare and Carlini cases. Evidence for spec-first is practitioner-level only.
11. **Cover edge cases on purpose:** empty, maximum size, Unicode, negative, duplicate, concurrent, and malformed input. Use proptest for invariants (roundtrip, idempotence, ordering). Run `cargo mutants --in-diff` on your change and kill survivors by strengthening tests, never by deleting code. *Reason:* coverage shows lines reached, not lines checked; property tests and mutation testing find tests that check nothing.
12. **Ask for a separate review, and verify what it says.** Start a fresh session, ideally a different model family, give it the diff and spec but not your reasoning, and a security checklist (authorization on every endpoint and tool, injection, SSRF, path traversal, secrets in logs, prompt injection into MCP tools, unbounded input). Turn each finding into a failing test before acting. *Reason:* same-model self-review gave 0 to +12.9 points, cross-model review helped or hurt by direction, 60% of closed PRs reviewed only by agents had signal ratios under 30%. "Write secure code" in the prompt measured no effect.
13. **Measure before optimizing.** Attach a profile (samply, flamegraph, `EXPLAIN (ANALYZE, BUFFERS)`) or a benchmark delta to every performance change. Check the database before Rust CPU. *Reason:* AI PRs showed about 8x more excessive I/O (CodeRabbit), and optimization without a measurement adds complexity for no proven gain.
14. **Keep money and secrets out of tests and code.** `cargo test` never touches the network. Paid-API tests live behind a feature flag or `#[ignore]`, read keys from the environment only in the protected CI environment, and use recorded fixtures elsewhere. Never log keys or full request bodies. Never edit workflows to add secret access. *Reason:* untrusted pull requests must not spend money; build scripts run before any test.
15. **Report honestly and explain.** End each PR description with what you ran, what you did not run, and what you are unsure of; mark claims you did not verify. Explain any non-obvious design choice in two or three sentences, as if to a learner. *Reason:* assistant users were more confident and less secure (Perry); developers who asked for explanations kept their comprehension while delegators lost it (Anthropic RCT); the maintainer must be able to review what ships.

## 9. Open points and unverified items

- No AI-specific Rust vulnerability study; applicability of Python, Java and JS figures is **unverified**.
- Security behavior of current frontier models on agentic benchmarks is **unverified** (SusVibes used Claude 4 Sonnet).
- Dependabot's 3-day default cooldown: the post is dated 2026-07-23, an effective date was not stated.
- GitHub workflow lockfiles went GA one day before this check. Wait for a month of use before relying on them over SHA pins plus Dependabot.
- Whether release-plz-created tags can start a dist workflow with a non-default token was not tested.
- Whether Forgejo Actions fire on pull-mirror syncs, MiniMax spend limits, `cargo-auditable` plus scanner support, docling-serve image size, and the license compatibility of each dependency with AGPL-3.0 (let `cargo-deny licenses` enforce an allowlist you chose with care) were not checked.
- Hook support in Codex CLI was not checked. Use a git pre-commit hook and CI as the tool-neutral fallback.
