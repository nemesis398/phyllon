# 0006: Releases built by our own reusable workflow, not dist

Date: 2026-10-30

Status: accepted

## Context

The design's release flow runs in one workflow on every push to `main`.
release-plz tags a new version and creates a draft release. The later jobs
attach the binaries, the image, the SBOMs and the attestations, a verify job
checks them, and only then does the last job publish. The draft is needed
because Phyllon's releases are immutable, and an immutable release takes no new
assets once published. Everything that builds or signs runs in a reusable
workflow, `build.yml`, so the attestations name it as their signer (SLSA Build
Level 3). Every job starts with Harden-Runner in block mode. The design left one
question open: does axo's dist fit this flow with its generated workflow intact,
or does a short build job of our own do the work?

Task 19 answered it in a throwaway public repository,
`nemesis398/phyllon-release-spike`, with immutable releases on. It used a crate
that builds static binaries for `x86_64-unknown-linux-musl` and
`aarch64-unknown-linux-musl`, and `release-plz.toml` with `git_only = true`,
`git_release_draft = true`, `git_release_type = "pre"` and
`release_always = false`. The versions: release-plz 0.4.0 through
`release-plz/action` v0.5.145, dist 0.33.1, Harden-Runner v2.22.2,
`actions/attest` v4.2.2, and gh 2.103.3 for local checks.

**Our own build job worked from start to finish, twice.**

| Release | Harden-Runner | Run         | Duration    | Result                         |
| ------- | ------------- | ----------- | ----------- | ------------------------------ |
| v0.1.0  | audit         | 41120236386 | 3 min 31 s  | published, immutable, 4 assets |
| v0.1.1  | block         | 41122718480 | 3 min 6 s   | published, immutable, 4 assets |
| v0.2.0  | audit (dist)  | 41123819243 | hung 49 min | canceled, still a draft        |

- **The signer is `build.yml`.** Each binary and SBOM passed this check, in CI
  and again locally on the published files:

  ```sh
  gh attestation verify "$file" --repo nemesis398/phyllon-release-spike \
    --signer-workflow nemesis398/phyllon-release-spike/.github/workflows/build.yml \
    --deny-self-hosted-runners
  ```

  The certificate's `buildSignerURI` is `build.yml@refs/heads/main`, its
  `buildConfigURI` is the calling `release.yml`, and its `sourceRepositoryRef`
  is `refs/heads/main`. The same check with `--signer-workflow` naming
  `release.yml` failed on every file.

- **The verify job needs `contents: write`.** A job with `contents: read` got
  `release not found` for the draft, because a read-only `GITHUB_TOKEN` cannot
  see drafts. The verify job downloads the draft's assets, so it verifies
  exactly the bytes that are about to be published.
- **`release_always = false` behaved as the design assumes.** Two ordinary
  merges (the spike's pull requests 3 and 5) and three direct pushes released
  nothing, and release-plz logged "skipping release: current commit is not from
  a release PR". Each squash merge of a `release-plz-v*` branch released its
  version. release-plz finds the pull request through
  `GET /repos/{repo}/commits/{sha}/pulls` and matches the head branch prefix
  `release-plz-`. It creates the tag through the API, so checkout keeps
  `persist-credentials: false`.
- **Block mode blocks.** A probe job with the same allowlist (run 41131114284)
  reached `github.com`, and its curl to `example.com` failed with "Couldn't
  connect to server". The agent logged `domain not allowed: example.com.`.

**dist did not fit**, for five reasons:

1. **Its generated workflow cannot be called.** dist generates triggers only for
   a tag push, a pull request or a `workflow_dispatch`, and has no setting for
   `workflow_call`. A tag that release-plz pushes with `GITHUB_TOKEN` starts no
   workflow. Running dist as a reusable workflow took two hand edits to its
   `release.yml`: the trigger became `workflow_call` with the input `tag`, and
   Harden-Runner went first in each of its five jobs. dist's
   `github-build-setup` only adds steps before `dist build`. With
   `dispatch-releases = true`, every generated expression reads `inputs.tag`, so
   the edited file runs unchanged otherwise. The caller had to move to another
   file, because dist always writes `release.yml`.
2. **dist rejects an edited file unless it stops managing it.** On the edited
   file, `dist plan` and `dist generate --check` exit 255. They pass only with
   `allow-dirty = ["ci"]`, and with that setting `dist generate` no longer
   writes the file at all. From then on the file is ours, and every dist upgrade
   means merging its changes by hand.
3. **The generated file fails our workflow checks.** zizmor 1.31.1 reports 14
   findings on the untouched file: high `excessive-permissions` (top-level
   `contents: write`) and `template-injection` (`${{ }}` inside `run:`), two
   `unpinned-images`, `secrets-inherit`, and further template injections.
   actionlint 1.7.12 reports 4 shellcheck findings. Phyllon's `workflows.yml`
   fails on any of them. The `github-action-commits` setting pins the `uses:`
   actions by SHA, but without the `# vX.Y.Z` comment.
4. **It installs itself unpinned.** The plan and build jobs run:

   ```sh
   curl --proto '=https' --tlsv1.2 -LsSf https://github.com/axodotdev/cargo-dist/releases/download/v0.33.1/cargo-dist-installer.sh | sh
   ```

   The URL names a version, but nothing checks a digest or an attestation of the
   script or of the binary it fetches. No setting changes it, and
   `taiki-e/install-action` has no manifest for dist. Its build jobs also
   install `musl-tools` with `apt-get` from the Ubuntu mirrors over plain HTTP.

5. **It can publish without verification.** With `create-release = false` and
   the default `github-release`, dist's host job uploads and undrafts before any
   custom job runs. With `github-release = "announce"` and a custom publish job
   `./verify`, verify runs first. But the announce job's condition accepts a
   skipped verify as a pass:

   ```text
   if: ${{ always() && needs.host.result == 'success' && (needs.custom-verify.result == 'skipped' || needs.custom-verify.result == 'success') }}
   ```

   Canceling the rerun of run 41123819243 skipped verify, and announce started
   anyway. Its upload-and-undraft step failed only because of the cancel. verify
   is also skipped by its own `if:` for a version with a pre-release suffix,
   such as `0.2.0-rc.1`, when `publish-prereleases` is false.

dist did get the Level 3 signer: its build attestations named its called
`release.yml`, not the caller, and the caller was rejected as signer. The v0.2.0
run hung, though. In `build-global-artifacts`, checkout failed and the Post
Harden-Runner step then stayed in progress for about 45 minutes. GitHub never
stored that job's log (404 BlobNotFound), so the cause is unknown, and the draft
was never published.

## Options

1. **dist with its generated workflow intact**, started by tag push or dispatch.
   The tag push never fires with `GITHUB_TOKEN`. A dispatched run is a separate
   top-level run, not the reusable workflow the design requires, and the
   generated file still fails zizmor and still installs dist unpinned.
2. **dist with a hand-edited workflow called from `release.yml`**, as the spike
   ran it, with `allow-dirty = ["ci"]`.
3. **Our own reusable `build.yml`**: a matrix of native runners builds and
   attests the binaries, and the caller attaches them to the draft, verifies
   them against `build.yml` and publishes.

| Dial         | dist, intact                                                           | dist, hand-edited                                                         | Own `build.yml`                                                |
| ------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Granularity  | One generated file for plan, build, host and announce                  | The same, with our edits woven into it                                    | One job per concern: build, attach, verify, publish            |
| Redundancy   | Installers, checksums and a manifest we do not ship                    | The same                                                                  | Only the files we ship                                         |
| Coupling     | Needs a trigger that `GITHUB_TOKEN` cannot fire, and no Level 3        | Every dist upgrade means merging generated changes into our edits by hand | Ties us to the actions we pin, each vetted                     |
| Retention    | dist keeps its own manifest and its own copy of the workflow           | `allow-dirty` keeps our edited copy, and dist stops updating it           | Nothing kept beside the workflow                               |
| Flow control | dist decides when to publish, and announce runs after a skipped verify | The same `always()` condition decides                                     | Our `needs:` chain decides, and publish needs a passing verify |

## Decision

Use option 3. Task 20 writes `build.yml` and `release.yml` as follows:

- **`build.yml`** (`on: workflow_call`) builds the binaries on native runners,
  `ubuntu-24.04` for x86_64 and `ubuntu-24.04-arm` for aarch64, both available
  to public repositories. It checks out the release tag. It builds with
  `cargo auditable build --release --locked --target <musl target>` after
  `rustup target add`, with no cache. It writes each SBOM with `cargo cyclonedx`
  and the flags `--format json`, `--spec-version 1.5`, `--target <target>` and
  `--override-filename sbom`. It attests every file with `actions/attest`, whose
  default is SLSA provenance. The image job also lives in `build.yml`. As long
  as no crate compiles C code, no `musl-tools` is needed: the binaries came out
  `static-pie linked` and carry the `.dep-v0` section.
- **`release.yml`** runs release-plz (`command: release`, `contents: write`,
  `pull-requests: read`), then calls `build.yml`. An attach job uploads to the
  draft with `contents: write`. The verify job, also with `contents: write` plus
  `attestations: read`, downloads the draft's assets and runs
  `gh attestation verify` on each, with `--deny-self-hosted-runners` and
  `--signer-workflow nemesis398/phyllon/.github/workflows/build.yml`. A publish
  job, which needs verify, runs `gh release edit <tag> --draft=false`. The tag
  comes from release-plz's `releases` output through `jq`, is checked against
  `^v[0-9]+\.[0-9]+\.[0-9]+$`, and reaches `run:` steps only as an environment
  variable.
- **Every job sets `timeout-minutes`.** None of the spike's did, so its hung job
  could have run for the default 6 hours.
- **Harden-Runner `egress-policy: block`** in every job with steps, with these
  `allowed-endpoints`, each on port 443 (measured in audit runs, then proven in
  block mode):

  | Job           | Allowed endpoints                                                                                                                                                                                                                                                                                              |
  | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | release-plz   | `github.com`, `api.github.com`, `release-assets.githubusercontent.com`, `index.crates.io`, `static.crates.io`, `static.rust-lang.org`                                                                                                                                                                          |
  | binary (each) | `github.com`, `api.github.com`, `release-assets.githubusercontent.com`, `static.rust-lang.org`, `index.crates.io`, `static.crates.io`, `fulcio.sigstore.dev`, `rekor.sigstore.dev`, `token.actions.githubusercontent.com`, `results-receiver.actions.githubusercontent.com`, `*.actions.githubusercontent.com` |
  | image (build) | `github.com`, `api.github.com`, `results-receiver.actions.githubusercontent.com`, `registry-1.docker.io`, `auth.docker.io`, `production.cloudfront.docker.com`, `gcr.io`, `dl-cdn.alpinelinux.org`, `index.crates.io`, `static.crates.io`                                                                      |
  | attach        | `api.github.com`, `uploads.github.com`, `results-receiver.actions.githubusercontent.com`                                                                                                                                                                                                                       |
  | verify        | `api.github.com`, `release-assets.githubusercontent.com`, `tmaproduction.blob.core.windows.net`, `tuf-repo-cdn.sigstore.dev`, `tuf-repo.github.com`                                                                                                                                                            |
  | publish       | `api.github.com`                                                                                                                                                                                                                                                                                               |

  `release-assets.githubusercontent.com` serves the tools that release-plz's
  action and `taiki-e/install-action` download, and the draft's assets. The
  wildcard is needed because the Actions service host changes between runs
  (`run-actions-1-azure-eastus`, then `run-actions-3-azure-eastus`).
  Harden-Runner allows `github.com`, `*.github.com`, `*.githubapp.com`,
  `ghcr.io`, `productionresultssa*.blob.core.windows.net` and its own
  StepSecurity endpoints by itself. The block run reached the blob hosts without
  listing them.

- **What the spike did not measure.** The image job built the image only. It did
  not push to GHCR, attest the image or sign with cosign, and verify ran no
  `cosign verify`. Task 20 runs those steps once in audit mode, reads the
  agent's `endpoint called` lines in the Post Harden-Runner log, and adds the
  hosts it finds before switching to block.
- **`release-plz.toml`** takes exactly the four settings above, plus
  `publish = false`. That combination is valid; only `git_only` together with
  `publish = true` is rejected.
- **`scripts/prepare-release.sh`** runs `git fetch --tags` first, because
  without the tags `release-plz update` sees no release and changes nothing. The
  first release starts from a `main` without `CHANGELOG.md`, sets
  `version = "0.1.0"` in `Cargo.toml`, runs `cargo update -w --offline`, then
  `release-plz update --allow-dirty`, which writes the changelog. With a version
  given later, it runs `release-plz update` first and then
  `release-plz set-version <crate>@<version>`, because `set-version` renames the
  newest changelog entry. Alone, it would rename the previous release's entry,
  and it fails on a changelog without one. Only one release branch exists at a
  time, cut from current `main`, because release branches stacked on each other
  conflict in `Cargo.toml`, `Cargo.lock` and `CHANGELOG.md` once the earlier
  ones are squash merged.
- **The reusable-workflow call** keeps `uses: ./.github/workflows/build.yml`
  with `# zizmor: ignore[self-repository]` and a comment that says why: zizmor
  1.31.1 asks for GitHub's newer `$/` form, and actionlint 1.7.12 rejects it.

## Consequences

- Each workflow file is ours, short and reviewed, and passes zizmor and
  actionlint without a generator to keep in sync.
- Publishing depends on a plain `needs:` chain. A failed, skipped or canceled
  verify leaves the release a draft, with its assets attached but nothing
  published, so no immutable release ships unverified.
- We give up dist's installers, checksum files and manifest. Phyllon ships a
  binary, an SBOM and an image, so none of them is missed. If shell or Homebrew
  installers are wanted later, revisit dist with a new record.
- The allowlists are a second list to keep current. A new tool or action in a
  release job takes one audit run and an update to its list, or the job fails
  closed.
- The spike ran on 2026-10-30 during a GitHub Actions and Webhooks incident. The
  repository, created at 18:02:57 UTC, got no push events until Actions was
  turned off and on again. That was an incident artifact, not a finding about
  the flow. Delete the spike repository once the maintainer agrees.
