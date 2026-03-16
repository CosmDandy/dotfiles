---
name: implement
description: Execute an approved implementation plan step-by-step, running validation after each step and stopping on failure
---

# /implement — Execute Approved Plan

Execute the implementation plan: $ARGUMENTS

`$ARGUMENTS` should be a path to a plan file (e.g., `plans/2026-03-15-feature.md`).

## Rules

1. **Read the plan file first** — understand all steps before starting
2. **Execute ONLY what the plan describes** — no improvisation, no "improvements"
3. **Follow the exact order** specified in the plan
4. **Validate after each step** — run the validation command specified in the plan
5. **Stop on failure** — do NOT continue to next step if validation fails
6. **No architectural decisions** — the plan already made those

## Process

### For each step in the plan:

1. **Announce**: "Step N: <description>"
2. **Execute**: make the changes described
3. **Validate**: run the validation command from the plan
4. **Report**: result of validation (pass/fail)
5. If **fail**: stop, show error, suggest fix, wait for user
6. If **pass**: continue to next step

### After all steps complete:

1. Run the final validation from the plan's "Validation" section
2. Show `git diff --stat` summary of all changes
3. Show `git status` for the user
4. Suggest commit message in conventional commits format
5. **STOP** — user commits via lazygit

## Error Recovery

If a step fails:
- Show the exact error
- Attempt auto-fix if the fix is obvious (lint errors, formatting)
- If auto-fix works, re-run validation and continue
- If auto-fix fails, STOP and present the issue to user
- NEVER skip a failed step

## Guardrails

- Do NOT modify files not listed in the plan's "File Impact" section
- Do NOT add features not in the plan
- Do NOT refactor code that isn't part of the plan
- If the plan seems wrong or outdated, STOP and ask user
