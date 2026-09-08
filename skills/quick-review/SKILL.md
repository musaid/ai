---
name: quick-review
description: Quick, lean PR review that reports at most three verified, must-fix findings — the lightweight counterpart to a full multi-agent adversarial review. Use when asked to review a PR (number or URL), a branch, or the current diff and the reader wants only blocking issues, not a full audit.
---

# Quick review

Review the target diff (`gh pr diff <n>` for a PR number; `git diff <base>...HEAD` for a branch; `git diff` for the working tree). Read the PR/ticket description first — the review judges the diff against the problem it claims to solve.

Report **at most three findings**, and only ones that pass all four gates:

1. **A user or teammate actually hits it** — a defect that ships, or the PR's own claim not holding (the bug it says it fixes still reproducing through some path). Name the concrete input or state that triggers it; if you can't, it's not a finding.
2. **Judge the approach against the problem, not against alternatives.** Challenge it when it fails on the merits: wrong root cause, complexity the problem doesn't require, re-implementing what the codebase already has, breaking its conventions. If both the current approach and yours solve the problem, the one in the code wins — a lateral swap is never a finding, no matter who or what wrote the code.
3. **It's in the diff's blast radius** — code the diff adds, changes, or makes false (a comment, a changeset claim). Pre-existing issues nearby get one closing line as ticket suggestions, never findings.
4. **It survives verification** — confirmed against real callers, real library source, and the full enclosing functions (not just the hunks). Say plainly when a failure mode is inferred rather than demonstrated.

## Output

Each finding is **at most three sentences**: `file:line`, what breaks and the trigger, the fix. Worst first. No preamble, no methodology, no summary of what was reviewed, no restating findings in a conclusion.

Earlier review rounds are settled; re-open a decision only for a new fact, never a preference. Zero findings is a valid, complete review: say "no blocking issues" and stop.

Only post to the PR when explicitly asked; the default deliverable is the findings in the conversation.
