#!/usr/bin/env bash
# Boots a throwaway Fedora Cloud Base VM under KVM, runs one command in it as
# an unprivileged user over SSH, and removes the VM again. CI uses it to run
# rootless Podman with SELinux enforcing, which an Ubuntu runner cannot. Run it
# with:
#
#   scripts/ci/fedora-vm.sh [--package NAME]... [--linger] [--copy PATH]... \
#     -- COMMAND [ARG]...
#
# The VM user has no sudo, so whatever needs root happens at boot, through
# cloud-init, before the command runs: each --package NAME installs a Fedora
# package with dnf, which needs the network, and --linger turns on systemd's
# linger for the user, so its user services run without a login session.
# Each --copy PATH (a file or a directory) is copied into the VM user's home
# directory before the command runs, under the base name of the path it
# resolves to: a symlink is followed and arrives under its target's name.
# COMMAND and its arguments reach the VM's shell word for word, and the
# script's stdin is the command's stdin. The exit status is the command's, or
# 255 if SSH failed; a failure before the command runs exits 1 with a message.
#
# The image is Fedora's, and nothing about it is trusted until it is checked:
# the CHECKSUM file must carry a good OpenPGP signature by the release key whose
# fingerprint is pinned below, and the image must match the SHA-256 that signed
# file lists. Both checks run on every start, also for a cached image. The
# verified image is cached in $PHYLLON_VM_CACHE (default ~/.cache/phyllon-vm)
# and never written to: each VM boots from a copy-on-write overlay. The SSH
# client key and the VM's SSH host key are generated per run, so the client
# trusts exactly this VM. The host's private key and the cloud-init user-data
# that carries it are deleted once the seed is built, and the overlay, the seed
# (which still holds the host key) and the client key when the script exits,
# however it exits. Only a SIGKILL skips that; the next start removes what such
# a run left.
#
# Settings, all optional: PHYLLON_VM_CACHE (directory), PHYLLON_VM_CPUS
# (default 2), PHYLLON_VM_MEMORY (MiB, default 4096), PHYLLON_VM_DISK (GiB the
# overlay may grow to, default 20) and PHYLLON_VM_BOOT_TIMEOUT (seconds until
# SSH must answer, default 300). It needs read and write access to /dev/kvm,
# qemu-system-x86_64, qemu-img, cloud-localds, gpgv, curl, ssh, ssh-keygen,
# setpriv and ss on the host, and nothing in the VM but its image.
#
# Changing this file needs the maintainer's explicit approval (AGENTS.md).

set -euo pipefail

# Fedora 44, the current stable release when this was written. Compose 1.7 is
# its final release, and a release tree never changes afterwards, so the names
# below always mean the same bytes. To move to a new release, change all three
# values together; the release keys and their fingerprints are listed at
# https://fedoraproject.org/security/.
release=44
compose=1.7
# "Fedora (44) <fedora-44-primary@fedoraproject.org>", rsa4096/DBFCF71C6D9F90A6.
key_fingerprint=36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6

# download.fedoraproject.org redirects to a nearby mirror. A mirror is not
# trusted either: the signature and the checksum decide.
base_url="https://download.fedoraproject.org/pub/fedora/linux/releases/$release/Cloud/x86_64/images"
image_name="Fedora-Cloud-Base-Generic-$release-$compose.x86_64.qcow2"
checksum_name="Fedora-Cloud-$release-$compose-x86_64-CHECKSUM"
# Fedora's published certificates for its current releases. The download is
# only a candidate: gpgv may use any key in it, and the check below accepts
# only a signature whose primary key is the pinned fingerprint.
key_url=https://fedoraproject.org/fedora.gpg
vm_user=phyllon

say() { printf 'fedora-vm.sh: %s\n' "$@" >&2; }
die() {
	say "$@"
	exit 1
}
# Milliseconds since the epoch; EPOCHREALTIME's separator follows the locale.
now_ms() {
	local t="${EPOCHREALTIME//[!0-9]/}"
	echo $((t / 1000))
}
# Prints the time since $1 (from now_ms) in seconds with one decimal.
since() {
	local ms=$(($(now_ms) - $1))
	printf '%d.%d s' $((ms / 1000)) $((ms % 1000 / 100))
}

usage="usage: scripts/ci/fedora-vm.sh [--package NAME]... [--linger] [--copy PATH]... -- COMMAND [ARG]..."
copies=()
packages=()
linger=false
while (($# > 0)); do
	case "$1" in
	--package)
		(($# >= 2)) || die "--package needs a name"
		# The name goes into the YAML that root acts on, so it must be a
		# plain package name: no space, quote, newline or leading dash.
		[[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] ||
			die "--package: '$2' is not a package name"
		packages+=("$2")
		shift 2
		;;
	--linger)
		linger=true
		shift
		;;
	--copy)
		(($# >= 2)) || die "--copy needs a path"
		[[ -e "$2" ]] || die "--copy: $2 does not exist"
		copies+=("$(realpath -- "$2")")
		shift 2
		;;
	--)
		shift
		break
		;;
	*) die "$usage" ;;
	esac
done
(($# > 0)) || die "$usage"

# Reads a positive integer setting $1 with default $2 and maximum $3.
setting() {
	local value="${!1:-$2}"
	if [[ ! "$value" =~ ^[1-9][0-9]{0,5}$ ]] || ((value > $3)); then
		die "$1 must be a whole number from 1 to $3, not '$value'"
	fi
	echo "$value"
}
cpus="$(setting PHYLLON_VM_CPUS 2 64)"
memory="$(setting PHYLLON_VM_MEMORY 4096 262144)"
disk="$(setting PHYLLON_VM_DISK 20 2048)"
boot_timeout="$(setting PHYLLON_VM_BOOT_TIMEOUT 300 3600)"

for tool in qemu-system-x86_64 qemu-img cloud-localds gpgv curl sha256sum \
	ssh ssh-keygen setpriv ss timeout; do
	command -v "$tool" >/dev/null 2>&1 || die "$tool not found"
done
cache="${PHYLLON_VM_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/phyllon-vm}"
mkdir -p -- "$cache"
# Absolute, because the overlay records the image's path as given.
cache="$(realpath -- "$cache")"
# Everything this run creates lives here, so one rm removes it. The overlay
# can grow to gigabytes, which is why this is not under /tmp.
run="$(mktemp -d -p "$cache" run.XXXXXX)"
echo "$$" >"$run/owner"
# A run killed by SIGKILL cannot run its trap and leaves its directory behind;
# its QEMU dies with it (see start_qemu). Remove such directories, but not
# those of runs still going, nor one so new that it has no owner file yet.
for old in "$cache"/run.*; do
	[[ "$old" != "$run" && -f "$old/owner" ]] || continue
	owner="$(<"$old/owner")"
	if [[ ! "$owner" =~ ^[0-9]+$ ]] || ! kill -0 "$owner" 2>/dev/null; then
		rm -rf -- "$old"
	fi
done
qemu_pid=""
# shellcheck disable=SC2329 # the EXIT trap calls it
cleanup() {
	local status=$? i
	if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
		# The overlay is thrown away, so a clean guest shutdown would buy
		# nothing. SIGTERM makes QEMU stop the VM and exit.
		kill -TERM "$qemu_pid" 2>/dev/null || true
		for ((i = 0; i < 50; i++)); do
			kill -0 "$qemu_pid" 2>/dev/null || break
			sleep 0.2
		done
		kill -KILL "$qemu_pid" 2>/dev/null || true
	fi
	[[ -z "$qemu_pid" ]] || wait "$qemu_pid" 2>/dev/null || true
	rm -rf -- "$run"
	exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Downloads $1 to $2 with at most $3 bytes, over HTTPS only.
fetch() {
	curl --fail --silent --show-error --location --proto '=https' \
		--proto-redir '=https' --retry 3 --connect-timeout 20 \
		--speed-limit 1048576 --speed-time 30 \
		--max-filesize "$3" --user-agent phyllon-dev-tooling \
		--output "$2" -- "$1"
}

# Checks the signature on CHECKSUM file $1 with the keys in $2 and writes the
# signed text, and only that, to $3. Fails unless the signature is good and
# made by the pinned key.
verify_checksum_file() {
	local signer
	gpgv --keyring "$2" --status-fd 3 --output "$3" -- "$1" \
		3>"$run/gpgv.status" 2>"$run/gpgv.log" || {
		cat -- "$run/gpgv.log" >&2
		return 1
	}
	# VALIDSIG's last field is the primary key's fingerprint.
	signer="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "$run/gpgv.status")"
	[[ "$signer" == "$key_fingerprint" ]] || {
		say "signed by '${signer:-nobody}', not by the pinned key $key_fingerprint"
		return 1
	}
}

# Prints the SHA-256 the verified CHECKSUM text $1 lists for the image.
expected_sha256() {
	local line prefix="SHA256 ($image_name) = " found=""
	while IFS= read -r line; do
		if [[ "$line" == "$prefix"* ]]; then
			[[ -z "$found" ]] || return 1
			found="${line#"$prefix"}"
		fi
	done <"$1"
	[[ "$found" =~ ^[0-9a-f]{64}$ ]] || return 1
	echo "$found"
}

# Checks image $1 against the SHA-256 in verified CHECKSUM text $2.
verify_image() {
	local want got
	want="$(expected_sha256 "$2")" || {
		say "$checksum_name lists no single SHA-256 for $image_name"
		return 1
	}
	got="$(sha256sum -- "$1")"
	got="${got%% *}"
	[[ "$got" == "$want" ]] || {
		say "$1 has SHA-256 $got, but the signed $checksum_name says $want"
		return 1
	}
}

# The image. Each file enters the cache only once it has passed its check, and
# the checks run again on every start, so a corrupted or altered cache fails
# here instead of booting.
start="$(now_ms)"
if [[ ! -f "$cache/$checksum_name" || ! -f "$cache/fedora.gpg" ]]; then
	say "downloading $checksum_name and Fedora's keys"
	fetch "$key_url" "$run/fedora.gpg" 1048576 ||
		die "could not download $key_url"
	fetch "$base_url/$checksum_name" "$run/$checksum_name" 65536 ||
		die "could not download $base_url/$checksum_name"
	verify_checksum_file "$run/$checksum_name" "$run/fedora.gpg" "$run/checksum.txt" ||
		die "the signature on the downloaded $checksum_name does not verify"
	mv -f -- "$run/fedora.gpg" "$cache/fedora.gpg"
	mv -f -- "$run/$checksum_name" "$cache/$checksum_name"
fi
verify_checksum_file "$cache/$checksum_name" "$cache/fedora.gpg" "$run/checksum.txt" ||
	die "the signature on the cached $cache/$checksum_name does not verify;" \
		"delete it and $cache/fedora.gpg to download both again"
if [[ ! -f "$cache/$image_name" ]]; then
	say "downloading $image_name"
	fetch "$base_url/$image_name" "$run/download" 4294967296 ||
		die "could not download $base_url/$image_name"
	say "downloaded in $(since "$start")"
	verify_image "$run/download" "$run/checksum.txt" ||
		die "the downloaded image does not match the signed checksum"
	chmod a-w -- "$run/download"
	mv -f -- "$run/download" "$cache/$image_name"
else
	verify_image "$cache/$image_name" "$run/checksum.txt" ||
		die "the cached image does not match the signed checksum; delete $cache/$image_name"
fi
say "image verified: Fedora $release ($compose), signed by $key_fingerprint, after $(since "$start")"

# The VM's disk: an overlay on the verified image, which QEMU opens read-only.
qemu-img create -q -f qcow2 -F qcow2 -b "$cache/$image_name" "$run/disk.qcow2" "${disk}G"

# The keys for this run only: one the client logs in with, and the VM's host
# key, which the client pins instead of trusting whatever answers first.
ssh-keygen -q -t ed25519 -N '' -C "$vm_user" -f "$run/id_ed25519"
ssh-keygen -q -t ed25519 -N '' -C phyllon-vm -f "$run/host_ed25519"
printf 'phyllon-vm %s\n' "$(cut -d' ' -f1,2 "$run/host_ed25519.pub")" >"$run/known_hosts"

# The NoCloud seed: one user who logs in with the run's key and has no
# password and no sudo, the host key, and the root work the options ask for.
# Cloud-init creates no default user.
{
	cat <<EOF
#cloud-config
users:
  - name: $vm_user
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(<"$run/id_ed25519.pub")
disable_root: true
ssh_pwauth: false
ssh_deletekeys: true
ssh_keys:
  ed25519_public: $(<"$run/host_ed25519.pub")
  ed25519_private: |
EOF
	sed 's/^/    /' "$run/host_ed25519"
	if ((${#packages[@]} > 0)); then
		# Quoted, so YAML reads a name such as null as a string.
		echo "packages:"
		printf "  - '%s'\n" "${packages[@]}"
	fi
	if [[ "$linger" == true ]]; then
		printf 'runcmd:\n  - [loginctl, enable-linger, %s]\n' "$vm_user"
	fi
} >"$run/user-data"
printf 'instance-id: phyllon-%s\n' "${run##*.}" >"$run/meta-data"
cloud-localds "$run/seed.img" "$run/user-data" "$run/meta-data"
rm -f -- "$run/host_ed25519" "$run/user-data"

# Checked this late so that the image checks run, and can be tested, without
# KVM.
[[ -r /dev/kvm && -w /dev/kvm ]] ||
	die "/dev/kvm is missing or not readable and writable by $(id -un)"

# Picks a port on 127.0.0.1 nothing listens on. QEMU binds it itself, so
# another program can still take it first; then QEMU exits and the next
# attempt picks another port.
pick_port() {
	local p i
	for ((i = 0; i < 50; i++)); do
		p=$((RANDOM % 20000 + 30000))
		if [[ -z "$(ss -Hltn "sport = :$p")" ]]; then
			echo "$p"
			return 0
		fi
	done
	return 1
}

# Starts QEMU in the background with the SSH forward on $1. setpriv makes the
# kernel kill QEMU if this script dies without running its trap.
start_qemu() {
	setpriv --pdeathsig KILL -- qemu-system-x86_64 \
		-name phyllon-vm -machine q35 -enable-kvm -cpu host \
		-smp "$cpus" -m "$memory" \
		-nodefaults -no-user-config -display none \
		-serial "file:$run/console.log" \
		-drive "if=virtio,format=qcow2,file=$run/disk.qcow2,discard=unmap" \
		-drive "if=virtio,format=raw,file=$run/seed.img,readonly=on" \
		-netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$1-:22" \
		-device virtio-net-pci,netdev=net0,romfile= \
		-device virtio-rng-pci \
		</dev/null >"$run/qemu.log" 2>&1 &
	qemu_pid=$!
}

boot="$(now_ms)"
port=""
for ((attempt = 1; attempt <= 5; attempt++)); do
	candidate="$(pick_port)" || die "found no free port on 127.0.0.1"
	start_qemu "$candidate"
	# QEMU sets up the forward before the guest runs, so within seconds it
	# either listens on the port or has exited.
	for ((i = 0; i < 100; i++)); do
		kill -0 "$qemu_pid" 2>/dev/null || break
		if [[ -n "$(ss -Hltn "sport = :$candidate")" ]]; then
			port="$candidate"
			break 2
		fi
		sleep 0.1
	done
	if kill -0 "$qemu_pid" 2>/dev/null; then
		die "QEMU runs but does not listen on 127.0.0.1:$candidate"
	fi
	wait "$qemu_pid" 2>/dev/null || true
	qemu_pid=""
	say "QEMU did not start (attempt $attempt):"
	cat -- "$run/qemu.log" >&2
done
[[ -n "$port" ]] || die "QEMU did not start"

ssh_opts=(
	-F /dev/null -p "$port" -i "$run/id_ed25519"
	-o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes
	-o HostKeyAlias=phyllon-vm -o StrictHostKeyChecking=yes
	-o UserKnownHostsFile="$run/known_hosts" -o GlobalKnownHostsFile=/dev/null
	-o ConnectTimeout=5 -o ServerAliveInterval=10 -o ServerAliveCountMax=6
	-o LogLevel=ERROR
)
# The callers quote what the VM's shell must not split.
# shellcheck disable=SC2029
vm() { ssh "${ssh_opts[@]}" "$vm_user@127.0.0.1" "$@"; }

deadline=$((SECONDS + boot_timeout))
# User-mode networking accepts the connection before the guest's sshd runs,
# so each attempt has its own time limit. --foreground lets Ctrl-C reach ssh.
until timeout --foreground 15 ssh "${ssh_opts[@]}" -n "$vm_user@127.0.0.1" true \
	2>"$run/ssh.log"; do
	if ! kill -0 "$qemu_pid" 2>/dev/null; then
		say "QEMU exited before SSH answered:"
		cat -- "$run/qemu.log" >&2
		tail -n 40 -- "$run/console.log" >&2 || true
		die "the VM did not boot"
	fi
	if ((SECONDS >= deadline)); then
		tail -n 40 -- "$run/console.log" >&2 || true
		say "the last SSH attempt said:"
		cat -- "$run/ssh.log" >&2
		die "SSH did not answer within $boot_timeout s"
	fi
	sleep 1
done
say "SSH answered after $(since "$boot") (port $port)"

# Wait for cloud-init to finish, so the command does not race its last steps.
# Exit 2 means it finished with warnings only.
status=0
timeout --foreground "$boot_timeout" ssh "${ssh_opts[@]}" -n "$vm_user@127.0.0.1" \
	cloud-init status --wait --long >"$run/cloud-init.log" 2>&1 || status=$?
if ((status == 2)); then
	say "cloud-init finished with warnings:"
	cat -- "$run/cloud-init.log" >&2
elif ((status != 0)); then
	cat -- "$run/cloud-init.log" >&2
	die "cloud-init failed in the VM (exit $status)"
fi
say "VM ready after $(since "$boot")"

for path in ${copies[@]+"${copies[@]}"}; do
	tar -C "$(dirname -- "$path")" -cf - -- "$(basename -- "$path")" |
		vm tar -xf - || die "could not copy $path into the VM"
	say "copied $path"
done

# printf %q quotes each word for the VM user's bash, so the command arrives as
# its words and not as one string the remote shell splits again.
command_start="$(now_ms)"
status=0
vm "$(printf '%q ' "$@")" || status=$?
say "command exited $status after $(since "$command_start"); total $(since "$start")"
exit "$status"
