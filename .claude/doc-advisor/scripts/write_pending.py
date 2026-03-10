#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# doc-advisor-version-xK9XmQ: 4.4
"""
pending YAML write script (unified for rules/specs)

Writes analysis results from subagent to pending YAML,
changing status to completed.

Usage:
    python3 write_pending.py --target rules \
      --entry-file ".claude/doc-advisor/toc/rules/.toc_work/xxx.yaml" \
      --title "Title" \
      --purpose "Purpose" \
      --content-details "item1 ||| item2 ||| item3 ||| item4 ||| item5" \
      --applicable-tasks "task1 ||| task2" \
      --keywords "kw1 ||| kw2 ||| kw3 ||| kw4 ||| kw5"

Error mode:
    python3 write_pending.py --target rules \
      --entry-file ".claude/doc-advisor/toc/rules/.toc_work/xxx.yaml" \
      --error --error-message "Source file not found"

Exit codes:
    0: Success
    1: File not found
    2: Missing required field
    3: Array element count insufficient
    4: Write failure
"""

import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path

from toc_utils import yaml_escape, load_entry_file, get_project_root, validate_path_within_base


# Validation settings
MIN_CONTENT_DETAILS = 5
MIN_APPLICABLE_TASKS = 1
MIN_KEYWORDS = 5


def parse_args():
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(
        description='Write analysis results to pending YAML'
    )
    parser.add_argument('--target', required=True, choices=['rules', 'specs'],
                        help='Target category: rules or specs')
    parser.add_argument('--entry-file', required=True,
                        help='Target entry YAML file path')

    # Error mode
    parser.add_argument('--error', action='store_true',
                        help='Write error status (skip field validation)')
    parser.add_argument('--error-message', default='',
                        help='Error message (used with --error)')

    # Content fields (required in normal mode, ignored in error mode)
    parser.add_argument('--title', default=None,
                        help='Document title')
    parser.add_argument('--purpose', default=None,
                        help='Document purpose (1-2 sentences)')
    parser.add_argument('--content-details', default=None,
                        help='Content details (||| separated, 5-10 items)')
    parser.add_argument('--applicable-tasks', default=None,
                        help='Applicable tasks (||| separated, 1+ items)')
    parser.add_argument('--keywords', default=None,
                        help='Keywords (||| separated, 5-10)')
    parser.add_argument('--force', action='store_true',
                        help='Force overwrite even if completed')

    return parser.parse_args()


def parse_separated(value, separator='|||'):
    """Convert separator-delimited string to array (default: ||| separator)"""
    if not value:
        return []
    items = [item.strip() for item in value.split(separator)]
    return [item for item in items if item]  # Remove empty strings


def validate_array(name, items, min_count):
    """Validate array element count"""
    if len(items) < min_count:
        print(f"Error: {name} requires at least {min_count} items (got {len(items)})")
        print(f"  Provided: {', '.join(items)}")
        return False
    return True


def write_error_yaml(filepath, meta, error_message, target):
    """
    Write error status to entry YAML file

    Args:
        filepath: Output file path
        meta: _meta section dict (source_file, doc_type preserved)
        error_message: Error description
        target: 'rules' or 'specs'

    Returns:
        bool: True on success
    """
    lines = []

    # _meta section
    lines.append("_meta:")
    lines.append(f"  source_file: {yaml_escape(meta.get('source_file', ''))}")
    doc_type = meta.get('doc_type', '')
    if doc_type:
        lines.append(f"  doc_type: {doc_type}")
    lines.append("  status: pending")
    lines.append(f"  error_message: {yaml_escape(error_message)}")
    lines.append(f"  updated_at: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
    lines.append("")

    # Null fields (preserve template structure)
    lines.append("title: null")
    lines.append("purpose: null")
    lines.append("content_details: []")
    lines.append("applicable_tasks: []")
    lines.append("keywords: []")

    lines.append("")  # Trailing newline

    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        return True
    except (IOError, OSError, PermissionError) as e:
        print(f"Error: Failed to write file: {filepath} - {e}")
        return False


def write_entry_yaml(filepath, meta, entry, target):
    """
    Write entry YAML file

    Args:
        filepath: Output file path
        meta: _meta section dict
        entry: Entry data dict
        target: 'rules' or 'specs'

    Returns:
        bool: True on success
    """
    lines = []

    # _meta section
    lines.append("_meta:")
    lines.append(f"  source_file: {yaml_escape(meta.get('source_file', ''))}")
    doc_type = meta.get('doc_type', '')
    if doc_type:
        lines.append(f"  doc_type: {doc_type}")
    lines.append(f"  status: {meta.get('status', 'completed')}")
    lines.append(f"  updated_at: {meta.get('updated_at', '')}")
    lines.append("")

    # Scalar fields
    lines.append(f"title: {yaml_escape(entry.get('title', ''))}")
    lines.append(f"purpose: {yaml_escape(entry.get('purpose', ''))}")

    # Array fields
    for field in ['content_details', 'applicable_tasks', 'keywords']:
        lines.append(f"{field}:")
        items = entry.get(field, [])
        for item in items:
            lines.append(f"  - {yaml_escape(item)}")

    lines.append("")  # Trailing newline

    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        return True
    except (IOError, OSError, PermissionError) as e:
        print(f"Error: Failed to write file: {filepath} - {e}")
        return False


def main():
    args = parse_args()

    target = args.target
    entry_file = Path(args.entry_file)

    # Path traversal check (CWE-22)
    project_root = get_project_root()
    try:
        entry_file = validate_path_within_base(entry_file, project_root)
    except ValueError:
        print(f"Error: Path traversal detected: {args.entry_file}")
        return 1

    # File existence check
    if not entry_file.exists():
        print(f"Error: Entry file not found: {entry_file}")
        return 1

    # Load existing file
    try:
        meta, _ = load_entry_file(entry_file)
    except IOError as e:
        print(f"Error: {e}")
        return 1

    # _meta section check
    if not meta:
        print(f"Error: Entry file missing _meta section: {entry_file}")
        return 1

    # source_file check
    if 'source_file' not in meta:
        print(f"Error: Entry file missing _meta.source_file: {entry_file}")
        return 1

    # Error mode: write error status and exit
    if args.error:
        if not args.error_message:
            print("Error: --error-message is required with --error")
            return 2
        if not write_error_yaml(entry_file, meta, args.error_message, target):
            return 4
        print(f"Entry error: {entry_file}")
        print(f"  source_file: {meta['source_file']}")
        print(f"  status: pending (error_message set)")
        print(f"  error_message: {args.error_message}")
        return 0

    # completed status check
    if meta.get('status') == 'completed' and not args.force:
        print(f"Error: Entry file already completed: {entry_file}")
        print("  Use --force to overwrite")
        return 1

    # Required fields check (normal mode)
    missing = []
    for field in ['title', 'purpose', 'content_details', 'applicable_tasks', 'keywords']:
        if getattr(args, field.replace('-', '_')) is None:
            missing.append(f'--{field.replace("_", "-")}')
    if missing:
        print(f"Error: Required arguments in normal mode: {', '.join(missing)}")
        return 2

    # Parse arrays
    content_details = parse_separated(args.content_details)
    applicable_tasks = parse_separated(args.applicable_tasks)
    keywords = parse_separated(args.keywords)
    # Validation
    valid = True
    if not validate_array('content_details', content_details, MIN_CONTENT_DETAILS):
        valid = False
    if not validate_array('applicable_tasks', applicable_tasks, MIN_APPLICABLE_TASKS):
        valid = False
    if not validate_array('keywords', keywords, MIN_KEYWORDS):
        valid = False

    if not valid:
        return 3

    # Update _meta (preserve doc_type from pending YAML)
    updated_meta = {
        'source_file': meta['source_file'],
        'doc_type': meta.get('doc_type', ''),
        'status': 'completed',
        'updated_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    }

    # Entry data
    entry = {
        'title': args.title,
        'purpose': args.purpose,
        'content_details': content_details,
        'applicable_tasks': applicable_tasks,
        'keywords': keywords
    }
    # Write
    if not write_entry_yaml(entry_file, updated_meta, entry, target):
        return 4

    # Success message
    print(f"Entry completed: {entry_file}")
    print(f"  source_file: {updated_meta['source_file']}")
    print(f"  status: {updated_meta['status']}")
    print(f"  updated_at: {updated_meta['updated_at']}")

    return 0


if __name__ == '__main__':
    sys.exit(main())
