---
description: "Review current working directory changes: analyze code quality, find bugs, suggest improvements"
argument-hint: "[path or focus area]"
---

# Code Review: $ARGUMENTS

Perform a thorough code review of the current changes. If $ARGUMENTS is provided, focus on that path or area. Otherwise review all recent changes.

## Step 1: Understand what changed

Run in parallel:

```bash
# What files changed recently
git diff --stat HEAD 2>/dev/null || git status

# Full diff of staged + unstaged changes  
git diff HEAD 2>/dev/null

# Recent commits context
git log --oneline -10 2>/dev/null
```

If not a git repo, use:
```bash
ls -la $ARGUMENTS
```

## Step 2: Read the changed files

For each changed file:
- Read the FULL file, not just the diff
- Understand the surrounding context (what calls it, what it imports)
- Check related files (imports, tests, config)

## Step 3: Run static analysis

```bash
# Python files
ruff check $ARGUMENTS 2>/dev/null

# TypeScript/JavaScript
npx tsc --noEmit 2>/dev/null || true

# Shell scripts
shellcheck $ARGUMENTS 2>/dev/null || true
```

## Step 4: Analyze for issues

Check these categories:

### Bugs & Logic
- Wrong conditions or comparisons
- Missing return values or error handling
- Off-by-one errors, boundary conditions
- Null/undefined/None not handled
- Race conditions or async issues

### Security
- Command injection (unquoted variables in shell)
- SQL injection (string concatenation in queries)  
- Hardcoded secrets or tokens
- Unsafe deserialization
- Missing input validation at boundaries

### Code Quality
- Dead code (unused variables, unreachable branches)
- Duplicate code that should be extracted
- Misleading names or comments
- Missing edge cases

### Performance
- N+1 queries or loops
- Unnecessary repeated computations
- Missing caching opportunities

## Step 5: Write the review

Format:

```
## Code Review

### Summary
[1-2 sentence overview of what was reviewed and overall quality]

### 🔴 Critical Issues
[Only if truly breaking/security issues]

### 🟠 Bugs
[Real logic errors that will cause wrong behavior]

### 🟡 Improvements
[Code quality, readability, maintainability]

### 🟢 Suggestions
[Optional nice-to-haves]

### ✅ What's good
[Acknowledge solid work]

### Action items
- [ ] ...
- [ ] ...
```

## Rules

- Always read the full file before commenting — never from diff alone
- Show concrete examples: broken code → fixed code
- Explain WHY, not just WHAT is wrong
- If nothing serious: say so clearly — don't manufacture issues
- Keep focus on $ARGUMENTS if specified
