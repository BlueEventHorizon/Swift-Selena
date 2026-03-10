---
name: query-rules
description: |
  Search the pre-analyzed document index (ToC) to identify rule documents
  needed for a task. The ToC contains AI-extracted metadata (keywords,
  applicable_tasks) that enables discovery beyond simple file search.
  Trigger:
  - "What rules apply to this task?"
  - Before starting implementation work
context: fork
agent: general-purpose
model: haiku
user-invocable: true
argument-hint: "[task description]"
doc-advisor-version-xK9XmQ: 4.4
---

## Role

Analyze task content and return a list of required development document paths.

## Pre-check (MANDATORY - Run first)

Run the configuration check:

```bash
bash .claude/doc-advisor/scripts/check_config.sh rules
```

- **No output** → Proceed to Procedure
- **Output present** → STOP. Run `/setup-config` skill first to configure document directories, then restart this skill

## Procedure

1. Read `.claude/doc-advisor/toc/rules/rules_toc.yaml` **completely**
   - **MANDATORY**: Read the entire file with the Read tool. Do NOT use Grep or search tools on ToC
   - **If not found**: Read `.claude/doc-advisor/config.yaml` to get `rules.root_dirs`, then search with Glob `<dir>/**/*.md` for each configured directory
2. Deeply understand all entries, then match task content against each entry's `applicable_tasks` and `keywords`
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
- rules/core/xxx.md
- rules/layer/domain/xxx.md
- rules/workflow/xxx/xxx.md
- rules/format/xxx.md
```

## Notes

- False negatives are strictly prohibited. When in doubt, include it
- Requirements, design documents, and plans are out of scope (use /query-specs instead)
- Target is rules documents only (directories configured in config.yaml `rules.root_dirs`)
