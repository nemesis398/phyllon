#!/usr/bin/env bash
# Checks the hardening of every container of a compose project from the
# engine's inspect output, and lists each gap. Run it with:
#
#   scripts/posture.sh ENGINE PROJECT
#
# ENGINE is docker or podman, PROJECT the compose project name. Exit 0 means
# no gap, 1 one or more gaps (or no container at all), 2 an error.
#
# Each container must not run privileged or on the host network, must drop
# every capability and keep none, set no-new-privileges, have a memory and a
# pids limit and a healthcheck, mount no engine socket, run as a user other
# than root and publish no port unless it is the proxy. phyllon must also have
# a read-only root. The one capability allowed is NET_BIND_SERVICE on proxy,
# which the caddy binary needs to start (see compose.yaml).
#
# Docker and Podman write inspect differently. Docker keeps CapDrop as given
# (["ALL"]) with CapAdd beside it; Podman expands CapDrop to the capabilities
# it dropped and lists what is left in BoundingCaps, so a container that has
# BoundingCaps is judged by that list. Podman's docker command answers in
# Podman's format, which is why the format, not ENGINE, decides.

set -euo pipefail

case "${1:-}:$#" in
docker:2 | podman:2) engine="$1" project="$2" ;;
*)
	echo "usage: scripts/posture.sh docker|podman PROJECT" >&2
	exit 2
	;;
esac

ids="$("$engine" ps --all --quiet --filter "label=com.docker.compose.project=$project")"
if [[ -z "$ids" ]]; then
	echo "posture: no containers for the project $project"
	exit 1
fi
# shellcheck disable=SC2086 # one argument per id
inspect="$("$engine" inspect $ids 2>/dev/null)" || {
	echo "posture: $engine inspect failed" >&2
	exit 2
}

# One line per check: "ok" or "gap <container>: <what>".
results="$(jq -r '
	def caps: map(ascii_upcase | ltrimstr("CAP_"));
	.[] | (.Name | ltrimstr("/")) as $name
	| (.Config.Labels["com.docker.compose.service"] // "") as $service
	| .HostConfig as $h
	| (if has("BoundingCaps") then {all: true, kept: (.BoundingCaps // [] | caps)}
		else {all: ($h.CapDrop // [] | caps | index(["ALL"]) != null),
			kept: ($h.CapAdd // [] | caps)} end) as $caps
	| ($caps.kept - (if $service == "proxy" then ["NET_BIND_SERVICE"] else [] end)) as $extra
	| (.Config.User // "") as $user
	| [.Mounts[]? | .Source, .Destination | select(test("(docker|podman)\\.sock$"))] as $sockets
	| [
		[$h.Privileged != true, "runs privileged"],
		[$h.NetworkMode != "host", "uses the host network"],
		[$caps.all, "does not drop all capabilities"],
		[$extra == [], "keeps the capabilities \($extra | join(", "))"],
		[any($h.SecurityOpt[]?; test("^no-new-privileges([:=]true)?$")), "does not set no-new-privileges"],
		[($h.Memory // 0) > 0, "has no memory limit"],
		[($h.PidsLimit // 0) > 0, "has no pids limit"],
		[(.Config.Healthcheck.Test // [] | length > 0 and .[0] != "NONE"), "has no healthcheck"],
		[$sockets == [], "mounts the engine socket \($sockets | unique | join(", "))"],
		[($user | test("^(root|0)?(:.*)?$") | not), "runs as root (user \($user | tojson))"],
		[$service == "proxy" or ([$h.PortBindings // {} | .[] // [] | .[]] == []),
			"publishes a port, which only proxy may"]
	  ]
	+ (if $service == "phyllon" then [[$h.ReadonlyRootfs == true, "has a writable root filesystem"]] else [] end)
	| .[] | if .[0] then "ok" else "gap \($name): \(.[1])" end
' <<<"$inspect")"

containers="$(jq length <<<"$inspect")"
total="$(wc -l <<<"$results")"
gaps="$(command grep -c '^gap ' <<<"$results" || true)"
if ((gaps == 0)); then
	echo "posture: $total checks passed on $containers containers"
	exit 0
fi
command grep '^gap ' <<<"$results" | sed 's/^gap /posture: /'
if ((gaps == 1)); then
	echo "posture: 1 gap, $((total - gaps)) of $total checks passed"
else
	echo "posture: $gaps gaps, $((total - gaps)) of $total checks passed"
fi
exit 1
