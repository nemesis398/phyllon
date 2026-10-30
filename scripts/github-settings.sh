#!/usr/bin/env bash
# Phyllon's GitHub settings, kept in one table so they can be audited and
# applied again. Run it with:
#
#   scripts/github-settings.sh audit   list each setting that differs; exit 0
#                                      when none does and 1 when some do
#   scripts/github-settings.sh apply   write every setting in the table
#
# Both need jq and gh, logged in as an admin of the repository. audit only
# reads. apply changes a public repository, so read the audit first. Exit 2
# means an error, such as a request that failed for another reason than drift.
# The social preview image is not in the table, because the API cannot set it.

set -euo pipefail

repo=nemesis398/phyllon
# The REST API version the endpoints below were read against.
api_version="X-GitHub-Api-Version: 2026-03-10"

# The table. Each key is a REST endpoint under /repos/{owner}/{repo} ("" is
# the repository itself) and each value is what GET there must return. audit
# compares the fields named here and ignores the others, and apply sends them.
expected="$(jq -n '{
	# GET and PATCH /repos/{owner}/{repo}. has_discussions is missing from the
	# documented PATCH body, but gh repo edit --enable-discussions sends it so.
	"": {
		description: "Self-hosted task library, worksheet engine and checker that AI clients use over MCP",
		homepage: "https://phyllon.de",
		has_discussions: true,
		# Squash only. The subject is the pull request title and the body the
		# commit messages, so the sign-offs reach main.
		allow_squash_merge: true,
		allow_merge_commit: false,
		allow_rebase_merge: false,
		squash_merge_commit_title: "PR_TITLE",
		squash_merge_commit_message: "COMMIT_MESSAGES",
		delete_branch_on_merge: true,
		security_and_analysis: {
			secret_scanning: {status: "enabled"},
			secret_scanning_push_protection: {status: "enabled"}
		}
	},
	# GET and PUT /repos/{owner}/{repo}/topics.
	topics: {names: ["edtech", "education", "llm", "math", "mcp", "mcp-server",
		"model-context-protocol", "pgvector", "postgresql", "rust", "self-hosted",
		"typst", "worksheet-generator", "worksheets"]},
	# The four switches: PUT turns one on and DELETE off. GET answers
	# {"enabled": ...}, except that GET /vulnerability-alerts (Dependabot
	# alerts) answers 204 when on, and each of the last three answers 404 when
	# off. Alerts come before security updates, which need them. Dependabot
	# pauses security updates when its pull requests go ignored; PUT takes no
	# body, so apply cannot clear a pause, but audit shows it.
	"private-vulnerability-reporting": {enabled: true},
	"vulnerability-alerts": {enabled: true},
	"automated-security-fixes": {enabled: true, paused: false},
	"immutable-releases": {enabled: true},
	# CodeQL default setup: GET and PATCH. PATCH answers 202 and sets it up in
	# the background, so an audit right after apply may still see it pending.
	"code-scanning/default-setup": {state: "configured"},
	# GET and PUT /repos/{owner}/{repo}/actions/permissions/workflow.
	"actions/permissions/workflow": {
		default_workflow_permissions: "read",
		can_approve_pull_request_reviews: false
	},
	# GET and PUT .../actions/permissions/fork-pr-contributor-approval.
	"actions/permissions/fork-pr-contributor-approval": {
		approval_policy: "all_external_contributors"
	},
	# Rulesets, by name: GET /rulesets?includes_parents=false lists them, GET
	# /rulesets/{id} reads one, PUT /rulesets/{id} updates it and POST
	# /rulesets creates it. GitHub signs squash merges and Dependabot commits,
	# so signed commits break nothing legitimate. strict is off, because an
	# up-to-date branch would rebase every Dependabot pull request after each
	# merge. Each check is pinned to the GitHub Actions app (15368), so no other
	# app can pass it by posting a status with the same name.
	rulesets: [{
		name: "main",
		target: "branch",
		enforcement: "active",
		bypass_actors: [],
		conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
		rules: [
			{type: "deletion"},
			{type: "non_fast_forward"},
			{type: "required_linear_history"},
			{type: "required_signatures"},
			{type: "pull_request", parameters: {
				required_approving_review_count: 0,
				dismiss_stale_reviews_on_push: false,
				require_code_owner_review: false,
				require_last_push_approval: false,
				required_review_thread_resolution: false,
				allowed_merge_methods: ["squash"]
			}},
			{type: "required_status_checks", parameters: {
				strict_required_status_checks_policy: false,
				do_not_enforce_on_create: false,
				# The jobs of ci.yml, and pr-title from pr-title.yml.
				required_status_checks: ["gate", "integration (17)",
					"integration (18)", "pr-title", "sign-off", "dependency-review",
					"markdown", "scripts"] | map({context: ., integration_id: 15368})
			}}
		]
	}]
}')"

toggles=" private-vulnerability-reporting vulnerability-alerts automated-security-fixes immutable-releases "

fail() {
	printf 'github-settings.sh: %s\n' "$@" >&2
	exit 2
}

tmp="$(mktemp -d -p "${TMPDIR:-/tmp}" github-settings.XXXXXX)"
trap 'rm -rf -- "$tmp"' EXIT

# Prints the answer to GET /repos/{owner}/{repo}/$1: nothing for a 204 and null
# for a 404. Any other failure ends the script.
get() {
	local path="repos/$repo${1:+/$1}"
	if gh api -H "$api_version" "$path" >"$tmp/body" 2>"$tmp/err"; then
		cat -- "$tmp/body"
	elif [[ "$(<"$tmp/err")" == *"(HTTP 404)"* ]]; then
		echo null
	else
		fail "GET $path failed: $(<"$tmp/err")"
	fi
}

# Prints the repository's own rulesets as a JSON array. Anything else, a 404
# included, ends the script, because without the list apply would create a
# second ruleset.
rulesets() {
	local list
	list="$(get "rulesets?includes_parents=false")"
	jq -e 'type == "array"' <<<"$list" >/dev/null ||
		fail "GET repos/$repo/rulesets returned no list: ${list:0:200}"
	printf '%s\n' "$list"
}

# Sends $1 to /repos/{owner}/{repo}/$2, with the body $3 if given.
write() {
	local path="repos/$repo${2:+/$2}" input=()
	(($# < 3)) || input=(--input -)
	echo "apply: $1 $path"
	gh api -X "$1" -H "$api_version" "$path" "${input[@]}" <<<"${3-}" >/dev/null ||
		fail "$1 $path failed"
}

# Reads every endpoint of the table into $live, in the table's shape.
read_live() {
	local key body summary
	live='{}'
	while IFS= read -r key; do
		body="$(get "$key")"
		if [[ "$toggles" == *" $key "* ]]; then
			[[ "$body" != null ]] || body='{"enabled": false}'
			[[ -n "$body" ]] || body='{"enabled": true}'
		fi
		live="$(jq --arg k "$key" --argjson v "${body:-null}" '.[$k] = $v' <<<"$live")"
	done < <(jq -r 'keys_unsorted[] | select(. != "rulesets")' <<<"$expected")
	# The full ruleset for each name in the table, the summary for the others.
	live="$(jq '.rulesets = []' <<<"$live")"
	body="$(rulesets)"
	while IFS= read -r summary; do
		if jq -e --argjson s "$summary" 'any(.rulesets[]; .name == $s.name)' \
			<<<"$expected" >/dev/null; then
			summary="$(get "rulesets/$(jq -r .id <<<"$summary")")"
		fi
		live="$(jq --argjson s "$summary" '.rulesets += [$s]' <<<"$live")"
	done < <(jq -c '.[]' <<<"$body")
}

audit() {
	local drift count
	read_live
	drift="$(jq -r --argjson want "$expected" '
		# An extra field GitHub returns is fine while it is off.
		def off: . == null or . == false or . == 0 or . == "" or . == []
			or (type == "object" and all(.[]; off));
		def norm: if type == "array" then sort else . end;
		# A line for each field of $w whose value here differs. Arrays are sets,
		# so for two arrays the line names what is missing and what is extra.
		def diff($w; $label): . as $is
			| [$w | paths(type != "object") | select(all(.[]; type == "string"))][] as $p
			| ($is | getpath($p)) as $v | ($w | getpath($p)) as $x
			| select(($v | norm) != ($x | norm))
			| "\($label) .\($p | join(".")): " + (if [$v, $x | type] == ["array", "array"]
				then "missing \($x - $v | tojson), extra \($v - $x | tojson)"
				else "is \($v | tojson), want \($x | tojson)" end);
		def ruleset($w): . as $is | "ruleset \($w.name)" as $l
			| ($is | del(.rules, .bypass_actors) | diff($w | del(.rules, .bypass_actors); $l)),
			(if $is.bypass_actors == null then "\($l): bypass actors unreadable"
				else $is.bypass_actors[]
				| "\($l): bypass actor \(.actor_type) \(.actor_id) (\(.bypass_mode))" end),
			(($w.rules | map(.type)) as $wt | ($is.rules // [] | map(.type)) as $it
				| (($it - $wt)[] | "\($l): extra rule \(.)"),
				(($wt - $it)[] | "\($l): missing rule \(.)")),
			($w.rules[] as $r | ($r.parameters // {}) as $rp
				| ($is.rules // [])[] | select(.type == $r.type) | (.parameters // {})
				| diff($rp; "\($l) rule \($r.type)"),
				(to_entries[] | select(.key as $k | $rp | has($k) | not)
					| select(.value | off | not)
					| "\($l) rule \($r.type) .\(.key): is \(.value | tojson), want it off"));
		. as $live
		| ($want | to_entries[] | select(.key != "rulesets") | .key as $k
			| $live[$k] | diff($want[$k]; if $k == "" then "repo" else $k end)),
		($want.rulesets[] as $w | [$live.rulesets[] | select(.name == $w.name)] as $m
			| if $m == [] then "ruleset \($w.name): missing"
			elif ($m | length) > 1 then "ruleset \($w.name): \($m | length) share the name"
			else $m[0] | ruleset($w) end),
		($live.rulesets[] | select(.name as $n | all($want.rulesets[]; .name != $n))
			| "ruleset \(.name): not in the table")
		| "drift: \(.)"' <<<"$live")"
	if [[ -z "$drift" ]]; then
		echo "audit: every setting matches"
		return 0
	fi
	printf '%s\n' "$drift"
	count="$(wc -l <<<"$drift")"
	if ((count == 1)); then
		echo "audit: 1 setting differs"
	else
		echo "audit: $count settings differ"
	fi
	return 1
}

apply() {
	local key body list id
	# Read the ruleset list first, so a failure stops apply before any write.
	list="$(rulesets)"
	while IFS= read -r key; do
		body="$(jq -c --arg k "$key" '.[$k]' <<<"$expected")"
		if [[ "$toggles" == *" $key "* ]]; then
			if [[ "$(jq .enabled <<<"$body")" == true ]]; then
				write PUT "$key"
			else
				write DELETE "$key"
			fi
		elif [[ -z "$key" || "$key" == code-scanning/default-setup ]]; then
			write PATCH "$key" "$body"
		else
			write PUT "$key" "$body"
		fi
	done < <(jq -r 'keys_unsorted[] | select(. != "rulesets")' <<<"$expected")
	# Update a ruleset by name, so a second run never creates a second one.
	while IFS= read -r body; do
		id="$(jq -r --argjson b "$body" \
			'first(.[] | select(.name == $b.name) | .id) // empty' <<<"$list")"
		if [[ -n "$id" ]]; then
			write PUT "rulesets/$id" "$body"
		else
			write POST rulesets "$body"
		fi
	done < <(jq -c '.rulesets[]' <<<"$expected")
	echo "apply: done; run scripts/github-settings.sh audit to check"
}

command -v jq >/dev/null 2>&1 || fail "jq not found."
command -v gh >/dev/null 2>&1 || fail "gh not found."
case "${1:-}:$#" in
audit:1) audit ;;
apply:1) apply ;;
*)
	echo "usage: scripts/github-settings.sh audit|apply" >&2
	exit 2
	;;
esac
