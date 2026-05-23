# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Use What Exists

**Frameworks, algorithms, and this codebase have solved most problems already.**

Before writing:
- If the problem has a name (fairness, ranking, dedup, rate limiting, vector search), find the algorithm. Don't hand-roll it.
- If the framework has a primitive for it (loaders, actions, `useOptimistic`, `Suspense`), use the primitive. Don't reach for `useState`+`useEffect` or `useRevalidator` to patch around it.
- If this repo already does it (check `/models`, `/services`), use the existing function.

**Pick algorithms that collapse complexity, not ones that add prestige.** The right algorithm replaces hundreds of lines of growing edge cases with a small core of auditable math (see `models/fairness.ts` — Thompson sampling + M-table in ~200 lines replaces what would otherwise be an unbounded rule pile). The wrong algorithm is a 2000-line consensus protocol where a unique constraint would do.

A wrong implementation that looks right is the worst outcome. If you can't name the algorithm, find the primitive, or justify why this algorithm fits, stop and ask.

## 6. Commit Etiquette

**Match the repo's commit style. Never co-author.**

- Read `git log --oneline -5` before writing a commit message. Match the existing style (gitmoji shortcodes, unicode emoji, prefix conventions).
- Never add `Co-Authored-By: Claude` or any AI attribution line. The commit is the user's work.
- Never add "🤖 Generated with Claude Code" or similar trailers.
- One logical change per commit. Don't bundle unrelated edits.
- Commit only files you actually changed for the task. Review `git status` before `git add`.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
