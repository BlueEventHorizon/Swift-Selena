---
name: toc_update_workflow
description: "{target}_toc.yaml update workflow (individual entry file method)"
applicable_when:
  - Running as toc-updater Agent
  - Executing /create-rules-toc or /create-specs-toc
  - After adding, modifying, or deleting target documents
doc-advisor-version-xK9XmQ: 5.0
---

# ToC Update Workflow

> **Note**: `{target}` is either `rules` or `specs`, determined by the invoking SKILL.

## Overview

Workflow for updating `.claude/doc-advisor/toc/{target}/{target}_toc.yaml`. Uses **individual entry file method**, processing each document with independent subagents.

## Architecture

### Design Philosophy

- **1 file = 1 subagent**: Process each document individually
- **Persistent artifacts**: Each subagent's output remains as a file
- **Resumable**: Completed work is preserved on interruption, resume from incomplete
- **Single Source of Truth**: Format definition consolidated in `toc_format.md`

### Directory Structure

```
.claude/doc-advisor/toc/{target}/
├── {target}_toc.yaml            # Final artifact (after merge)
├── .toc_checksums.yaml          # Change detection checksums
└── .toc_work/                   # Work directory (.gitignore target)
    ├── {target}_subdir_file1.yaml
    ├── {target}_subdir_file2.yaml
    └── ... (for each target file)
```

---

## Key Principles [MANDATORY]

- **Single Source of Truth**: `toc_format.md` is the only source for format definition and intermediate file schema
- **All fields required**: Fill all fields in format definition. **No omissions**
- **Keyword extraction**: Actually read each file and extract keywords from content (array format)
- **YAML syntax**: Use indentation, colons, and hyphens correctly
- **Key format**: Project-relative path (e.g., `rules/core/architecture_rule.md`, `specs/requirements/login.md`)

---

## Workflow Overview

```
/create-{target}-toc execution
    ↓
Phase 1: Initialization (Orchestrator)
    ↓
Phase 2: Processing (Parallel Subagents)
    ↓
Phase 3: Merge (Orchestrator)
    ↓
Cleanup
```

---

## Phase 1: Initialization (Orchestrator)

### Step 1.1: Check .toc_work/ status

```bash
test -d .claude/doc-advisor/toc/{target}/.toc_work && echo "EXISTS" || echo "NOT_EXISTS"
```

### Step 1.2: Mode determination and branching

| Condition                                                  | Processing                                      |
| ---------------------------------------------------------- | ----------------------------------------------- |
| `--full` option specified                                  | Delete .toc_work/ → New processing in full mode |
| .toc_work/ exists                                          | Continue mode (process existing pending YAMLs)  |
| .toc_work/ doesn't exist + {target}_toc.yaml doesn't exist | New processing in full mode                     |
| .toc_work/ doesn't exist + {target}_toc.yaml exists        | Incremental mode                                |

### Step 1.3: Identify target files

- **full mode**: Get all files in scan targets
- **incremental mode**: Detect changed files using hash method

### Step 1.4: Generate pending YAML templates

Generate templates in `.toc_work/` for each target file.

---

## Phase 2: Parallel Processing (Subagent)

### Step 2.1: Identify pending YAMLs

Read `.claude/doc-advisor/toc/{target}/.toc_work/*.yaml` and identify files with `_meta.status: pending`

### Step 2.2: Launch subagents in parallel

**Parallel count**: Default 5 (defined in toc_utils.py)

```
# Orchestrator calls multiple Task tools in one message
Task(subagent_type: toc-updater, prompt: "target: {target}, entry_file: .claude/doc-advisor/toc/{target}/.toc_work/xxx.yaml")
Task(subagent_type: toc-updater, prompt: "target: {target}, entry_file: .claude/doc-advisor/toc/{target}/.toc_work/yyy.yaml")
... (up to max_workers simultaneous)
```

### Step 2.3: Subagent processing

Each subagent (toc-updater) executes:

1. Read `entry_file`
2. Get document path from `_meta.source_file`
3. Read document (resolve from project root)
4. Extract and set fields according to "Field Guidelines" in `toc_format.md`:
   - `title`: Extract from H1
   - `purpose`: Summarize in 1-2 lines
   - `content_details`: Content details (5-10 items)
   - `applicable_tasks`: Applicable tasks
   - `keywords`: 5-10 words
5. Set `_meta.status: completed` and `_meta.updated_at`
6. Write and save

### Step 2.4: Repeat

Repeat Steps 2.1-2.3 until all pending YAMLs are completed

---

## Phase 3: Merge

### Step 3.1: Completion check

Verify each `.toc_work/*.yaml` meets:

- `_meta.status == completed`
- `title != null`
- `purpose != null`

**If incomplete**: Output warning and confirm with user

### Step 3.2: Merge processing

#### full mode

1. Read all `.toc_work/*.yaml`
2. Exclude `_meta` and convert to `docs` section
3. Set `metadata` (generated_at, file_count)
4. Write to `{target}_toc.yaml`

#### incremental mode

1. Read existing `{target}_toc.yaml`
2. Delete entries recorded in `.toc_checksums.yaml` but file doesn't exist
3. Overwrite/add entries from `.toc_work/*.yaml` (exclude `_meta`)
4. Update `metadata.generated_at`, `metadata.file_count`
5. Write to `{target}_toc.yaml`
6. Update checksums: `cp .toc_work/.toc_checksums_pending.yaml .toc_checksums.yaml`

### Step 3.3: Cleanup

```bash
rm -rf .claude/doc-advisor/toc/{target}/.toc_work
```

---

## Validation

Check before merge:

1. **YAML syntax check**:
   - Accuracy of indentation, colons, hyphens
   - Quote escaping

2. **Required field check**:
   - metadata: name, generated_at, file_count
   - docs: Each entry has title, purpose, content_details, applicable_tasks, keywords

3. **File existence check**:
   - All files listed in docs actually exist

---

## Error Handling

### On subagent error

- Immediately change `_meta.status` to `error` (do NOT leave as `pending`)
- Record error content in `_meta.error_message`
- Do NOT retry — error files require manual review
- This prevents infinite loops from recurring failures

### On merge error

- Do not delete `.toc_work/` (can re-run)
- Report error content
- Prompt manual intervention

---

## Quality Checklist

After generation/update, verify:

- [ ] All target document files are listed
- [ ] Each entry has required fields (title, purpose, content_details, applicable_tasks, keywords)
- [ ] purpose contains "what it defines" (1-2 lines)
- [ ] keywords contain task-matchable terms (5-10 words)
- [ ] YAML syntax is correct (indentation, colons, hyphens)
- [ ] Generated time (metadata.generated_at) is ISO 8601 format
- [ ] File count (metadata.file_count) matches actual file count

---

## Related Files

- `toc_format.md` - Format definition (YAML schema)
- `agents/toc-updater.md` - Single file processing subagent
- `doc-advisor/docs/toc_orchestrator.md` - Orchestrator workflow
