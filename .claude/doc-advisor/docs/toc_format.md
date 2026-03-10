---
name: toc_format
description: Format definition for {target}_toc.yaml (Single Source of Truth)
applicable_when:
  - Creating or updating ToC entries
  - Validating rules_toc.yaml or specs_toc.yaml structure
doc-advisor-version-xK9XmQ: 4.4
---

# ToC YAML Format Definition

## Purpose

`.claude/doc-advisor/toc/{target}/{target}_toc.yaml` is the **single source of truth** for the subagent to identify documents needed for tasks.

The quality of this file determines task execution success. **Missing information is not acceptable.**

**This file serves as the Single Source of Truth for format definition and intermediate file schema.**

---

## Key Principles [MANDATORY]

- Include all target documents without omission
- Support task matching through keywords
- When in doubt, include it (never miss documents)
- **Key format**: Project-relative path (e.g., `rules/core/architecture_rule.md`, `specs/requirements/app_overview.md`)

### Language Rule

- **All field values must be written in English**, regardless of the source document's language
- ToC is a search index for AI agents — English ensures consistent keyword matching across multilingual projects

### YAML Formatting Rules

- **Indentation**: 2 spaces (no tabs)
- **After colon**: Always one space (`key: value`)
- **Arrays**: Hyphen + space (`- item`)
- **No null**: All fields must be filled
- **No empty arrays**: `[]` is not allowed (minimum 1 item)
- **No inline arrays**: Do not use `[a, b]` format. Always use list format
- **No multiline**: Do not use `|` or `>`. Write in single line

---

## Intermediate File Schema [Single Source of Truth]

Structure definition for work files used in individual entry file method.

### File Layout

```
.claude/doc-advisor/toc/{target}/.toc_work/   # Work directory (.gitignore target)
├── {sha256_hash_16chars}.yaml
└── ... (for each target file)
```

### Filename Generation Rule

Generate YAML filename using SHA256 hash of the source file path:

```python
hashlib.sha256(source_file.encode('utf-8')).hexdigest()[:16] + ".yaml"
```

```
rules/core/architecture_rule.md   → a1b2c3d4e5f67890.yaml
specs/requirements/app_overview.md → 1234567890abcdef.yaml
```

The original path is preserved in `_meta.source_file` inside each YAML file.
Hash-based naming avoids filename length limits, case-insensitive collisions, and special character issues.

### Entry YAML Structure

```yaml
_meta:
  source_file: {target}/path/to/document.md    # Path from project root
  doc_type: requirement                        # Document type from .doc_structure.yaml
  status: pending                               # pending | completed | error
  error_message: null                            # Error details (only when status: error)
  updated_at: null                              # Completion time (ISO 8601 format)

# Below: {target}_toc.yaml entry format (key uses source_file value)
title: null
purpose: null
content_details: []
applicable_tasks: []
keywords: []
```

### _meta Field Description

| Field           | Type          | Description                                                                                                    |
| --------------- | ------------- | -------------------------------------------------------------------------------------------------------------- |
| `source_file`   | string        | Target document path (from project root)                                                                       |
| `doc_type`      | string        | Document type derived from `.doc_structure.yaml` (e.g., rule, requirement, design, plan, api, reference, spec) |
| `status`        | enum          | `pending` (unprocessed), `completed` (done), or `error` (failed)                                               |
| `error_message` | string/null   | Error details (only when `status: error`), `null` otherwise                                                    |
| `updated_at`    | datetime/null | Completion time (ISO 8601 format), `null` if incomplete                                                        |

---

## YAML Schema Definition (Final Output)

### Top-level Structure

```yaml
metadata:
  name: string # Index name
  generated_at: datetime # Generation time (ISO 8601 format)
  file_count: integer # Total target file count

docs: object # Document entries (key: file path)
```

---

### docs (Document Entries)

```yaml
docs:
  <file_path>: # Path from project root
    doc_type: string # Document type (e.g., rule, requirement, design)
    title: string # Title (extracted from H1)
    purpose: string # Purpose (max 200 chars)
    content_details: array[string] # Content details (max 10 items)
    applicable_tasks: array[string] # Applicable tasks (max 10 items)
    keywords: array[string] # Keywords (max 10 words)
```

**Rules Example**:

```yaml
docs:
  rules/core/architecture_rule.md:
    doc_type: rule
    title: Architecture Rules
    purpose: Defines overall architecture structure, layer design, and inter-layer communication
    content_details:
      - Directory structure
      - Layer dependencies
      - Inter-layer communication patterns
      - Data flow design
      - AsyncStream design principles
    applicable_tasks:
      - Architecture review
      - Layer violation detection
      - Overall design review
    keywords:
      - architecture
      - layer
      - Clean Architecture
      - DI
      - Factory
```

**Specs Example**:

```yaml
docs:
  specs/requirements/app_overview.md:
    doc_type: requirement
    title: Application Overview Specification
    purpose: Defines overall requirements, feature scope, and use cases for the application
    content_details:
      - Application overview
      - Main feature list
      - Use case definitions
      - Screen navigation overview
      - Data requirements
    applicable_tasks:
      - New feature implementation planning
      - Feature scope confirmation
      - Overall design understanding
    keywords:
      - application
      - requirements
      - feature list
      - use case
      - screen navigation
```

---

## Field Guidelines

### purpose

- Describe the file's role concisely (max 200 characters)
- Use phrases like "Defines rules for...", "Specifies requirements for...", "Describes design for..."

### content_details

- List **specific content items** in the file (rules/constraints/patterns/requirements/design elements)
- Detailed enough for subagent to understand overview without reading the file
- Must include important constraints/requirements
- Prioritize items **unique to this document** — generic items (e.g., "error handling", "overview") add little value
- Describe **concrete details under each heading**, not the heading itself (e.g., not "Error handling" but "ContactContainerError enum with differentContainer, readOnlyContainer variants")
- Max 10 items

### applicable_tasks

- List **specific task types** that need this file
- Avoid vague expressions, use specific task names
- Include actions like "implementation", "creation", "modification", "review"
- Prioritize the most specific and distinguishing tasks
- Max 10 items

### keywords

- **Matching terms** for task descriptions
- Prioritize **class names, method names, and domain-specific terms** (e.g., `ContactListViewModel`, `canAddToGroup`, `debounce`)
- Include technical terms, concept names, abbreviations, feature names
- Avoid category labels (e.g., "workflow", "document") — prefer terms unique to this document
- Max 10 words

---

## Complete Examples

### Rules ToC

```yaml
# .claude/doc-advisor/toc/rules/rules_toc.yaml

metadata:
  name: Development Documentation Search Index
  generated_at: 2026-01-11T12:00:00Z
  file_count: 25

docs:
  rules/core/architecture_rule.md:
    doc_type: rule
    title: Architecture Rules
    purpose: Defines overall architecture structure, layer design, and inter-layer communication
    content_details:
      - Directory structure
      - Layer dependencies
      - Data flow design
      - AsyncStream design principles
    applicable_tasks:
      - Architecture review
      - Layer violation detection
      - Overall design review
    keywords:
      - architecture
      - layer
      - Clean Architecture
      - DI
      - Factory

  rules/layer/infrastructure/repository_rule.md:
    doc_type: rule
    title: Repository Implementation Rules
    purpose: Defines Repository implementation's immediate response + eventual sync pattern
    content_details:
      - Repository layer responsibilities
      - Immediate response + eventual sync pattern
      - Application method for Create/Update/Delete
      - Anti-patterns
    applicable_tasks:
      - Repository implementation
      - Infrastructure layer implementation
      - CRUD operation implementation
    keywords:
      - Repository
      - immediate response
      - eventual sync
      - cache update
      - forceBroadcast
```

### Specs ToC

```yaml
# .claude/doc-advisor/toc/specs/specs_toc.yaml

metadata:
  name: Project Specification Document Search Index
  generated_at: 2026-01-11T12:00:00Z
  file_count: 25

docs:
  specs/requirements/app_overview.md:
    doc_type: requirement
    title: Application Overview Specification
    purpose: Defines overall requirements and feature scope for the application
    content_details:
      - Application overview
      - Main feature list
      - Use case definitions
      - Screen navigation overview
    applicable_tasks:
      - New feature implementation planning
      - Feature scope confirmation
    keywords:
      - application
      - requirements
      - feature list

  specs/design/login_screen_design.md:
    doc_type: design
    title: Login Screen Design
    purpose: Defines UI design, ViewModel, and state management for the login screen
    content_details:
      - Screen layout
      - ViewModel design
      - State transitions
      - Authentication service integration
    applicable_tasks:
      - Login screen implementation
      - UI layer design review
    keywords:
      - login
      - ViewModel
      - SwiftUI
      - authentication
```
