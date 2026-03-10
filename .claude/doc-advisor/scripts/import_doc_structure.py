#!/usr/bin/env python3
"""
Import .doc_structure.yaml into config.yaml.

Reads .doc_structure.yaml and writes root_dirs and doc_types_map into
the corresponding sections of config.yaml. This is called by setup.sh
during installation (Route A in DES-005).

Usage:
    python3 import_doc_structure.py <doc_structure_path> <config_yaml_path>

Created by k_terada
"""

import os
import re
import sys
from pathlib import Path


def _yaml_escape(s):
    """Escape a string value for safe YAML output."""
    if not s:
        return '""'
    s = str(s)
    first_char_indicators = set('-?:,[]{}#&*!|>\'"% @`~')
    needs_quotes = s[0] in first_char_indicators
    if not needs_quotes:
        needs_quotes = ': ' in s or ' #' in s or '"' in s or "'" in s
    if not needs_quotes:
        needs_quotes = s.endswith(':') or s.endswith(' ')
    if needs_quotes:
        escaped = s.replace('\\', '\\\\').replace('"', '\\"')
        return f'"{escaped}"'
    return s


def parse_doc_structure(content):
    """
    Parse .doc_structure.yaml content.

    Supports the following structure:
        rules:
          rule:
            paths: [rules/]
          reference:
            paths:
              - references/
            exclude: [archive/]
        specs:
          requirement:
            paths: [specs/requirements/]
          design:
            paths: [specs/design/]

    Returns:
        dict: {category: {doc_type: {paths: [...], exclude: [...]}}}
    """
    result = {}
    current_section = None
    current_doc_type = None
    current_list = None

    for line in content.split('\n'):
        stripped = line.strip()

        # Skip comments and empty lines
        if not stripped or stripped.startswith('#'):
            continue

        indent = len(line) - len(line.lstrip())

        if ':' in stripped and not stripped.startswith('- '):
            key, _, value = stripped.partition(':')
            key = key.strip()
            value = value.strip()

            if indent == 0:
                if value:
                    result[key] = value.strip('"\'')
                else:
                    current_section = key
                    result[key] = {}
                    current_doc_type = None
                    current_list = None
            elif indent == 2 and current_section:
                current_doc_type = key
                result[current_section][key] = {}
                current_list = None
            elif indent == 4 and current_section and current_doc_type:
                if value:
                    parsed = _parse_inline_array(value)
                    if parsed is not None:
                        result[current_section][current_doc_type][key] = parsed
                        current_list = result[current_section][current_doc_type][key]
                    else:
                        result[current_section][current_doc_type][key] = value.strip('"\'')
                        current_list = None
                else:
                    result[current_section][current_doc_type][key] = []
                    current_list = result[current_section][current_doc_type][key]
        elif stripped.startswith('- ') and current_list is not None:
            item = stripped[2:].strip().strip('"\'')
            if '  #' in item and not item.startswith('"'):
                item = item[:item.index('  #')].strip()
            current_list.append(item)

    return result


def _parse_inline_array(value):
    """Parse YAML inline array like [a, b, c]."""
    if value.startswith('[') and value.endswith(']'):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [item.strip().strip('"\'') for item in inner.split(',')]
    return None


def extract_config_data(structure):
    """
    Extract root_dirs and doc_types_map from parsed .doc_structure.yaml.

    Returns:
        dict: {category: {'root_dirs': [...], 'doc_types_map': {path: doc_type}}}
    """
    result = {}
    for category in ('rules', 'specs'):
        category_data = structure.get(category, {})
        root_dirs = []
        doc_types_map = {}

        for doc_type_name, doc_type_info in category_data.items():
            if isinstance(doc_type_info, dict):
                paths = doc_type_info.get('paths', [])
                if isinstance(paths, str):
                    paths = [paths]
                root_dirs.extend(paths)
                for p in paths:
                    doc_types_map[p] = doc_type_name

        # Deduplicate while preserving order
        seen = set()
        unique_dirs = []
        for d in root_dirs:
            if d not in seen:
                seen.add(d)
                unique_dirs.append(d)

        if unique_dirs:
            result[category] = {
                'root_dirs': unique_dirs,
                'doc_types_map': doc_types_map,
            }

    return result


def update_config_yaml(config_content, config_data):
    """
    Update config.yaml content with root_dirs and doc_types_map.

    Replaces commented `# root_dirs: []` lines with actual values
    and inserts doc_types_map entries.

    Args:
        config_content: Original config.yaml text
        config_data: Dict from extract_config_data()

    Returns:
        str: Updated config.yaml content
    """
    lines = config_content.split('\n')
    result = []
    current_section = None
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Track current top-level section
        if stripped and not stripped.startswith('#') and ':' in stripped:
            indent = len(line) - len(line.lstrip())
            if indent == 0:
                key = stripped.partition(':')[0].strip()
                if key in ('rules', 'specs', 'common'):
                    current_section = key

        # Replace root_dirs line (commented or active)
        if current_section in config_data and re.match(
            r'^\s*#?\s*root_dirs:', line
        ):
            data = config_data[current_section]
            root_dirs = data['root_dirs']
            doc_types_map = data.get('doc_types_map', {})

            # Write root_dirs
            result.append('  root_dirs:')
            for d in root_dirs:
                result.append(f'    - {_yaml_escape(d)}')

            # Write doc_types_map
            if doc_types_map:
                result.append('  doc_types_map:')
                for path, doc_type in doc_types_map.items():
                    result.append(f'    {_yaml_escape(path)}: {_yaml_escape(doc_type)}')

            # Skip existing root_dirs block entries (  - item lines)
            i += 1
            while i < len(lines) and re.match(r'^\s{4,}-\s', lines[i]):
                i += 1

            # Skip existing doc_types_map block (commented or active) and its entries
            if i < len(lines) and re.match(r'^\s*#?\s*doc_types_map:', lines[i]):
                i += 1
                while i < len(lines) and re.match(r'^\s{4,}\S', lines[i]):
                    i += 1
            continue

        # Skip commented doc_types_map line (replaced above with root_dirs)
        if current_section in config_data and re.match(
            r'^\s*#\s*doc_types_map:', line
        ):
            i += 1
            continue

        result.append(line)
        i += 1

    return '\n'.join(result)


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <doc_structure_path> <config_yaml_path>",
              file=sys.stderr)
        sys.exit(1)

    doc_structure_path = sys.argv[1]
    config_yaml_path = sys.argv[2]

    # Path traversal check (CWE-22)
    cwd = Path.cwd().resolve()
    for arg_path in [doc_structure_path, config_yaml_path]:
        resolved = Path(arg_path).resolve()
        if not str(resolved).startswith(str(cwd) + os.sep) and resolved != cwd:
            print(f"Error: Path traversal detected: {arg_path}", file=sys.stderr)
            sys.exit(1)

    # Read .doc_structure.yaml
    try:
        with open(doc_structure_path, 'r', encoding='utf-8') as f:
            doc_structure_content = f.read()
    except FileNotFoundError:
        print(f"Error: {doc_structure_path} not found", file=sys.stderr)
        sys.exit(1)

    # Read config.yaml
    try:
        with open(config_yaml_path, 'r', encoding='utf-8') as f:
            config_content = f.read()
    except FileNotFoundError:
        print(f"Error: {config_yaml_path} not found", file=sys.stderr)
        sys.exit(1)

    # Parse and extract
    structure = parse_doc_structure(doc_structure_content)
    config_data = extract_config_data(structure)

    if not config_data:
        print("No rules or specs categories found in .doc_structure.yaml",
              file=sys.stderr)
        sys.exit(0)

    # Update config.yaml
    updated = update_config_yaml(config_content, config_data)

    # Write back
    with open(config_yaml_path, 'w', encoding='utf-8') as f:
        f.write(updated)

    # Report what was imported
    for category, data in config_data.items():
        dirs = ', '.join(data['root_dirs'])
        print(f"  {category}: root_dirs=[{dirs}]")


if __name__ == '__main__':
    main()
