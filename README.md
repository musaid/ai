# ai

Behavioral guidelines I give Claude (and other coding LLMs) across my projects. Compact, opinionated, evolved through real use on production codebases.

The whole thing is in [CLAUDE.md](./CLAUDE.md).

## Why this exists

LLMs make consistent classes of mistakes when writing code: assuming instead of asking, over-engineering simple problems, "improving" code you didn't ask them to touch, declaring victory without verifying, reinventing solved problems, fighting frameworks instead of using them, and burying the answer in preamble and recap.

This file is a small set of rules — seven sections, under 900 words — that head off those failures at the prompt level. It stays short, but the real limit is the number of rules, not the word count: adherence degrades as constraints pile up, and unresolved conflicts between rules cost more than length. Where two rules pull against each other, the file says which wins.

## How to use it

Drop `CLAUDE.md` at the root of your repo (or a parent directory). Claude Code reads it automatically. For other tools, paste it into your system prompt or rules file.

Each project can add its own project-specific `CLAUDE.md` on top — env vars, commands, schema notes — and reference this one as the base.

## Also here

[**claude-code-hardening.md**](./claude-code-hardening.md) — running Claude Code with minimal prompting without giving up the red lines (no credential theft, no irrecoverable deletion, no production, no rewriting shared history). Measured against 12,239 real commands: **32.7 → 1.41 interruptions per session**, every remaining stop intentional.

The approach inverts the usual one: instead of enumerating thousands of safe commands, allow Bash broadly and put one smart gate in front of it — [`claude-guard.sh`](./claude-guard.sh), installed by [`install-claude-guard.sh`](./install-claude-guard.sh). A hook can tell `psql -h localhost` from `psql -h prod-db`; a prefix glob can't.

> **If you followed an earlier version of the hardening doc, read the v2 corrections.** `network.allowedDomains` does *not* restrict Bash egress without `strictAllowlist: true` — verified by reaching arbitrary hosts through a configured allowlist. Assume you have had open egress.

[**agents/lean-reviewer.md**](./agents/lean-reviewer.md) — §7 applied to code review: findings only, worst first, one `file:line` block each. No summary preamble, no "positive observations", no closing recap of the findings above it. Copy it to `~/.claude/agents/` to get it in every project.

It is deliberately *not* named `code-reviewer`. Project subagents (`.claude/agents/`, priority 3) shadow user ones (`~/.claude/agents/`, priority 4) with the same name, so a repo that already ships a `code-reviewer` would silently win. A distinct name works everywhere.

## License

MIT. Copy, fork, adapt. If a rule earns its place in your workflow, that's the point.
