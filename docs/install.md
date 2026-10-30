# Install Phyllon

This guide runs Phyllon, its PostgreSQL database and a Caddy proxy on one host.
It has three paths: Docker, Podman, and Podman under systemd with Quadlet. Each
setup command is one that `scripts/stack-test.sh` or `scripts/quadlet-test.sh`
runs in CI, so the guide and the tests cannot drift apart unnoticed.

## What you need

- A Linux host with 2 GB of free memory. The three containers have limits of 512
  MB, 1 GB and 256 MB.
- One container engine:
  - Docker Engine with the Compose plugin, or
  - Podman 5 with a compose provider such as `docker-compose` (on Fedora,
    `sudo dnf install podman docker-compose`), or
  - Podman 5 and systemd, for the Quadlet path.

  CI runs the Podman paths on Fedora 44, and older versions are untested.

- `git` and `openssl`.

CI runs both Podman paths with SELinux enforcing. The compose file and the units
relabel what they mount, so you need no SELinux setting of your own.

The commands below say `docker compose`. With Podman, say `podman compose`
instead and give it the same arguments.

## Quickstart on localhost

This starts the whole stack on your own machine, on ports 8080 and 8443, so it
needs no root even under rootless Podman.

1. Get the code and the settings file.

   ```bash
   git clone https://github.com/nemesis398/phyllon.git
   cd phyllon
   cp .env.example .env
   ```

2. Create the three database passwords. The directory is for you alone. The
   files are mode 0444 because each container runs as its own user and must be
   able to read the files it gets; the directory keeps everyone else out.

   ```bash
   mkdir -m 700 secrets
   for name in db_superuser_password db_owner_password db_runtime_password; do
     (umask 222 && openssl rand -base64 32 >"secrets/$name")
   done
   ```

   To replace a password later, delete its file first: the mode makes it
   read-only for you too. A new password does not change the database of a
   running installation. The roles keep the old one until you change them in
   PostgreSQL.

3. Check that all three files exist and are not empty.

   ```bash
   for name in db_superuser_password db_owner_password db_runtime_password; do
     if [ -f "secrets/$name" ] && [ -s "secrets/$name" ]; then
       echo "ok: $name"
     else
       echo "missing or empty: $name"
     fi
   done
   ```

   Do not skip this. When a file is missing, Compose creates an empty directory
   in its place, and the database setup then fails on a password it cannot read.

4. Build the image. This step is temporary, until the first release is published
   (see [Build the image yourself](#build-the-image-yourself)):

   ```bash
   podman build -t ghcr.io/nemesis398/phyllon:0.1 .
   ```

5. Start the stack and wait until every service is healthy.

   ```bash
   docker compose up -d --wait
   ```

   The first start pulls two images and sets up the database, so allow a minute
   or two.

6. Open <https://localhost:8443>, or check from a shell:

   ```bash
   curl -k https://localhost:8443/readyz
   ```

   `/healthz` answers while Phyllon runs. `/readyz` answers `ok` once Phyllon
   can reach the database, and `503` with `database unavailable` if it cannot.

Your browser warns about the certificate. For `localhost`, Caddy cannot get a
certificate from a public authority, so it signs one with its own internal
authority, and no browser trusts that. Accept the warning, or give `curl` the
`-k` flag as above. A real domain, below, gets a trusted certificate on its own.

To stop the stack and keep its data, run `docker compose down`.

### If the first start fails

PostgreSQL creates Phyllon's two roles only while it sets up an empty data
volume. If that setup fails, the volume already exists on the next start, so
PostgreSQL skips the setup and the roles never appear. Phyllon then runs, but
`/readyz` answers `503`, and `docker compose logs db` shows the error.

Fix the cause, then remove the volume and start again:

```bash
docker compose down -v
docker compose up -d --wait
```

**This deletes the database and everything in it.** On a first start there is
nothing to lose. On an installation that holds data, do not run it.

## Public installation

A public installation serves your own domain on ports 80 and 443 with a
certificate that browsers trust. Caddy requests the certificate from Let's
Encrypt on its own and renews it. Do these before the first start:

1. Point the domain's DNS records at the host, and let ports 80 and 443 through
   your firewall. Caddy needs port 80 to prove it controls the domain and to
   redirect plain HTTP.

2. In `.env`, set the domain and the ports. Without the two port lines, the
   defaults are 80 and 443.

   ```ini
   PHYLLON_DOMAIN=phyllon.example.org
   HTTP_PORT=80
   HTTPS_PORT=443
   ```

3. In `deploy/phyllon.toml`, set the address people reach the site at. This is a
   second edit, in a different file, and the two must agree:

   ```toml
   public_url = "https://phyllon.example.org"
   ```

   Compose mounts that file into the Phyllon container, so you edit the copy in
   the checkout. On a running installation, a change needs
   `docker compose up -d --force-recreate phyllon`, because the container reads
   the file when it is created.

4. Under rootless Podman, allow unprivileged ports from 80. This is the only
   root step in the whole installation, and it comes from rootless containers,
   not from Phyllon: every web service under rootless Podman needs it. Docker
   runs its daemon as root and needs nothing.

   ```bash
   echo 'net.ipv4.ip_unprivileged_port_start=80' |
     sudo tee /etc/sysctl.d/99-unprivileged-ports.conf
   sudo sysctl --system
   ```

Then continue with the password files and `docker compose up -d --wait` from the
quickstart.

The proxy container keeps one Linux capability, `NET_BIND_SERVICE`, because the
`caddy` binary carries it as a file capability and the kernel refuses to start a
binary whose capability is missing. It allows binding a low port inside the
container's own network only. You configure nothing for it.

## Quadlet on Fedora

Quadlet turns unit files into systemd services, so rootless Podman starts the
stack at boot and restarts it on failure, without a compose provider. Run these
steps as your own user, not as root.

1. Get the code, and put the units and the files they mount in place.

   ```bash
   git clone https://github.com/nemesis398/phyllon.git
   cd phyllon
   mkdir -p ~/.config/containers/systemd
   cp deploy/quadlet/* ~/.config/containers/systemd/
   mkdir -m 700 ~/.config/phyllon
   mkdir ~/.config/phyllon/postgres
   cp deploy/phyllon.toml deploy/Caddyfile ~/.config/phyllon/
   cp deploy/postgres/10-roles.sh ~/.config/phyllon/postgres/
   ```

2. Create the three passwords as Podman secrets. Each password goes in on
   standard input, never as a command-line argument, where any user of the host
   could read it in the process list.

   ```bash
   for name in phyllon-db-superuser-password phyllon-db-owner-password \
     phyllon-db-runtime-password; do
     openssl rand -base64 32 | podman secret create "$name" -
   done
   ```

3. Build the image ([Build the image yourself](#build-the-image-yourself)),
   because the first release does not exist yet.

4. Let your services run when you are not logged in, then load the units and
   start the stack. Linger is a systemd setting for your user. Turning it on for
   yourself needs no root: polkit allows `set-self-linger` for every user.

   ```bash
   loginctl enable-linger
   systemctl --user daemon-reload
   systemctl --user start phyllon-proxy.service
   ```

   Starting the proxy starts Phyllon, which starts PostgreSQL, and each waits
   until the one before it is healthy. The first start sets up the database. The
   units carry an `[Install]` section, so they start at boot from now on.

5. Check it, as the quickstart does:

   ```bash
   systemctl --user status phyllon-proxy.service phyllon.service phyllon-db.service
   curl -k https://localhost:8443/readyz
   ```

If `systemctl --user cat phyllon.service` shows no unit, Quadlet skipped its
file and says why only in its own output. Run
`/usr/libexec/podman/quadlet -dryrun -user` to see it.

The unit files publish ports 8080 and 8443 and set `PHYLLON_DOMAIN=localhost`,
so the steps above give you the localhost quickstart. A failed first start
leaves the same trap as under Compose, and the fix is the same, with the
database volume in place of the Compose volume:

```bash
systemctl --user stop phyllon-proxy.service phyllon.service phyllon-db.service
podman volume rm systemd-phyllon-db
systemctl --user start phyllon-proxy.service
```

**This deletes the database and everything in it.** Do it only on a first start.

### Quadlet with a public domain

Edit nothing in the shipped units: put your changes in a drop-in, so an update
of the units does not overwrite them. Quadlet merges every `.conf` file in
`phyllon-proxy.container.d/` into the unit, in alphabetical order.

```bash
mkdir ~/.config/containers/systemd/phyllon-proxy.container.d
```

Write `~/.config/containers/systemd/phyllon-proxy.container.d/10-public.conf`:

```ini
[Container]
Environment=PHYLLON_DOMAIN=phyllon.example.org
Environment=HTTPS_PORT=443
# An empty value drops the two ports of the shipped unit.
PublishPort=
PublishPort=80:8080
PublishPort=443:8443
```

The ports are `host:container`. Caddy listens on 8080 and 8443 inside its
container, so the container side stays and the host side changes. Without the
empty `PublishPort=`, your lines would add to the shipped ones and leave 8080
and 8443 open on the host as well. A later `Environment=` for the same name
replaces the earlier one.

Then set `public_url = "https://phyllon.example.org"` in
`~/.config/phyllon/phyllon.toml`, do the root step (step 4 of the public
installation above), and apply it:

```bash
systemctl --user daemon-reload
systemctl --user restart phyllon.service phyllon-proxy.service
```

## Behind an existing proxy

A host that already runs a proxy, such as Traefik under Coolify, needs no second
one. Phyllon then listens only on a network it shares with your proxy, publishes
no port, and your proxy terminates TLS. Phyllon sets its own security headers,
so they hold behind any proxy.

With Compose and Traefik:

1. In `.env`, set `PHYLLON_DOMAIN` to the domain, and remove `proxy` from the
   profiles so that Caddy stays off:

   ```ini
   COMPOSE_PROFILES=
   ```

2. In `deploy/phyllon.toml`, set `public_url` to the domain, as in the previous
   section.

3. Open `deploy/examples/compose.traefik.yaml` and change the network name
   `proxy` (twice), the entry point and the certificate resolver to the ones
   your Traefik uses. The file adds labels and the external network to `phyllon`
   and removes nothing from `compose.yaml`.

4. Start with both files:

   ```bash
   docker compose -f compose.yaml -f deploy/examples/compose.traefik.yaml up -d --wait
   ```

Another proxy needs the same three facts: the upstream is `phyllon:8080` on the
shared network, it speaks plain HTTP, and the proxy must send the domain as the
`Host` header.

With Quadlet, leave out `phyllon-proxy.container` when you copy the units. A
proxy on the host reaches Phyllon through a port bound to the loopback address
only. Add `~/.config/containers/systemd/phyllon.container.d/10-local.conf`:

```ini
[Container]
PublishPort=127.0.0.1:8080:8080
```

Start `phyllon.service` instead of the proxy. A proxy that runs as a container
joins the network `systemd-phyllon-edge` and reaches Phyllon as `phyllon:8080`.

## Upgrades

The image is named `ghcr.io/nemesis398/phyllon:0.1`. The `0.1` is a release
line, not a version. It follows the patch releases, `0.1.1`, `0.1.2` and so on,
and never moves to `0.2` on its own. Before 1.0, a breaking change or any
database migration raises the minor number, so a patch release never migrates
your database. Moving to `0.2` is a deliberate edit, which you make after
reading its release notes.

Compose:

```bash
docker compose pull
docker compose up -d --wait
```

To move to a new line, change `PHYLLON_IMAGE` in `.env` first.

Quadlet checks the registry with Podman's own updater. The Phyllon unit has
`AutoUpdate=registry`, so this pulls a newer `0.1` image and restarts the unit:

```bash
podman auto-update
```

A systemd timer runs it daily. Turn it on once the image is published:

```bash
systemctl --user enable --now podman-auto-update.timer
```

To move to a new line, change `Image=` in your copy of `phyllon.container`, or
add a drop-in with `Image=`, then run `systemctl --user daemon-reload` and
restart the unit. Caddy and PostgreSQL are pinned by digest in both paths. They
change only when you update the checkout or the units.

## What phase 1 cannot do yet

- **The image is not published.** The name `ghcr.io/nemesis398/phyllon:0.1`
  works only after the first release, `v0.1.0`, which comes in a later task of
  phase 1. Build the image yourself until then (see below). A section on
  verifying a release's signature and attestation joins this guide with that
  release.
- **There is nothing to use.** Phyllon serves a start page, the health routes
  and its assets. It has no sign-in and no learning tasks, and PostgreSQL holds
  no tables yet. Learning tasks come in later phases (see the
  [roadmap](roadmap.md)).

### Build the image yourself

This part is temporary. It goes away when the first release is published.

From the checkout, build the image under the name the stack expects:

```bash
podman build -t ghcr.io/nemesis398/phyllon:0.1 .
```

With Docker, use `docker build` instead. To give the image another name, build
it under that name and set `PHYLLON_IMAGE` in `.env` to it. The Quadlet unit has
no variable: edit `Image=` in your copy, or build under the shipped name. A
local image is used as it is, so nothing is pulled from `ghcr.io`. Do not turn
on the auto-update timer until the image is published, because the registry has
no `0.1` to compare with.
