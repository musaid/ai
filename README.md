# ai

Behavioral guidelines I give Claude (and other coding LLMs) across my projects. Compact, opinionated, evolved through real use on production codebases.

The whole thing is in [CLAUDE.md](./CLAUDE.md).

## Why this exists

LLMs make consistent classes of mistakes when writing code: assuming instead of asking, over-engineering simple problems, "improving" code you didn't ask them to touch, declaring victory without verifying, reinventing solved problems, and fighting frameworks instead of using them.

This file is a small set of rules — five sections, well under 500 words — that head off those failures at the prompt level. It's deliberately short. Long instructions degrade output quality; the rules in the middle get skipped.

## How to use it

Drop `CLAUDE.md` at the root of your repo (or a parent directory). Claude Code reads it automatically. For other tools, paste it into your system prompt or rules file.

Each project can add its own project-specific `CLAUDE.md` on top — env vars, commands, schema notes — and reference this one as the base.

## Also here

[**claude-code-hardening.md**](./claude-code-hardening.md) — running Claude Code with minimal prompting without giving up the red lines (no credential theft, no irrecoverable deletion, no production, no rewriting shared history). Measured against 12,239 real commands: **32.7 → 1.41 interruptions per session**, every remaining stop intentional.

The approach inverts the usual one: instead of enumerating thousands of safe commands, allow Bash broadly and put one smart gate in front of it — [`claude-guard.sh`](./claude-guard.sh), installed by [`install-claude-guard.sh`](./install-claude-guard.sh). A hook can tell `psql -h localhost` from `psql -h prod-db`; a prefix glob can't.

> **If you followed an earlier version of the hardening doc, read the v2 corrections.** `network.allowedDomains` does *not* restrict Bash egress without `strictAllowlist: true` — verified by reaching arbitrary hosts through a configured allowlist. Assume you have had open egress.

## License

MIT. Copy, fork, adapt. If a rule earns its place in your workflow, that's the point.
