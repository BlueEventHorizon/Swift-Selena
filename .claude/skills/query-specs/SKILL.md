---
name: query-specs
description: |
  Search the pre-analyzed document index (ToC) to identify specification
  documents needed for a task. The ToC contains AI-extracted
  metadata (keywords, applicable_tasks) that enables discovery beyond
  simple file search.
  Trigger:
  - "What specs apply to this task?"
  - Before starting implementation work
context: fork
agent: general-purpose
model: haiku
user-invocable: true
argument-hint: "[task description]"
doc-advisor-version-xK9XmQ: 4.4
---

## Role

Analyze task content and return a list of required specification document paths.

## Pre-check (MANDATORY - Run first)

Run the configuration check:

```bash
bash .claude/doc-advisor/scripts/check_config.sh specs
```

- **No output** → Proceed to Procedure
- **Output present** → STOP. Run `/setup-config` skill first to configure document directories, then restart this skill

## Procedure

1. Read `.claude/doc-advisor/toc/specs/specs_toc.yaml` **completely** (YAML format index)
   - **MANDATORY**: Read the entire file with the Read tool. Do NOT use Grep or search tools on ToC
2. Deeply understand all entries, then identify relevant candidates from task content
   - Find relevant entries (match by keywords, purpose, title, applicable_tasks)
3. If there's any chance of relevance, read the actual file to confirm (no false negatives allowed)
4. Return the confirmed path list

## Critical Rule

**ToC must be fully read and deeply understood before making decisions.**

- ❌ PROHIBITED: Using Grep/search tools on ToC content
- ❌ PROHIBITED: Partial reading or skimming the ToC
- ✅ REQUIRED: Read the entire ToC file with Read tool
- ✅ REQUIRED: Understand all entries before identifying relevant documents

## Output Format

```
Required documents:
- specs/requirements/login_screen.md
- specs/requirements/user_authentication.md
- specs/design/login_screen_design.md
```

## Notes

- False negatives are strictly prohibited. When in doubt, include it
