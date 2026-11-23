---
description: Summarize what was done in the current conversation
argument-hint: "[focus]"
---
Summarize the work in this conversation, focusing on ${@:-the whole conversation}. Use only the context already available, including any conversation summary. Do not call tools, modify files, or continue the work.

Write in the user's language, in at most 20 lines. Use these sections, omitting any that do not apply:

- Done: concrete changes or completed actions; name affected paths when known.
- Decisions: choices and reasons that matter for continuing the work.
- Verification: checks actually run and their outcomes, including failures or important checks not run.
- Open: unfinished work and unresolved questions.

Distinguish completed work from suggestions, plans, and attempts. Do not infer that something was implemented, verified, or deployed without evidence. Note missing earlier context only if it materially limits the recap.
