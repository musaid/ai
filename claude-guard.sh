#!/bin/bash
# claude-guard.sh — PreToolUse chokepoint for Claude Code.
#
# Design: settings.json allows Bash broadly (no prompts). This hook is the only
# thing that says no, and it says no with real logic instead of prefix globs.
# Docs: "A blocking hook also takes precedence over allow rules."
#
# v2 — evaluates each SHELL SEGMENT independently. v1 matched patterns against
# the whole command string, which denied `env-cmd -f ../../.env` as a force-push
# (a stray `-f`) and denied any command that merely mentioned .env. Verified
# against 12,216 real commands: v1 produced 3.5 bogus denials/session.
#
# NOT covered here, by design: .env reads. The OS-level `Read(**/.env*)` deny is
# strictly stronger — verified to block node/python/subprocess reads with EPERM.
# Duplicating it in regex only created false positives.

set -uo pipefail

# PRIMARY control ⇒ must FAIL CLOSED.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
_bail() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}
command -v jq >/dev/null 2>&1 || _bail "claude-guard could not run (jq not found) - failing closed."

input=$(cat)
[[ -z "$input" ]] && exit 0
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || _bail "claude-guard could not parse the tool call - failing closed."
[[ "$tool" != "Bash" ]] && exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || _bail "claude-guard could not parse the command - failing closed."
[[ -z "$cmd" ]] && exit 0

deny() { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
ask()  { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}';  exit 0; }

SECRET_PATH='(\.npmrc|\.netrc|id_rsa|id_ed25519|\.ssh/|/\.aws/|\.config/gcloud|\.config/gh/hosts)'

# Split into segments on shell operators. Deliberately conservative: we only
# need command boundaries, so quoting subtleties can't hide a dangerous verb.
segments=$(printf '%s' "$cmd" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|]/\n/g')

while IFS= read -r seg; do
  s=$(printf '%s' "$seg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s ' ')
  [[ -z "$s" ]] && continue

  # Strip leading env assignments and benign wrappers to find the real verb.
  while [[ "$s" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*)$ ]]; do s="${BASH_REMATCH[1]}"; done
  while [[ "$s" =~ ^(sudo|command|builtin|nohup|time|nice|stdbuf|timeout[[:space:]]+[0-9smh]+)[[:space:]]+(.*)$ ]]; do s="${BASH_REMATCH[2]}"; done
  verb=${s%% *}; verb=${verb##*/}
  rest=" ${s#"$verb"} "

  case "$verb" in

  rm)
    # ORDER: absolute red lines before the generic recursive ask.
    [[ "$rest" =~ [[:space:]](/|~|\$HOME|\$\{HOME\}|/\*|~/\*|\.)[[:space:]] ]] && \
      deny "Refusing to delete filesystem root, home, or cwd."
    # Regenerable artifacts are not data loss. Whole path COMPONENTS only —
    # a substring test would let `rm -rf ~/node_modules_backup` through.
    _all=1; _seen=0
    for a in $rest; do
      [[ "$a" == -* ]] && continue
      _seen=1; b=${a%/}; b=${b##*/}
      case "$b" in
        node_modules|dist|build|coverage|.next|.turbo|.cache|.parcel-cache|out|.svelte-kit|.nuxt|tsconfig.tsbuildinfo) ;;
        *) _all=0 ;;
      esac
    done
    [[ $_seen -eq 1 && $_all -eq 1 ]] && continue
    [[ "$rest" =~ [[:space:]]-[a-zA-Z]*r ]] && ask "Recursive delete. Confirm the target path."
    ;;

  git)
    sub=$(printf '%s' "$rest" | sed -e 's/^ *//' -e 's/^-[^ ]* *//' -e 's/^-[^ ]* *//'); sub=${sub%% *}
    case "$sub" in
      push)
        [[ "$rest" =~ --force-with-lease ]] && \
          ask "force-with-lease rewrites branch history (safely - aborts if the remote moved). Confirm."
        [[ "$rest" =~ --force([^-]|$) || "$rest" =~ [[:space:]]-f[[:space:]] || "$rest" =~ [[:space:]]\+[A-Za-z] ]] && \
          deny "Unconditional force-push blocked (red line). Use --force-with-lease, or run it yourself."
        [[ "$rest" =~ --delete|--mirror ]] && deny "Remote branch deletion blocked (irrecoverable shared state)."
        [[ "$rest" =~ [[:space:]](main|master|production|prod|release)[[:space:]] ]] && \
          ask "Push targets a protected branch. Confirm this is intended."
        ;;
      reset)   [[ "$rest" =~ --hard ]] && ask "git reset --hard discards uncommitted work. Confirm." ;;
      clean)   [[ "$rest" =~ [[:space:]]-[a-zA-Z]*[fx] ]] && ask "git clean deletes untracked files irrecoverably." ;;
      branch)  [[ "$rest" =~ [[:space:]]-D ]] && ask "Force branch delete - unmerged commits may be lost." ;;
      reflog)  [[ "$rest" =~ expire ]] && deny "Reflog expiry destroys the recovery net." ;;
      gc)      [[ "$rest" =~ --prune=now ]] && deny "Aggressive gc destroys the recovery net." ;;
      filter-branch|filter-repo) deny "History rewrite blocked." ;;
      update-ref) [[ "$rest" =~ [[:space:]]-d ]] && deny "Direct ref deletion blocked." ;;
      show|cat-file|archive|grep|diff|log)
        # Read-denies protect PATHS; the git object store is a different path,
        # so `git show HEAD:.env.prod` reads straight past them. Verified bypass.
        [[ "$rest" =~ (\.env|\.dev\.vars)([^a-zA-Z/]|$) || "$rest" =~ $SECRET_PATH ]] && \
          deny "Reading credential material out of the git object store is blocked."
        ;;
    esac
    ;;

  psql|pg_dump|pg_restore|mysql|mongo|redis-cli)
    if [[ "$rest" =~ (-h|--host)[[:space:]=]*([^[:space:]]+) ]]; then
      host="${BASH_REMATCH[2]}"
      [[ "$host" =~ ^(localhost|127\.0\.0\.1|::1|0\.0\.0\.0|host\.docker\.internal)$ ]] || \
        deny "Database connection to non-local host '$host' is treated as production."
    fi
    [[ "$rest" =~ (DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE) ]] && \
      ask "Destructive SQL detected. Confirm the target database."
    ;;

  wrangler)
    [[ "$rest" =~ [[:space:]](deploy|publish)([[:space:]]|$) ]] && deny "wrangler deploy touches production."
    [[ "$rest" =~ --remote ]] && deny "wrangler --remote touches production data."
    [[ "$rest" =~ [[:space:]]secret([[:space:]]|$) ]] && deny "wrangler secret management blocked."
    ;;

  gh)
    [[ "$rest" =~ ^[[:space:]]*repo[[:space:]]+delete ]] && deny "Repository deletion blocked."
    [[ "$rest" =~ ^[[:space:]]*secret ]] && deny "GitHub secret management blocked."
    [[ "$rest" =~ ^[[:space:]]*auth[[:space:]]+token ]] && deny "Printing the GitHub token is blocked."
    [[ "$rest" =~ -X[[:space:]]*(DELETE|PUT|PATCH) ]] && ask "Mutating GitHub API call. Confirm."
    [[ "$rest" =~ ^[[:space:]]*(pr[[:space:]]+merge|release[[:space:]]+delete) ]] && ask "Shared-state change on GitHub. Confirm."
    ;;

  npx|bunx|pnpm|yarn)
    _args=$rest
    [[ "$verb" == pnpm || "$verb" == yarn ]] && { [[ "$rest" =~ [[:space:]]dlx[[:space:]] ]] || continue; _args=${rest#* dlx }; }
    pkg=""
    for w in $_args; do [[ "$w" == -* ]] && continue; pkg=$w; break; done
    case "${pkg##*/}" in
      tsc|typescript|eslint|prettier|vitest|jest|only-allow|playwright|tsx|turbo|changeset|env-cmd|\
      prisma|drizzle-kit|vite|next|nx|ts-node|dotenv|npm-check-updates|depcheck|serve|http-server|"") ;;
      *) ask "npx/dlx will download and execute '$pkg' from the registry. Confirm it is the package you expect." ;;
    esac
    ;;

  shred|srm)  deny "Secure-erase blocked (irrecoverable by design)." ;;
  dd)         [[ "$rest" =~ of= ]] && deny "Raw disk write blocked." ;;
  find)
    [[ "$rest" =~ -delete ]] && ask "find -delete performs bulk irrecoverable deletion."
    [[ "$rest" =~ -exec[[:space:]]+rm ]] && ask "find -exec rm performs bulk irrecoverable deletion."
    ;;

  cat|less|more|head|tail|bat|xxd|od|strings|base64|cp|scp|rsync|nl)
    # .env deliberately omitted: the OS-level Read deny already blocks it for
    # every process, and matching it here only produced false positives.
    [[ "$rest" =~ $SECRET_PATH ]] && deny "Reading credential material via shell is blocked."
    ;;

  env)
    [[ "$rest" =~ ^[[:space:]]*$ ]] && ask "Dumping the full environment can expose tokens."
    ;;

  esac
done <<< "$segments"

# Safety net: `npx dotenv -- bash -c 'psql ... DROP TABLE'` hides the verb inside
# a quoted string, invisible to segment parsing. Only patterns with near-zero
# false-positive risk belong here.
[[ "$cmd" =~ (DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+(TABLE|[A-Za-z_\"])) ]] && \
  ask "Destructive SQL appears in this command. Confirm the target database."

exit 0
