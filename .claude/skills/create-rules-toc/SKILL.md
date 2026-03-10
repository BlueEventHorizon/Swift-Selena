---
name: create-rules-toc
description: |
  Update the rules search index (ToC) after modifying, creating, or deleting
  development documents such as coding standards, architecture rules,
  or workflow guides.
  Trigger:
  - After editing, adding, or removing rule documents
  - "Rebuild the rules ToC"
allowed-tools: Bash, Read, Task
user-invocable: true
argument-hint: "[--full]"
doc-advisor-version-xK9XmQ: 4.4
---

# create-rules-toc

Generate/update rules ToC (Table of Contents) for AI-searchable document index.

## Usage

```
/create-rules-toc [--full]
```

| Argument | Description                                           |
| -------- | ----------------------------------------------------- |
| (none)   | Incremental update (hash-based) or resume processing  |
| `--full` | Full file scan (for initial creation or regeneration) |

## Pre-check (MANDATORY - Run first)

Run the configuration check:

```bash
bash .claude/doc-advisor/scripts/check_config.sh rules
```

- **No output** → Proceed to Execution Flow
- **Output present** → STOP. Run `/setup-config` skill first to configure document directories, then restart this skill

## Execution Flow

1. Read `.claude/doc-advisor/docs/toc_orchestrator.md` for orchestrator workflow
2. Read `.claude/doc-advisor/docs/toc_format.md` for format definition
3. Execute Pre-check and Phase 1-3 as described in the orchestrator document, with **target = rules**
   - If `$0` = `--full`: Execute in **full mode** (rebuild entire ToC)
   - Otherwise: Execute in **incremental mode** (process changes only)

## Error Handling

If an unexpected error occurs during processing, report the error details clearly and ask the user how to proceed.
