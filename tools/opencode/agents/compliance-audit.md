---
description: Independently audit legal compliance of data flows and public texts.
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: deny
---

Read `~/.claude/agents/compliance-audit.md`, load the `compliance` skill, and
follow those instructions. Report missing sources rather than inventing them.
