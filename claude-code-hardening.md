# Hardening Claude Code for Autonomous Use

A setup that lets Claude Code run with **minimal prompting** — no `ask` list, Bash allowed broadly —
**without giving up the red lines**: no credential theft, no irrecoverable deletion, no production,
no rewriting shared history.

Tested on macOS 15 (Apple Silicon), Claude Code 2.1.160. Measured against **12,239 real commands
across 51 sessions**: **32.7 → 1.41 interruptions per session**, with every remaining stop intentional.

Two files implement it: [`claude-guard.sh`](./claude-guard.sh) (the enforcement point) and
[`install-claude-guard.sh`](./install-claude-guard.sh) (portable installer — merges into existing
settings, backs up first, self-tests).

```bash
./install-claude-guard.sh ~/your/code/root
```

---

## v2 — three corrections to the previous version of this doc

The earlier revision of this file was wrong about things that matter. All three were caught by
measuring rather than reasoning.

**1. `network.allowedDomains` does not restrict Bash egress on its own.** The old doc called it
"the real exfiltration control" and claimed a hijacked subprocess "has nowhere to exfiltrate to."
Verified false — with a 12-domain allowlist configured:

```
curl https://example.com   -> 200, real <title>Example Domain</title>
curl https://pastebin.com  -> 200, real body
POST https://httpbin.org/post -> 200
```

The sandbox proxy issues CONNECT tunnels to arbitrary hosts. **The fix is
`sandbox.network.strictAllowlist: true`** — *"deterministically denies hosts not in allowedDomains
instead of prompting."* Without that key the list is decorative. If your config predates this,
assume you have had open egress.

**2. A long `ask` list is the main source of prompts, and it defeats the sandbox.** `ask` outranks
`autoAllowBashIfSandboxed`, and it outranks narrower `allow` rules — the docs are explicit: *"a
matching ask rule prompts even when a more specific allow rule also matches the same call."* In the
measured corpus the old `ask` list caused **73% of all prompts, of which 87% were read-only**
(`gh pr view`, `npx tsc`, `pnpm exec eslint`). The design principle "only named scripts auto-run"
sounds prudent and costs ~24 prompts/session for almost no security.

**3. `deny` globs override a PreToolUse hook and cancel its precision.** Deny is evaluated
regardless of what a hook returns. Keeping `Bash(rm -rf *)` "as belt and braces" alongside the guard
hard-blocked `rm -rf node_modules`, which the guard deliberately allows. If you use the hook, remove
Bash deny globs — the hook is strictly more precise.

Smaller corrections: `Bash(pnpm run typecheck)`-style rules matched **zero** of 12,239 commands
(real invocations are `pnpm type-check`, `pnpm --filter <pkg> build`); `Bash(git config *)` in deny
blocks read-only `--get`/`--list` and is trivially bypassed by `git -c` / `git -C`; and leaving
`~/.ssh` readable "so SSH push works" buys nothing, because **SSH git does not work in the sandbox
at all** (see below).

---

## The mental model

| Layer | What it is | What it actually protects |
|---|---|---|
| **1. PreToolUse hook** | *Enforcement* — inspects each command with real logic | The red lines. This is the only layer that can tell `psql -h localhost` from `psql -h prod-db` |
| **2. Sandbox** | *Containment* — OS-level fs + network isolation | Your device — **but only if `strictAllowlist` is set** |
| **3. `Read`/`Edit` denies** | *OS-level secret protection* | `.env` files, against every process — not just Claude's tools |
| **4. git** | *Recovery* | Anything that reaches your repo |

The inversion that makes this work: **stop enumerating safe commands; allow Bash and put one smart
gate in front.** The official docs prescribe exactly this:

> "To run all Bash commands without prompts except for a few you want blocked, add `"Bash"` to your
> allow list and register a PreToolUse hook that rejects those specific commands."

A hook can do what prefix globs fundamentally cannot: parse each shell segment, distinguish a local
database from a production one, tell `git push feat/x` from `git push origin +main`, and allow
`rm -rf node_modules` while refusing `rm -rf ~`. It also **cannot be undone by accumulated
"yes, don't ask again" clicks** — hooks outrank allow rules, so the permission file can't grow holes
over time.

### What the `Read` deny actually buys (better than documented)

`Read(**/.env)` propagates to the OS sandbox and blocks **arbitrary subprocesses**, not just
Claude's file tools:

```
node   readFileSync('.env')  -> EPERM
python open('.env')          -> PermissionError
cat / grep / cp              -> Operation not permitted
```

That is genuinely strong — it survives a poisoned build script. Two caveats: it is **path**-based,
so `git show HEAD:.env.prod` reads the same secret out of the object store untouched (the guard
closes this), and it only helps for paths you can afford to deny — `~/.npmrc` must stay readable or
`pnpm install` breaks, so the guard blocks *shell reads* of it while leaving pnpm's access intact.

---

## Three things the sandbox breaks (and the fixes)

These cost more prompts than any permission rule, because each failure escalates to an unsandboxed
retry that goes through the permission gate.

**SSH git — 100% broken.** The sandbox sets
`GIT_SSH_COMMAND=ssh -o ProxyCommand='nc -X 5 -x localhost:PORT %h %p'`, but the proxy requires auth
and `nc` cannot supply it:

```
nc: authentication method negotiation failed
```

Git over **HTTPS works fine** through the same proxy. Fix without touching your `~/.gitconfig` —
scope the rewrite to Claude Code via `env`:

```json
"env": {
  "GIT_CONFIG_COUNT": "1",
  "GIT_CONFIG_KEY_0": "url.https://github.com/.insteadOf",
  "GIT_CONFIG_VALUE_0": "git@github.com:"
}
```

**`gh` — 100% broken.** `tls: failed to verify certificate: x509: OSStatus -26276`. Go's darwin x509
verifier needs the `com.apple.trustd` Mach service, which Seatbelt denies. Every `gh` call fails,
and `gh auth status` misreports the token as invalid, sending you down a pointless re-auth path.
Fix: `sandbox.enableWeakerNetworkIsolation: true`. The docs flag it as reducing security; the
alternative is running `gh` entirely outside the sandbox, which is worse.

**Sibling repos are read-only.** `allowWrite: ["."]` covers only the launch directory. Add your code
root to both `permissions.additionalDirectories` and `sandbox.filesystem.allowWrite`, or every edit
in another repo escalates. Also add `~/Library/Caches` (macOS) — Playwright, esbuild and node-gyp
write there.

---

## What the guard enforces

| Verdict | Examples |
|---|---|
| **deny** | `rm -rf /` · `rm -rf ~` · `git push --force` / `-f` / `+main` · `git push --delete` · `reflog expire` · `gc --prune=now` · `filter-branch` · `psql -h <non-local>` · `wrangler deploy` / `--remote` · `gh repo delete` · `gh auth token` · `cat ~/.npmrc` · `git show HEAD:.env.prod` · `shred` · `dd of=` |
| **ask** | `--force-with-lease` · push to `main` · `git reset --hard` · `git clean -fd` · `rm -rf <anything not a build artifact>` · `npx <unknown package>` · `DROP TABLE` / `TRUNCATE` · `find -delete` |
| **pass** | everything else — including `git fetch/pull/push feat/x`, `gh pr view/diff/checkout`, `pnpm install`, `pnpm --filter X build`, `npx tsc/eslint/prettier`, `rm -rf node_modules` |

Design notes worth knowing before you edit it:

- **Per-segment evaluation.** Splitting on `&&`/`||`/`;`/`|` is not cosmetic. Matching the whole
  command string denied `pnpm exec env-cmd -f ../../.env ts-node` as a *force-push* — a stray `-f`
  three tokens away from an unrelated `git` mention. Whole-string matching produced 3.5 bogus
  denials per session.
- **Build artifacts are matched by path component, not substring.** A substring test lets
  `rm -rf ~/node_modules_backup_important` through.
- **Fails closed.** No `jq`, or unparseable input, returns `ask` — never silent approval.
- **`--force-with-lease` asks rather than denies.** It is the safe force-push and people genuinely
  use it; a hard block just sends them to a terminal.
- **Cost:** ~36 ms per command (133 ms for a pathological 25-segment chain).

---

## Reproduce on a new machine

`install-claude-guard.sh` handles the machine-specific parts — code roots are arguments (or probed
from `~/work`, `~/code`, `~/src`, `~/dev`, `~/projects`, `~/repos`, `~/Developer`), cache paths
switch on `uname`, and the guard's `PATH` covers Apple Silicon, Intel, and Linux. It merges into
existing settings (your `model`, plugins, MCP config and your own hooks survive), backs up first,
and aborts if its own 4-pass/4-deny self-test fails.

```bash
./install-claude-guard.sh ~/code
# then RESTART Claude Code — sandbox settings only apply at startup
curl -s -o /dev/null -w '%{http_code}\n' https://example.com   # want 000/403, not 200
```

Linux needs `bwrap` + `socat`; both platforms need `jq` (the guard fails closed without it, which
would turn every command into a prompt).

That last `curl` is the important one. **Verify it rather than trusting it** — that is the single
check the previous version of this doc got wrong.

---

## Residual risks

- **A permissions config cannot stop a malicious dependency.** The guard inspects command strings
  Claude submits; it has zero visibility into what `pnpm install` then executes. What actually helps:
  pnpm 10+ blocks dependency build scripts by default (check yours with `pnpm ignored-builds` — keep
  `onlyBuiltDependencies` short, it is your attack surface), and the OS-level `.env` read-deny.
  The guard adds an `npx <unknown package>` gate, since `npx` executes registry code with no such
  protection.
- **`~/.npmrc` holds plaintext tokens and must stay readable** for installs to work. The guard blocks
  shell reads of it, but any process that runs can read it. Scope those tokens to the minimum
  (`read:packages`) and rotate them.
- **`ask` may not prompt inside subagents.** Reported during this work but not confirmed in a main
  session; if true, `ask` was never a security boundary for delegated work — another reason
  enforcement belongs in the hook.
- **Prompt injection.** Claude reading a malicious PR diff or issue can be *told* to run something.
  The guard is what makes the attempt cheap; it is the layer that matters for this threat.
- **Zero risk is not on the table** for an autonomous agent with credentials on the box. The goal is
  small, bounded, and *measured* risk.
