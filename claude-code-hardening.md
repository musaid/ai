# Hardening Claude Code for Autonomous Use

A layered setup that lets Claude Code run with **minimal prompting** — auto-accept edits, auto-run
sandboxed Bash — **without significant risk to your codebase or device**. Tested on macOS 15
(Apple Silicon), Claude Code 2.1.x.

The config in this doc is a *template*. Some values are machine-specific (node-manager paths,
package-store paths, which credential dirs exist) and some are stack-specific (allowed domains, the
scripts you auto-run). **Don't paste it blindly — run the probe, adapt the marked bits, verify.**

---

## The mental model (read this first)

| Layer | What it is | What it protects |
|---|---|---|
| **1. Permission rules** (`permissions`) | *Policy* — what Claude *intends* to run | Reduces prompts; blocks obvious footguns |
| **2. Sandbox** (`sandbox`) | *Enforcement* — OS-level fs + network isolation | Your **device**; stops exfiltration |
| **3. git + checkpoints** | *Recovery* | Undo for anything that reaches your repo |

Three facts that drive every decision below:

1. **Permission rules match only the top-level command.** `pnpm run build` is allowlisted, but it
   spawns `node`, which spawns anything — none of it re-checked. A static allowlist **cannot** stop a
   poisoned build/postinstall/dependency script. Only the sandbox can.
2. **"Accept Edits" is not your risk surface.** `acceptEdits` mode auto-clears *file-edit* prompts
   only (edits are reversible via git). It does **not** auto-run Bash. The danger to your machine
   lives in shell execution, which Accept Edits never touches.
3. **Rule precedence: `deny` > `ask` > `allow` > mode default.** `deny` always wins, even in
   `acceptEdits`. This is why secret-file denies hold no matter how permissive the rest is.

**The payoff combo:** sandbox on + `autoAllowBashIfSandboxed` + default-deny network. The box
contains the blast radius, so you can safely *stop prompting for Bash* — real autonomy, because even
a hijacked subprocess is jailed and has nowhere to exfiltrate to.

---

## Layer 1 — permission rules

Design principles:

- **Gate by irreversibility, not fear.** Edits & local git = auto (reversible). Installs,
  interpreters, prod/deploy CLIs, DB clients = `ask`. Destructive/secret ops = `deny`.
- **Only named scripts auto-run.** `pnpm run test` yes; `pnpm install` / `dlx` / `exec` / `npx` /
  `node` / `tsx` → `ask` (that's where unvetted code enters).
- **Paths use `**/` not `./`.** In a *global* `~/.claude/settings.json`, a `./.env` rule anchors to
  your home dir and silently fails to match `~/projects/app/.env`. `**/.env` matches that file in any
  repo. Basename-anchor every path rule in a global file.
- **Deny the quiet persistence vectors:** `git config` (rewrites hooks/identity), `git reset --hard`
  / `git clean` (nuke worktree), `eval`, `rm -rf`, force-push.
- **`git checkout`:** allow only `git checkout -b *` and `git switch *`. Bare `git checkout <path>`
  discards uncommitted work, so let it fall through to a prompt.

---

## Layer 2 — sandbox

| Key | Value | Why |
|---|---|---|
| `enabled` | `true` | Every Bash subprocess runs in Seatbelt (macOS) / bubblewrap (Linux). |
| `failIfUnavailable` | `true` | If the sandbox can't start, Claude Code **exits** instead of silently running unprotected. Fail-closed. |
| `autoAllowBashIfSandboxed` | `true` | Stop prompting for Bash — the box is the safety net. This is what makes it autonomous. |
| `network.allowedDomains` | your hosts | **Default-deny egress. This is the real exfiltration control** — a script that reads a secret can't send it anywhere off-list. |
| `filesystem.allowWrite` | tool dirs | Node-manager + package-store + cache dirs *outside* the repo that your toolchain must write to (see probe). |
| `credentials.files` / `.envVars` | `deny` | Hard-block reading cloud creds your workflow doesn't use, and unset their env vars for subprocesses. |

Notes:
- Reads are broadly allowed by default; **writes and network are what's confined.** That's why you
  deny-read credentials explicitly, and why the domain allowlist matters more than anything.
- Claude Code auto-allows its own control-plane endpoints (the Anthropic API) — you don't list them.
- `ask` rules still gate commands that reach **beyond** the sandbox (prod deploys, remote DB). The
  sandbox doesn't protect Cloudflare/your DB — the human prompt does. Keep `wrangler`/`psql`/
  `git push` on `ask`. **Verify on first run that they still prompt.**
- Takes effect on the **next** Claude Code start, globally (all projects).

---

## Reproduce on a new machine

### 0. Prereqs
- macOS: Seatbelt is built in (`/usr/bin/sandbox-exec`). Nothing to install.
- Linux: install `bwrap` (bubblewrap) + `socat`; the sandbox needs them.
- Claude Code ≥ 2.x.

### 1. Probe the machine (paths differ per machine!)

```bash
echo "== os ==";        sw_vers 2>/dev/null; uname -s
echo "== seatbelt ==";  which sandbox-exec || echo "linux: need bwrap+socat"
echo "== claude ==";    claude --version
echo "== tools ==";     for t in node pnpm npm yarn bun git gh psql wrangler; do printf '%s: ' "$t"; which "$t" 2>/dev/null || echo '(absent)'; done
echo "== node mgr ==";  ls -d ~/.local/state/fnm_multishells ~/.nvm ~/.volta ~/.asdf ~/.local/share/mise 2>/dev/null
echo "== pkg store ==";  pnpm store path 2>/dev/null; npm config get cache 2>/dev/null; ls -d ~/Library/pnpm ~/.cache ~/.npm ~/.bun 2>/dev/null
echo "== cred dirs ==";  ls -d ~/.aws ~/.config/gcloud ~/.azure ~/.ssh ~/.config/gh ~/.kube ~/.docker 2>/dev/null
```

### 2. Adapt the marked bits from the probe output
- **`allowWrite`** ← your node-manager's per-shell write dir + package store/cache.
  Examples: fnm → `~/.local/state/fnm_multishells`; volta → `~/.volta`; asdf → `~/.asdf/shims`;
  pnpm → `~/Library/pnpm` (macOS) or `~/.local/share/pnpm` (Linux); plus `~/.cache`, `~/.npm`.
  **If you skip your node manager's write path, the sandbox blocks its per-shell init and node/pnpm
  vanish from `PATH` — the whole toolchain breaks.**
- **`credentials` deny** ← cred dirs the probe found that your stack doesn't use (e.g. `~/.aws`,
  `~/.config/gcloud` on a Cloudflare project). Pure attack-surface removal, zero cost.
- **`network.allowedDomains`** ← your package registry, git host, cloud provider, doc sites, and any
  **remote DB host** you `psql` into.
- **`allow` / `ask`** ← your project's real `package.json` scripts (allow) and your deploy/DB CLIs (ask).

### 3. Merge into `~/.claude/settings.json`
Preserve existing top-level keys (`model`, etc.) and merge arrays — don't replace the file.

### 4. Validate
```bash
python3 -c "import json,sys; json.load(open(sys.argv[1])); print('valid JSON')" ~/.claude/settings.json
```

### 5. First-run verification (do once, in a fresh session)
1. **Launches?** If Claude Code refuses to start, the sandbox failed — set `failIfUnavailable:false`
   temporarily and run `/sandbox` to diagnose.
2. **Toolchain survived?** Have it run `node -v` / `pnpm run typecheck`. "Not found" → your node
   manager needs another `allowWrite` path.
3. **Prod still gated?** First `git push` / `wrangler` / `psql` must still **prompt**. If one
   auto-runs, move it firmly into `ask` (or `deny`) and re-check.
4. **Egress locked?** A blocked domain shows a clear network denial (not a hang). Add legit hosts as
   you hit them — default-deny makes the blocks informative, not fatal.

---

## The config (template — adapt the `# ← marked` bits)

```jsonc
{
  // ... your existing top-level keys (model, includeCoAuthoredBy, ...) stay here ...
  "permissions": {
    "defaultMode": "default",
    "allow": [
      "Edit", "Write",
      // ← your real package.json scripts:
      "Bash(pnpm run typecheck)", "Bash(pnpm run lint)", "Bash(pnpm run lint:*)",
      "Bash(pnpm run test)", "Bash(pnpm run test:*)", "Bash(pnpm run build)", "Bash(pnpm run dev)",
      // local, reversible git:
      "Bash(git add *)", "Bash(git commit *)", "Bash(git checkout -b *)", "Bash(git switch *)",
      "Bash(git branch *)", "Bash(git stash *)",
      // ← doc sites you trust:
      "WebFetch(domain:developer.mozilla.org)", "WebFetch(domain:*.github.com)",
      "WebFetch(domain:docs.claude.com)", "WebFetch(domain:developers.cloudflare.com)",
      "WebFetch(domain:reactrouter.com)"
    ],
    "ask": [
      // code entry points — never blanket-allow:
      "Bash(pnpm install*)", "Bash(pnpm add *)", "Bash(pnpm update *)", "Bash(pnpm dlx *)",
      "Bash(pnpm exec *)", "Bash(npx *)", "Bash(node *)", "Bash(tsx *)",
      // destructive-to-worktree + remote git:
      "Bash(git checkout -- *)", "Bash(git push *)", "Bash(git fetch *)", "Bash(git pull *)",
      "Bash(git remote *)", "Bash(git merge *)", "Bash(git rebase *)", "Bash(gh *)",
      // ← reaches prod / beyond the sandbox:
      "Bash(wrangler *)", "Bash(curl *)", "Bash(wget *)", "Bash(ssh *)", "Bash(scp *)", "Bash(psql *)",
      // sensitive edits (basename-anchored for global scope):
      "Edit(**/migrations/**)", "Edit(**/schema.prisma)", "Edit(**/wrangler.toml)",
      "Edit(**/wrangler.jsonc)", "Edit(**/package.json)", "Edit(**/.github/**)"
    ],
    "deny": [
      "Bash(rm -rf *)", "Bash(git reset --hard *)", "Bash(git push --force *)", "Bash(git push -f *)",
      "Bash(git clean *)", "Bash(git config *)", "Bash(eval *)",
      "Read(**/.env)", "Read(**/.env.*)", "Read(**/.dev.vars)", "Read(**/.dev.vars.*)",
      "Read(**/secrets/**)", "Edit(**/.env*)", "Edit(**/.dev.vars*)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "autoAllowBashIfSandboxed": true,
    "network": {
      "allowedDomains": [                 // ← default-deny; list only what you need
        "github.com", "*.github.com", "*.githubusercontent.com",
        "registry.npmjs.org", "*.cloudflare.com", "binaries.prisma.sh",
        "developer.mozilla.org", "docs.claude.com", "developers.cloudflare.com", "reactrouter.com"
      ]
    },
    "filesystem": {
      "allowWrite": [                      // ← from probe: node mgr + pkg store + caches
        "~/Library/pnpm", "~/.local/state/fnm_multishells", "~/.cache", "~/.npm"
      ]
    },
    "credentials": {
      "files": [                           // ← cred dirs your stack does NOT use
        { "path": "~/.aws", "mode": "deny" },
        { "path": "~/.config/gcloud", "mode": "deny" }
      ],
      "envVars": [
        { "name": "AWS_ACCESS_KEY_ID", "mode": "deny" },
        { "name": "AWS_SECRET_ACCESS_KEY", "mode": "deny" },
        { "name": "AWS_SESSION_TOKEN", "mode": "deny" },
        { "name": "GOOGLE_APPLICATION_CREDENTIALS", "mode": "deny" }
      ]
    }
  }
}
```
> `settings.json` is strict JSON — the `//` comments above are for reading only; strip them in the real file.

---

## Residual risks (know these)

- **Allowlisted egress is still egress.** `*.cloudflare.com` is open for your app, so a subprocess
  holding `CLOUDFLARE_API_TOKEN` in its env could reach prod. Mitigation: keep `wrangler` on `ask`;
  optionally deny `CLOUDFLARE_API_TOKEN` as an env var if you only deploy by hand.
- **Prompt injection.** Claude reading a malicious file/page/issue can be told to run an allowlisted
  command. The sandbox contains the *consequence*; it can't stop the *attempt*. Default-deny egress +
  `ask` on prod is what keeps this cheap.
- **In-repo damage.** Claude can still write bad code or make bad commits. git + `/rewind` file
  checkpointing (`"fileCheckpointingEnabled": true`) is the undo.
- **`~/.ssh` left readable** so SSH `git push` works. If you push over HTTPS only, deny it too.
- **Zero risk is not on the table** for an autonomous agent that holds prod credentials. The goal is
  *small, bounded* risk — which this achieves.

---

## Recap: what each piece buys you

- **Permission rules** → fewer prompts + blocks obvious footguns. *Policy.*
- **Sandbox fs/network** → device safety + no exfiltration. *Enforcement.*
- **`autoAllowBashIfSandboxed`** → the autonomy actually materializes, safely.
- **`ask` on prod/DB** → human gate where the sandbox can't reach.
- **git + checkpoints** → recovery for the rest.
