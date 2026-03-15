---
name: setup-config
description: |
  Auto-detect and classify project document directories as rules or specs.
  Updates .doc_structure.yaml root_dirs based on classification results.
  Trigger:
  - After initial setup to configure document directories
  - "Classify my documents"
  - "What directories should be rules vs specs?"
allowed-tools: Bash, Read, Edit, Glob
user-invocable: true
argument-hint: "[--update]"
doc-advisor-version-xK9XmQ: 5.0
---

# setup-config

Auto-detect and classify project document directories for Doc Advisor.

## Usage

```
/setup-config [--update]
```

| Argument   | Description                                                   |
| ---------- | ------------------------------------------------------------- |
| (none)     | Full classification of all markdown directories               |
| `--update` | Only process directories not already in .doc_structure.yaml root_dirs |

## Prerequisite

Doc Advisor must be installed (`.claude/doc-advisor/` directory exists).
If not, run `setup.sh` first.

## Reference Documents

Before classifying, read the classification rules:

- `.claude/doc-advisor/docs/classification_rules.md`

This document defines:

- **category**: rules / specs
- **doc_type**: rule, requirement, design, plan, api, reference, spec
- Judgment procedure (path components → frontmatter → file content)

## Execution Flow

### Step 1: Run directory scan script

```bash
python3 .claude/doc-advisor/scripts/classify_dirs.py
```

Capture the JSON output. The script discovers markdown directories but does NOT classify them.

### Step 1b: Supplement with empty directory candidates

`classify_dirs.py` only finds directories that already contain markdown files.
Empty directories (not yet populated) are missing from the scan result.

After running the scan, use Glob to explore subdirectories under any
document-related top-level directories found (e.g. `docs/`, `rules/`, `specs/`):

```
Glob: docs/*/, rules/*/, specs/*/
```

Any subdirectory returned by Glob that is **not already in the scan result**
is added as an empty candidate: `{ dir, md_count: 0, empty: true }`.

**Do NOT skip these** — present them to the user for confirmation in Step 3/4.

### Step 2: Classify using rules

For each discovered directory in the JSON output:

1. Read `classification_rules.md` rules
2. Apply path_components scan (top-down, first match wins)
3. Check frontmatter doc_types if path is ambiguous
4. If still unclear, read 1-2 .md files from the directory

Assign each directory a **category** (rules/specs) and note confidence:

- **high**: path component directly matches (e.g., `rules/`, `specs/requirements/`)
- **medium**: semantic match or frontmatter match
- **low**: inferred from file content

### Step 3: Present results to user

Display the classification results clearly, including empty directory candidates:

```
Document Directory Classification

Rules (development rules, guidelines, standards):
  [high] rules/           (3 files)
  [medium] guidelines/    (2 files)

Specs (requirements, designs, plans):
  [high] specs/requirements/ (5 files)
  [high] specs/design/    (0 files, empty)   ← empty candidate from Step 1b

Skipped:
  docs/                   README/CHANGELOG only

Unclassified:
  shared/                 (3 files) - need user input
```

### Step 4: Ask user for confirmation

Ask the user:

- Are the classifications correct?
- For unclassified directories: should they be rules, specs, or skipped?
- For empty directories: confirm whether to include them in root_dirs.
- Any overrides needed?

### Step 5: Update .doc_structure.yaml

After user confirmation, write `.doc_structure.yaml` (at project root) using the Write tool.

If `.doc_structure.yaml` already exists, update the `root_dirs`, `doc_types_map`, and `patterns` sections.
If it does not exist, create it with the following structure.

Output example:

```yaml
# doc_structure_version: 3.0

rules:
  root_dirs:
    - rules/
    - guidelines/
  doc_types_map:
    rules/: rule
    guidelines/: rule
  patterns:
    target_glob: "**/*.md"
    exclude: []

specs:
  root_dirs:
    - specs/requirements/
    - specs/design/
  doc_types_map:
    specs/requirements/: requirement
    specs/design/: design
  patterns:
    target_glob: "**/*.md"
    exclude: []
```

Valid doc_types: `rule`, `requirement`, `design`, `plan`, `api`, `reference`, `spec`

### Step 6: Summary

```
.doc_structure.yaml updated

Rules directories:
  - rules/
  - guidelines/

Specs directories:
  - specs/
  - design/

Next steps:
  - /create-rules-toc --full  (generate rules search index)
  - /create-specs-toc --full  (generate specs search index)
```

## Error Handling

- If Doc Advisor is not installed (`.claude/doc-advisor/` not found), tell user to run setup.sh first
- If no markdown directories found, report that the project has no documents to classify
- If classification script fails, report the error and suggest manual configuration
