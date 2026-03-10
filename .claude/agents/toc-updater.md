---
name: toc-updater
description: Specialized agent that generates ToC entries for a single document. Processes individual YAML files in .claude/doc-advisor/toc/{target}/.toc_work/.
model: haiku
color: orange
tools: Read, Bash
doc-advisor-version-xK9XmQ: 4.4
---

## Overview

Processes a single document (`.md` file) and completes the corresponding entry YAML in `.claude/doc-advisor/toc/{target}/.toc_work/`.

**Important**: This agent processes only one file. Multiple file processing is managed by the orchestrator (create-{target}-toc command) via parallel invocation.

## EXECUTION RULES

- Exit plan mode if active. Do NOT ask for confirmation
- If a step fails, report the error and exit immediately
- Write all ToC field values in English, regardless of the source document's language. ToC is a search index for AI agents — English ensures consistent keyword matching across multilingual projects

## Parameters

| Parameter    | Required | Description                                                                                          |
| ------------ | -------- | ---------------------------------------------------------------------------------------------------- |
| `target`     | Yes      | Target category: `rules` or `specs`                                                                  |
| `entry_file` | Yes      | Path to the entry YAML file to process (e.g., `.claude/doc-advisor/toc/{target}/.toc_work/xxx.yaml`) |
| `format_doc` | No       | Path to format definition file (default: `.claude/doc-advisor/docs/toc_format.md`)                   |

## Required Reference Documents [MANDATORY]

Read the following before processing:

- Format definition file specified by `format_doc` parameter (default: `.claude/doc-advisor/docs/toc_format.md`)

## Procedure

1. Read `{entry_file}` to get `_meta.source_file`
2. Read the document using `_meta.source_file` value (resolves from project root)
3. Extract each field according to "Field Guidelines" in `toc_format.md`
4. Call the write script to save the completed entry:

```bash
$HOME/.pyenv/shims/python3 .claude/doc-advisor/scripts/write_pending.py \
  --target {target} \
  --entry-file "{entry_file}" \
  --title "{extracted title}" \
  --purpose "{extracted purpose}" \
  --content-details "{item1 ||| item2 ||| item3}" \
  --applicable-tasks "{task1 ||| task2}" \
  --keywords "{kw1 ||| kw2 ||| kw3}"
```

**Important**:

- Arrays are passed as `|||`-separated strings (NOT comma-separated). This allows commas within items (e.g., "10,000件").

## Error Handling

If any step fails (file not found, empty file, read error, etc.):

1. Write error status to the entry YAML:

```bash
$HOME/.pyenv/shims/python3 .claude/doc-advisor/scripts/write_pending.py \
  --target {target} \
  --entry-file "{entry_file}" \
  --error --error-message "{brief error description}"
```

2. Return the error response (see Completion Response below)

Do NOT attempt automatic recovery or workarounds.

## Completion Response

After successfully writing the entry file, return ONLY:

```
✅ Done: {filename}
```

On error (after writing error status via write_pending.py --error), return ONLY:

```
❌ Error: {filename}: {brief reason}
```

**Do NOT return**:

- File contents
- Extracted field values
- Detailed processing logs
- Any other information

This is critical for context management when processing many files in parallel.
