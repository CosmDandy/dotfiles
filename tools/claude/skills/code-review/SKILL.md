---
name: code-review
description: Read-only code quality analysis checking readability, DRY violations, error handling, test coverage, and naming conventions
context: fork
agent: Explore
---

# /code-review — Code Quality Analysis

Perform a read-only code review of: $ARGUMENTS

If `$ARGUMENTS` specifies files/paths, review those. Otherwise, review recent changes (`git diff`).

## Analysis Areas

### 1. Readability
- Clear naming (variables, functions, classes)
- Appropriate function length (20-30 lines ideal)
- Logical code organization
- No unnecessary complexity

### 2. DRY & Abstraction
- Duplicated logic that should be extracted
- Over-abstraction (premature generalization)
- Appropriate use of helpers/utilities

### 3. Error Handling
- Errors caught and handled appropriately
- No bare `except:` (Python) or swallowed errors
- Fail-fast principle applied
- Meaningful error messages

### 4. Logic & Correctness
- Edge cases handled
- Off-by-one errors
- Race conditions (if concurrent code)
- Resource cleanup (files, connections, locks)

### 5. Testing
- Changed code has test coverage
- Tests are meaningful (not just asserting True)
- Edge cases tested
- Test naming describes behavior

### 6. Conventions
- Project coding style followed
- Consistent patterns with existing codebase
- Import organization
- Type annotations (if project uses them)

## Output Format

```markdown
# Code Review: <scope>

## Summary
Quality: GOOD / ACCEPTABLE / NEEDS WORK
Key areas: N issues found

## Findings

### [HIGH] Finding title
- **File**: path:line
- **Code**: `relevant snippet`
- **Issue**: what's wrong
- **Suggestion**: how to improve
```

## Important

- This is READ-ONLY analysis — do NOT modify any files
- Focus on substance, not style nitpicks
- Reference specific line numbers
- Acknowledge what's done well, not just problems
