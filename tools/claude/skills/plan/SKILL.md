---
name: plan
description: Create a structured implementation plan with dependency analysis, blast radius assessment, and rollback strategy
---

# /plan — Implementation Planning

You are creating a structured implementation plan for: $ARGUMENTS

## Process

### 1. Analyze Request
- Parse the request into concrete deliverables
- Identify which systems/files are affected
- Map dependencies between changes

### 2. Research Codebase
Use a subagent to research the codebase:
- Find all files that will be modified or created
- Understand existing patterns and conventions
- Identify tests that cover affected code
- Check for related configuration (CI/CD, deployment)

### 3. Assess Risk
- **Blast radius**: what breaks if this goes wrong?
- **Reversibility**: can changes be rolled back easily?
- **Dependencies**: what must happen in order?
- **Environment impact**: dev only, staging, production?

### 4. Write Plan

Create the plan file at `plans/<date>-<feature-slug>.md` with this structure:

```markdown
# Plan: <title>

## Scope
What this plan covers and what it explicitly does NOT cover.

## Constraints
- Technical limitations
- Time/resource constraints
- Dependencies on external systems

## File Impact
| File | Action | Risk |
|------|--------|------|
| path/to/file | modify/create/delete | low/medium/high |

## Steps
### Step 1: <description>
- [ ] Action item
- [ ] Validation: how to verify this step worked
- Expected output/state after completion

### Step 2: <description>
...

## Risk Assessment
- **Overall risk**: LOW / MEDIUM / HIGH
- **Blast radius**: <what's affected>
- **Rollback**: <how to undo if needed>

## Validation
How to verify the entire plan succeeded:
- [ ] Test command
- [ ] Manual check
```

### 5. Present to User

Show the plan summary and ask for review:
- Total files affected
- Risk level
- Estimated steps
- Path to full plan file

**STOP here. Do NOT execute the plan. Wait for user to review and invoke /implement.**
