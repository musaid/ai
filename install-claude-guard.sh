#!/usr/bin/env bash
# install-claude-guard.sh — portable installer for the Claude Code guard setup.
#
#   ./install-claude-guard.sh [CODE_ROOT ...]
#
# CODE_ROOT is where your repos live. Pass one or more; if you pass none the
# script tries to detect them. Everything else is derived, so this works on a
# machine with different paths, a different package manager, or Linux.
#
# Idempotent: re-running is safe. Always backs up settings.json first.
# MERGES into existing settings — your model, plugins, and MCP config survive.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_DIR="$CLAUDE_DIR/hooks"
HOOK="$HOOK_DIR/claude-guard.sh"
TS=$(date +%Y%m%d-%H%M%S)

say() { printf '  %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

echo "== Claude Code guard installer =="

# ---------------------------------------------------------------- prerequisites
command -v jq      >/dev/null || die "jq is required (brew install jq / apt install jq)"
command -v python3 >/dev/null || die "python3 is required"
say "jq $(jq --version), python3 ok"

# ---------------------------------------------------------------- code roots
ROOTS=("$@")
if [ ${#ROOTS[@]} -eq 0 ]; then
  say "no CODE_ROOT given - detecting..."
  for cand in "$HOME/work" "$HOME/code" "$HOME/src" "$HOME/dev" \
              "$HOME/projects" "$HOME/repos" "$HOME/Developer"; do
    [ -d "$cand" ] && ROOTS+=("$cand")
  done
  [ ${#ROOTS[@]} -eq 0 ] && die "could not detect a code root - pass one explicitly, e.g. $0 ~/work"
fi
for r in "${ROOTS[@]}"; do [ -d "$r" ] || die "not a directory: $r"; done
say "code roots: ${ROOTS[*]}"

# ---------------------------------------------------------------- cache dirs
CACHES=()
case "$(uname -s)" in
  Darwin) CACHES+=("~/Library/Caches" "~/Library/pnpm") ;;
  Linux)  CACHES+=("~/.cache" "~/.local/share/pnpm") ;;
esac
CACHES+=("~/.cache" "~/.npm" "~/.local/state/fnm_multishells")
say "cache write paths: ${CACHES[*]}"

# ---------------------------------------------------------------- guard script
[ -f "${GUARD_SRC:-}" ] || GUARD_SRC="$(dirname "$0")/claude-guard.sh"
[ -f "$GUARD_SRC" ] || die "claude-guard.sh not found next to this script (set GUARD_SRC=/path/to/it)"
bash -n "$GUARD_SRC" || die "claude-guard.sh has a syntax error"

mkdir -p "$HOOK_DIR"
cp "$GUARD_SRC" "$HOOK"
chmod +x "$HOOK"
say "installed $HOOK"

# ---------------------------------------------------------------- merge settings
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-$TS"
say "backed up  $SETTINGS.bak-$TS"

ROOTS_JSON=$(printf '%s\n' "${ROOTS[@]}" | python3 -c 'import sys,json;print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
CACHES_JSON=$(printf '%s\n' "${CACHES[@]}" | python3 -c 'import sys,json;print(json.dumps(sorted(set(l.strip() for l in sys.stdin if l.strip()))))')

ROOTS_JSON="$ROOTS_JSON" CACHES_JSON="$CACHES_JSON" SETTINGS="$SETTINGS" python3 <<'PY'
import json, os

settings_path = os.environ["SETTINGS"]
roots  = json.loads(os.environ["ROOTS_JSON"])
caches = json.loads(os.environ["CACHES_JSON"])

with open(settings_path) as f:
    s = json.load(f)

# --- permissions: allow broadly, gate via the hook, keep hard denies ----------
perms = s.setdefault("permissions", {})
perms["defaultMode"] = "auto"
perms["allow"] = sorted(set(perms.get("allow", [])) | {"Bash", "Edit", "Write", "Read", "WebFetch"})
perms["ask"] = []          # the hook decides; broad ask rules only cause friction
perms["additionalDirectories"] = sorted(set(perms.get("additionalDirectories", [])) | set(roots))
# NOTE: deliberately NO Bash(...) deny rules here.
# Deny rules are evaluated regardless of what the hook returns, so a blunt glob
# like Bash(rm -rf *) OVERRIDES the hook's nuance and hard-blocks legitimate
# work (verified: it blocked `rm -rf node_modules`, which the hook allows).
# The hook is strictly more precise - let it be the sole authority on Bash.
# Read/Edit denies stay: they are OS-enforced (they stop node/python/subprocess
# reads, not just Claude's tools) and never conflict with the hook.
perms["deny"] = sorted(set(perms.get("deny", [])) | {
    "Read(**/.env)", "Read(**/.env.local)", "Read(**/.env.*.local)",
    "Read(**/.env.*.prod)", "Read(**/.env.*.production)",
    "Read(**/.dev.vars)", "Read(**/.dev.vars.*)",
    "Read(**/secrets)", "Read(**/secrets/**)",
    "Read(**/id_rsa)", "Read(**/id_ed25519)",
    "Edit(**/.env*)", "Edit(**/.dev.vars*)",
})

# --- git over HTTPS, scoped to Claude Code only ------------------------------
# The sandbox proxies SSH via `nc` with no credentials, so SSH remotes fail and
# every fetch/pull/push escalates. This rewrite is env-scoped: the user's own
# ~/.gitconfig and terminal git are untouched.
env = s.setdefault("env", {})
env.setdefault("GIT_CONFIG_COUNT", "1")
env.setdefault("GIT_CONFIG_KEY_0", "url.https://github.com/.insteadOf")
env.setdefault("GIT_CONFIG_VALUE_0", "git@github.com:")

# --- hook (replace any prior claude-guard entry, keep other hooks) ------------
hooks = s.setdefault("hooks", {})
pre = [b for b in hooks.get("PreToolUse", [])
       if not any("claude-guard" in (h.get("command") or "") for h in b.get("hooks", []))]
pre.append({
    "matcher": "Bash",
    "hooks": [{
        "type": "command",
        "command": "$HOME/.claude/hooks/claude-guard.sh",
        "timeout": 10,
        "statusMessage": "Checking command safety...",
    }],
})
hooks["PreToolUse"] = pre

# --- sandbox -----------------------------------------------------------------
sb = s.setdefault("sandbox", {})
sb["enabled"] = True
sb["failIfUnavailable"] = True          # fail closed, never silently unsandboxed
sb["autoAllowBashIfSandboxed"] = True
sb["enableWeakerNetworkIsolation"] = True   # lets Go tools (gh) verify TLS in-sandbox

net = sb.setdefault("network", {})
net["allowLocalBinding"] = True
net["strictAllowlist"] = True            # without this the allowlist is NOT enforced
net["allowedDomains"] = sorted(set(net.get("allowedDomains", [])) | {
    "localhost", "127.0.0.1",
    "github.com", "*.github.com", "*.githubusercontent.com",
    "registry.npmjs.org", "npm.pkg.github.com",
})

fs = sb.setdefault("filesystem", {})
fs["allowWrite"] = sorted(set(fs.get("allowWrite", [])) | set(caches) | set(roots))

cred = sb.setdefault("credentials", {})
cred["files"] = [{"path": p, "mode": "deny"} for p in
                 sorted({c["path"] for c in cred.get("files", [])} |
                        {"~/.aws", "~/.config/gcloud", "~/.ssh"})]
cred["envVars"] = [{"name": n, "mode": "deny"} for n in
                   sorted({c["name"] for c in cred.get("envVars", [])} |
                          {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY",
                           "AWS_SESSION_TOKEN", "GOOGLE_APPLICATION_CREDENTIALS"})]

with open(settings_path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
print("  merged settings")
PY

python3 -c "import json;json.load(open('$SETTINGS'))" || die "settings.json is invalid - restore $SETTINGS.bak-$TS"

# ---------------------------------------------------------------- verify
echo
echo "== verification =="
jq -e '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[] | .command' "$SETTINGS" >/dev/null \
  && say "hook registered ✅"
say "ask rules:  $(jq '.permissions.ask | length' "$SETTINGS")  (want 0)"
say "mode:       $(jq -r '.permissions.defaultMode' "$SETTINGS")"

probe() {
  out=$(jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | "$HOOK")
  [ -z "$out" ] && echo PASS || jq -r '.hookSpecificOutput.permissionDecision' <<<"$out"
}
fail=0
for c in "git status" "pnpm install" "gh pr view 1" "npx tsc --noEmit"; do
  [ "$(probe "$c")" = PASS ] || { echo "  !! should PASS but did not: $c"; fail=1; }
done
for c in "rm -rf /" "git push --force origin main" "cat ~/.npmrc" "wrangler deploy"; do
  [ "$(probe "$c")" = deny ] || { echo "  !! should DENY but did not: $c"; fail=1; }
done
[ $fail -eq 0 ] && say "guard behaviour ✅ (4 pass / 4 deny)" || die "guard self-test FAILED"

echo
echo "== done =="
say "RESTART Claude Code - sandbox settings only apply at startup."
say "After restart, confirm egress is locked:"
say "    curl -s -o /dev/null -w '%{http_code}\\n' https://example.com   # want 000/403, not 200"
say "Revert anytime:  cp $SETTINGS.bak-$TS $SETTINGS"
