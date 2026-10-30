# 0004: Caddy as the bundled proxy

Date: 2026-10-29

Status: accepted

## Context

The compose stack needs a proxy in front of Phyllon, to publish the two ports
and to get a certificate. The
[phase 1 design](../specs/2026-10-29-phase-1-foundations-design.md) names Caddy
and says that a deployer who already runs a proxy can leave it out. A
contributor who knows Traefik may ask why the stack does not use it, since some
hosts run it, for example under Coolify.

The maintainer compared the two on 2026-10-29, Caddy 2.11.7 against Traefik
3.7.16. The images are 24.9 MB against 55.4 MB, and GitHub lists 18 against 64
advisories in twelve months, most of them in features Phyllon does not use. This
record keeps those numbers as the maintainer reported them. How the advisories
were counted and which image tags were measured is not written down in this
repository.

The deciding point is not in the numbers. Traefik finds containers by their
labels, and that discovery needs the container socket. Item 13 of the security
baseline in [the standards research](../research/standards-security.md),
"Container posture", forbids a container-socket mount. The design says the same:
Caddy stays the default because the stack has one fixed upstream, and Traefik's
strength would need the socket that baseline item 13 forbids.

## Options

1. **Caddy**, in a compose profile that the default `.env` turns on.
2. **Traefik**, bundled the same way.
3. **No bundled proxy**: the deployer always brings one.

| Dial         | Caddy                                                       | Traefik                                                           | No bundled proxy                                          |
| ------------ | ----------------------------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------- |
| Granularity  | One container with one fixed upstream in `deploy/Caddyfile` | Each service could declare its own route with labels              | No unit of ours                                           |
| Redundancy   | One file serves `localhost` and a public name               | Not compared                                                      | Each deployer writes TLS and routing again                |
| Coupling     | None to the host's container engine                         | Label discovery needs the container socket, which item 13 forbids | Couples the quickstart to whatever proxy the deployer has |
| Retention    | Not at stake                                                | Not at stake                                                      | Not at stake                                              |
| Flow control | The Caddyfile names the upstream, and Caddy forwards to it  | Traefik watches the socket and decides routes from what it finds  | The deployer's proxy decides                              |

## Decision

Use option 1. The compose stack bundles Caddy, pinned by digest, in the `proxy`
profile, and the default `.env` turns that profile on. Do not mount the
container socket into any service.

A deployer who already runs a proxy leaves Caddy out by removing `proxy` from
`COMPOSE_PROFILES`. The install guide shows how to attach Phyllon to Traefik
through `deploy/examples/compose.traefik.yaml`, and the Quadlet path leaves the
proxy unit out.

## Consequences

- The default stack passes the container posture check of baseline item 13,
  which asserts that no container mounts the socket.
- Phyllon sets its security headers itself, so they hold behind Caddy and behind
  a deployer's own proxy. See [the module map](../map.md), entry `http`.
- A deployer on Traefik uses the shipped override and its labels on a Traefik
  they run themselves. The socket stays with that Traefik, where its owner
  decides.
- The stack follows Caddy releases: `compose.yaml` pins 2.11.7, and Dependabot
  proposes the next digest.
- Revisit this if baseline item 13 changes, or if the stack grows several
  upstreams that need discovery, for example a second web service behind the
  same proxy.
