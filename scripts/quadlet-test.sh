#!/usr/bin/env bash
# Installs the Quadlet units from deploy/quadlet/ for the current user, starts
# them under systemd, runs the checks of scripts/stack-test.sh on them and
# removes everything again. Run it with:
#
#   scripts/quadlet-test.sh
#
# It runs only inside the throwaway VM of scripts/ci/fedora-vm.sh, as
# podman.yml does, and never on a workstation: it writes units to
# ~/.config/containers/systemd/ and files to ~/.config/phyllon/, creates Podman
# secrets, and needs linger and a user systemd. It refuses to start outside a
# VM, and when any unit, file, secret, container, volume or network it would
# create already exists, so it never touches an installation. The image
# ghcr.io/nemesis398/phyllon:0.1 must be present; podman.yml loads one built
# from the checkout. Exit 0 means every check passed.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# scripts/posture.sh selects containers by the compose project label, which a
# drop-in below adds to each container for this test only.
project=phyllon-quadlet-test
image=ghcr.io/nemesis398/phyllon:0.1
units_dir="$HOME/.config/containers/systemd"
config_dir="$HOME/.config/phyllon"
# Container unit, then the compose service name posture.sh knows it by.
containers=(phyllon-db:db phyllon:phyllon phyllon-proxy:proxy)
secrets=(phyllon-db-superuser-password phyllon-db-owner-password phyllon-db-runtime-password)
# The names Podman gives the network and volume units' objects.
networks=(systemd-phyllon-edge systemd-phyllon-db)
volumes=(systemd-phyllon-db systemd-phyllon-caddy)

die() {
	printf 'quadlet-test.sh: %s\n' "$@" >&2
	exit 1
}

systemd-detect-virt --vm --quiet ||
	die "this runs only inside a throwaway VM, such as scripts/ci/fedora-vm.sh boots"
podman image exists "$image" || die "the image $image is missing"
mapfile -t units < <(cd "$root/deploy/quadlet" && ls -- *.container *.network *.volume)
for unit in "${units[@]}"; do
	[[ ! -e "$units_dir/$unit" && ! -e "$units_dir/$unit.d" ]] ||
		die "$units_dir/$unit already exists"
done
[[ ! -e "$config_dir" ]] || die "$config_dir already exists"
for name in "${secrets[@]}"; do
	! podman secret exists "$name" || die "the secret $name already exists"
done
for entry in "${containers[@]}"; do
	! podman container exists "${entry%%:*}" || die "the container ${entry%%:*} already exists"
done
for name in "${networks[@]}"; do
	! podman network exists "$name" || die "the network $name already exists"
done
for name in "${volumes[@]}"; do
	! podman volume exists "$name" || die "the volume $name already exists"
done

work="$(mktemp -d -p "${TMPDIR:-/tmp}" phyllon-quadlet-test.XXXXXX)"
# Each directory level mkdir -p creates below, deepest first, so that cleanup
# removes those levels and no others.
made_dirs=()
dir="$units_dir"
while [[ ! -d "$dir" ]]; do
	made_dirs+=("$dir")
	dir="$(dirname -- "$dir")"
done
services=()
for unit in "${units[@]}"; do
	case "$unit" in
	*.container) services+=("${unit%.container}.service") ;;
	*.network) services+=("${unit%.network}-network.service") ;;
	*.volume) services+=("${unit%.volume}-volume.service") ;;
	esac
done
cleanup() {
	local unit dir
	systemctl --user stop "${services[@]}" >/dev/null 2>&1 || true
	for unit in "${units[@]}"; do
		rm -rf -- "${units_dir:?}/$unit" "${units_dir:?}/$unit.d"
	done
	rm -rf -- "$config_dir"
	for dir in ${made_dirs[@]+"${made_dirs[@]}"}; do
		rmdir -- "$dir" 2>/dev/null || break
	done
	systemctl --user daemon-reload || true
	systemctl --user reset-failed "${services[@]}" >/dev/null 2>&1 || true
	podman rm --force --ignore -- "${containers[@]%%:*}" >/dev/null || true
	podman volume rm --force -- "${volumes[@]}" >/dev/null 2>&1 || true
	podman network rm --force -- "${networks[@]}" >/dev/null 2>&1 || true
	podman secret rm -- "${secrets[@]}" >/dev/null 2>&1 || true
	rm -rf -- "$work"
}
trap cleanup EXIT

# The units as shipped, and a drop-in per container with the labels.
mkdir -p -- "$units_dir"
cp -- "${units[@]/#/$root/deploy/quadlet/}" "$units_dir/"
for entry in "${containers[@]}"; do
	mkdir -- "$units_dir/${entry%%:*}.container.d"
	printf '[Container]\nLabel=com.docker.compose.project=%s\nLabel=com.docker.compose.service=%s\n' \
		"$project" "${entry#*:}" >"$units_dir/${entry%%:*}.container.d/50-quadlet-test.conf"
done
# The files the units mount, as the install guide places them.
mkdir -m 700 -- "$config_dir"
mkdir -- "$config_dir/postgres"
cp -- "$root/deploy/phyllon.toml" "$root/deploy/Caddyfile" "$config_dir/"
cp -- "$root/deploy/postgres/10-roles.sh" "$config_dir/postgres/"
# The passwords go to Podman on stdin, never on a command line.
for name in "${secrets[@]}"; do
	openssl rand -base64 32 | podman secret create "$name" - >/dev/null
done

systemctl --user daemon-reload
# Quadlet skips a unit it cannot read and says so only in its own output.
for entry in "${containers[@]}"; do
	systemctl --user cat "${entry%%:*}.service" >/dev/null 2>&1 || {
		/usr/libexec/podman/quadlet -dryrun -user >/dev/null || true
		die "Quadlet generated no ${entry%%:*}.service"
	}
done

# Requires= pulls in Phyllon and PostgreSQL, and Notify=healthy makes each
# start wait until the one before it is healthy.
start=$SECONDS
if ! timeout 600 systemctl --user start phyllon-proxy.service; then
	systemctl --user status --no-pager --lines 0 "${services[@]}" || true
	for entry in "${containers[@]}"; do
		journalctl --user --no-pager --lines 30 --unit "${entry%%:*}.service" || true
	done
	die "the units did not start"
fi
echo "quadlet-test.sh: the units started in $((SECONDS - start)) s"

db_exec() { podman exec -i phyllon-db "$@"; }
# shellcheck source=scripts/stack-checks.sh source-path=SCRIPTDIR/..
source "$root/scripts/stack-checks.sh"

for entry in "${containers[@]}"; do
	name="${entry%%:*}"
	state="$(systemctl --user is-active "$name.service" || true)"
	health="$(podman inspect --format '{{.State.Health.Status}}' "$name" || true)"
	if [[ "$state" == active && "$health" == healthy ]]; then
		pass "$name.service is active and healthy"
	else
		fail "$name.service is $state and its container $health"
	fi
done

# Each container gets only the passwords it needs, each a file only its user
# may read (mode 0400 is 256). Inspect shows what Podman was asked for; the
# stat below shows that it did so, in the one container with a shell.
for entry in "phyllon-db:999:db_owner db_runtime db_superuser" "phyllon:65532:db_runtime" \
	"phyllon-proxy:65533:"; do
	IFS=: read -r name uid want <<<"$entry"
	want="$(for role in $want; do
		printf 'phyllon-%s-password %s %s 256\n' "${role//_/-}" "$uid" "$uid"
	done | paste -sd, -)"
	got="$(podman inspect "$name" |
		jq -r '.[0].Config.Secrets // [] | map("\(.Name) \(.UID) \(.GID) \(.Mode)") | sort | join(",")' || true)"
	if [[ "$got" == "$want" ]]; then
		pass "$name gets only its secrets${want:+, readable only by $uid}"
	else
		fail "$name gets the secrets '$got', want '$want'"
	fi
done
out="$(db_exec stat -c '%n %u %g %a' /run/secrets/db_superuser_password \
	/run/secrets/db_owner_password /run/secrets/db_runtime_password 2>&1 || true)"
if [[ "$(awk '$2 == 999 && $3 == 999 && $4 == 400' <<<"$out" | wc -l)" == 3 ]]; then
	pass "phyllon-db's secrets are mode 0400 and owned by 999"
else
	fail "phyllon-db's secrets are not mode 0400 and owned by 999: $out"
fi

# PostgreSQL sits on the internal network alone, so it has no route out and
# nothing outside reaches it; only Phyllon is on both networks.
out="$(podman network inspect --format '{{.Internal}}' systemd-phyllon-db 2>&1 || true)"
if [[ "$out" == true ]]; then
	pass "systemd-phyllon-db is internal"
else
	fail "systemd-phyllon-db is not internal: $out"
fi
for entry in phyllon-db:systemd-phyllon-db phyllon:systemd-phyllon-db,systemd-phyllon-edge \
	phyllon-proxy:systemd-phyllon-edge; do
	name="${entry%%:*}"
	want="${entry#*:}"
	got="$(podman inspect "$name" | jq -r '.[0].NetworkSettings.Networks // {} | keys | join(",")' || true)"
	if [[ "$got" == "$want" ]]; then
		pass "$name is on $want only"
	else
		fail "$name is on '$got', want $want"
	fi
done

stack_checks podman "$project"

if ((failed > 0)); then
	echo "quadlet-test.sh: $failed checks failed"
	exit 1
fi
echo "quadlet-test.sh: every check passed"
