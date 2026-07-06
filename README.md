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

[**claude-code-hardening.md**](./claude-code-hardening.md) — a layered setup for running Claude Code with minimal prompting (auto-accept edits, auto-run sandboxed Bash) without significant risk to your codebase or device. Permission rules as policy, the OS sandbox as enforcement, git as recovery — plus a probe-and-adapt process to reproduce it on any machine.

## License

MIT. Copy, fork, adapt. If a rule earns its place in your workflow, that's the point.
