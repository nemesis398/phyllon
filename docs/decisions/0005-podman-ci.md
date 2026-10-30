# 0005: Podman checks in a Fedora VM on pull requests

Date: 2026-10-30

Status: accepted

## Context

Phyllon promises that its stack runs under rootless Podman with SELinux
enforcing, and Fedora is where that promise breaks first: SELinux denies a bind
mount that is not relabeled. GitHub's hosted runners run Ubuntu, which has no
SELinux, and a container cannot enforce SELinux on itself. The design therefore
boots a Fedora Cloud VM under KVM on the runner and runs the stack inside, as
long as that is fast and reliable enough for pull requests. Its fallback is a
nightly run on the maintainer's own hardware that pulls `main`, while pull
requests keep only the Docker job.

The spike set the bar at 15 minutes or less per run and three green runs. Its
job, in pull request #21 (run 41048047570), booted Fedora 44 Cloud Base Generic,
compose 1.7, on the `ubuntu-24.04` runner image 20261025.353.1, verified the
image's signed checksum, and ran `getenforce` and `podman info` in the VM:

| Attempt | Job  | Image download | SSH answered after |
| ------- | ---- | -------------- | ------------------ |
| 1       | 40 s | 3.1 s          | 18.6 s             |
| 2       | 51 s | 4.5 s          | 18.5 s             |
| 3       | 49 s | 10.0 s         | 12.8 s             |

All three printed `Enforcing`. On the maintainer's laptop, the same script took
29.8 s with the download and 13.9 s with the image cached.

## Options

1. **The VM job on pull requests**: `podman.yml` runs on every pull request that
   touches the stack, and nightly on GitHub's runners.
2. **A nightly run on the maintainer's hardware** that pulls `main`, with pull
   requests checked under Docker only.
3. **No SELinux check in CI**: Docker in CI, Podman by hand before a release.

| Dial         | VM job on pull requests                                    | Nightly on the maintainer's hardware                             | No SELinux check in CI                            |
| ------------ | ---------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------- |
| Granularity  | A failure names the pull request that caused it            | A failure names a night, and every change merged since           | A failure surfaces when someone happens to try it |
| Redundancy   | One workflow for pull requests and nights                  | A second setup beside CI, with its own runner and schedule       | Not at stake                                      |
| Coupling     | Needs `/dev/kvm` on hosted runners and Fedora's mirrors    | Needs the maintainer's machine to be on, online and kept current | Ties the check to the maintainer's memory         |
| Retention    | Nothing kept between runs: each run downloads and verifies | The machine keeps a checkout and an image cache it must refresh  | Not at stake                                      |
| Flow control | GitHub starts it, and its result sits on the pull request  | A timer on the machine starts it, and someone must read its log  | A person starts it                                |

## Decision

Use option 1. `podman.yml` runs on each pull request that touches the stack and
every night, boots the Fedora VM with `scripts/ci/fedora-vm.sh`, and runs
`scripts/stack-test.sh podman` and `scripts/quadlet-test.sh` in it. Build no
nightly fallback on the maintainer's hardware. The job stays a non-required
check.

## Consequences

- A pull request that breaks the stack under SELinux shows it on the pull
  request, before review, instead of on a user's host.
- Each such pull request spends one more runner job. The VM's part was under a
  minute in the spike, so the image build and the stack's own start dominate the
  job.
- The checks need root in the VM only for setup, which cloud-init does at boot:
  it installs Fedora's `docker-compose`, which `podman compose` runs, and `jq`,
  and turns on linger for the VM user, who has no sudo. On the laptop this
  raised the time until the VM is ready from 12.6 s to between 24.7 s and 37.0 s
  over five boots, because dnf fetches the repository metadata first.
- The job depends on GitHub keeping `/dev/kvm` on its hosted runners and on
  Fedora's mirrors. If a run goes past 15 minutes, or the job turns flaky, write
  a new record and revisit option 2.
- Moving to a new Fedora release changes the image, the key and the timings, so
  that move measures again and says so in its pull request.
