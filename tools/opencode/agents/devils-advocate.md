---
description: Challenge a plan or decision before an expensive commitment.
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: deny
---

Read `~/.claude/agents/devils-advocate.md` and follow its instructions. Report
if the source is unavailable.
