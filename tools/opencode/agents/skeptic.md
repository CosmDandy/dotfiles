---
description: Verify documentation and plans against the actual repository.
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: deny
---

Read `~/.claude/agents/skeptic.md` and follow its instructions. Report if the
source is unavailable.
