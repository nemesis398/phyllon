# 0007: Verify the image with cosign, not with Podman's signature policy

Date: 2026-10-31

Status: accepted

## Context

The phase 1 design wants Podman itself to refuse an image that the release
workflow did not sign: a `policy.json` that requires a keyless `sigstoreSigned`
signature from `build.yml` for `ghcr.io/nemesis398/phyllon`, so that
`podman auto-update` on the Quadlet unit cannot pull a swapped image. The plan
made this a spike (Task 21, step 5) with a fallback: verify with cosign before
an update, and drop `AutoUpdate=` from the unit.

The release `v0.1.0` gave the spike a real image. Its signature is the one
`release.yml` checks with `cosign verify` (cosign v3.1.4, certificate identity
`https://github.com/nemesis398/phyllon/.github/workflows/build.yml@refs/heads/main`,
issuer `https://token.actions.githubusercontent.com`). The spike ran rootless
Podman 5.8.9, the version CI tests, inside a throwaway container, with the
policy and the Fulcio and Rekor keys mounted read-only. Nothing of the host's
container configuration was touched.

**Podman refused our own image.** Under a policy that requires our identity for
all of `ghcr.io`, `podman pull ghcr.io/nemesis398/phyllon:0.1` and a pull of an
unrelated image (`ghcr.io/jqlang/jq:latest`) failed with the same message:
`Source image rejected: A signature was required, but no signature exists`. Two
causes stand behind it, and each was shown on its own:

- **Podman does not read the signature where cosign 3 puts it.** With
  `use-sigstore-attachments: true` for `ghcr.io` in `registries.d`, Podman looks
  for a `.sig` tag next to the image. cosign 3 stores a Sigstore bundle
  (`application/vnd.dev.sigstore.bundle.v0.3+json`) as an OCI referrer,
  reachable through the tag `sha256-<digest>`, and the package has no `.sig`
  tag.
- **Podman cannot match a workflow identity.** The `fulcio` requirement in
  `policy.json` has `oidcIssuer` and `subjectEmail`, and the check compares the
  email only against the certificate's email addresses. A GitHub Actions
  identity is a URI in the certificate, so it never matches. A control with
  containers/image's own test fixture, a legacy cosign signature made by
  `mitr@redhat.com`, showed both sides: a policy that required that email passed
  the signed image and refused the unsigned copy, and a policy that required the
  `build.yml` URI as `subjectEmail` refused the signed image with
  `Required email "<the URI>" not found (got ["mitr@redhat.com"])`.

The policy also has no field for the repository, so it could not pin
`nemesis398/phyllon` beside the workflow.

## Options

1. **Podman's signature policy** with a `sigstoreSigned` `fulcio` requirement.
   It does not work, for the two reasons above.
2. **cosign before each update**, run by the person who updates, and no
   `AutoUpdate=` in the unit. The check is `cosign verify` and
   `gh attestation verify` against the digest, then a pull of that digest.
3. **A second, key-based signature** that Podman can check with `keyPath`: sign
   the image again in the legacy `.sig` format with a long-lived private key.
4. **Keep `AutoUpdate=registry` and trust the registry** and the repository's
   write access to its own package.
5. **Sign in the legacy `.sig` format**: cosign can still write it
   (`--new-bundle-format=false`, not run in the spike), which removes the first
   cause. It leaves the second: Podman's `fulcio` requirement still compares
   only email addresses, so the keyless certificate of a workflow, whose
   identity is a URI, never matches. The fixture control above is a legacy
   signature and shows exactly that.

| Dial         | Policy (option 1)                         | cosign before update (2)                                 | Second key (3)                                                  | Trust the registry (4)                           |
| ------------ | ----------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------ |
| Granularity  | Would cover every pull on the host        | One check per update, by hand or script                  | Covers every pull on the host                                   | None                                             |
| Redundancy   | One signature, checked once               | The same signature `release.yml` already checks          | A second signature that says the same as the first              | Not at stake                                     |
| Coupling     | Needs Podman to learn bundles and URI SAN | Needs `cosign` and `gh` on the host, and the updater     | Ties releases to a secret in CI, which keyless signing avoids   | Ties the host to the registry account's security |
| Retention    | Not at stake                              | Not at stake                                             | A private key to guard and rotate; its public key sits on hosts | Not at stake                                     |
| Flow control | Podman would decide, silently, at pull    | The updater decides, and a failed check stops the update | Podman decides, silently, at pull                               | The registry decides what runs                   |

Option 5 has no column: it fails as option 1 does, for the second cause.

## Decision

Use option 2. Remove `AutoUpdate=` from `deploy/quadlet/phyllon.container`.
Update an installation by the version, not by a tag. The install guide's
"Verifying a release" section has a script that takes the target version's
`compose.yaml`, checks its attestation (signer `build.yml`, branch `main`, no
self-hosted runner), reads the image digest from it, runs `cosign verify` and
`gh attestation verify` on that digest, pulls the digest, and points the minor
line the unit names to it. The unit is then restarted by hand. A Compose
installation sets `PHYLLON_IMAGE` to the same digest reference. Do not write a
`policy.json` for Phyllon, and do not turn on `podman-auto-update.timer` for it.

Option 3 is rejected because it adds the long-lived signing key that keyless
signing exists to avoid, for a signature that adds no information.

## Consequences

- An update is a manual step. It no longer happens on a timer, so a host falls
  behind until someone runs the script. The install guide says so.
- The version decides the image. A tag such as `0.1` names whatever the registry
  holds, and any image `build.yml` signed on `main` passes a check by identity:
  an older patch release, an image that was never released, or, under a tag of
  the next line, a release that migrates the database. The digest in the
  attested `compose.yaml` of the version named binds the check to that release.
- The pull uses the verified digest, so a tag that moves between the check and
  the pull cannot swap the image.
- Compose installations never had an updater. They used the repository's
  `compose.yaml` with the tag, and now pin the digest in `.env`. The guide also
  tells an installation from the v0.1.0 era to replace its unit and turn the
  auto-update timer off.
- Revisit this when containers/image reads Sigstore bundles and matches URI
  subjects (its source carries a FIXME for URIs). Then a `policy.json` can
  enforce the check at every pull, and a new record supersedes this one.
