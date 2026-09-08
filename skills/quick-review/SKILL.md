---
name: quick-review
description: Quick, lean PR review that reports at most three verified, must-fix findings — the lightweight counterpart to a full multi-agent adversarial review. Use when asked to review a PR (number or URL), a branch, or the current diff and the reader wants only blocking issues, not a full audit.
---

# Quick review

Establish the exact scope first: `gh pr diff <n>` for a PR number; for a branch, resolve the base explicitly (`git merge-base <default-branch> HEAD`) and diff `<base>...HEAD`; for local work, `git diff HEAD` so staged changes are included. Read the PR/ticket description — the review judges the diff against the problem it claims to solve — and read any existing review threads before treating earlier rounds as settled.

Report **at most three findings**, and only ones that pass all four gates:

1. **A user or teammate actually hits it** — incorrect behavior, a security gap, a material performance regression, or a broken compatibility contract that ships, or the PR's own claim not holding (the bug it says it fixes still reproducing through some path). Name the concrete input or state that triggers it; if you can't, it's not a finding.
2. **Judge the approach against the problem, not against alternatives.** Wrong root causes, unnecessary complexity, duplicated mechanisms, and convention violations are findings only when they cause a concrete blocking defect. If both approaches satisfy the requirements, the one in the code wins — a lateral swap is never a finding, no matter who or what wrote the code.
3. **It's in the diff's blast radius** — code the diff adds, changes, or makes false (a comment, a changeset claim). Pre-existing defects noticed in passing are not findings: at most one closing line may hand them off as follow-up tickets, and only when they would pass gate 1 themselves — never for conventions or cleanup.
4. **It survives verification** — confirmed against real callers, real library source, and the full enclosing functions (not just the hunks). A finding need not be reproduced, but an inferred one must have a confirmed trigger and a traceable execution path; merely plausible failure modes are omitted. Say plainly when a failure mode is inferred rather than demonstrated.

## Output

Each finding is **at most three sentences**: `file:line`; what breaks and the trigger; the required correction, or a minimal fix when one is clear. Worst first. No preamble, no methodology, no summary of what was reviewed, no restating findings in a conclusion.

Earlier review rounds are settled; re-open a decision only for a new fact, never a preference. Zero findings is a valid, complete review: say "no blocking issues" and stop.

Only post to the PR when explicitly asked; the default deliverable is the findings in the conversation.
