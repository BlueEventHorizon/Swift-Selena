#!/usr/bin/env python3
"""
Merge old config.yaml user settings into new template config.yaml.

Preserves user-customized settings from old config while keeping the new
template structure. Processes in two stages:

  1. Version migrations: Apply structural changes for major version upgrades.
  2. User settings:     Carry over root_dirs, doc_types_map, exclude, etc.

Usage:
    python3 merge_config.py <old_config_path> <new_config_path>

Created by k_terada
"""

import os
import re
import sys
from pathlib import Path

# Import common utilities from toc_utils (installed in the same directory)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from toc_utils import (  # noqa: E402
    _parse_value,
    _lookahead_is_list,
    _parse_config_yaml,
    yaml_escape as _yaml_escape,
)


# ==============================================================================
# Version detection
# ==============================================================================

def get_major_version(content):
    """
    Extract major version number from config.yaml content.

    Parses the doc-advisor version identifier:
        # doc-advisor-version-xK9XmQ: 4.3

    Version format is "X.Y" where X is the major version.
    A config.yaml structure change must accompany a major version bump.

    Returns:
        int | None: Major version integer (e.g. 4 for "4.3"), or None if
                    not found or unparseable.
    """
    for line in content.split('\n'):
        stripped = line.strip()
        if 'doc-advisor-version-xK9XmQ:' in stripped:
            _, _, version_str = stripped.partition('doc-advisor-version-xK9XmQ:')
            version_str = version_str.strip()
            try:
                return int(version_str.split('.')[0])
            except (ValueError, IndexError):
                return None
    return None


# ==============================================================================
# Version migration registry
# ==============================================================================

# MIGRATIONS: {new_major: migration_fn}
#
# migration_fn signature:
#   fn(new_content: str, old_config_dict: dict) -> str
#
# How to add a migration when config.yaml structure changes:
#   1. Bump the major version in setup.sh (e.g. 4.x → 5.0)
#   2. Add an entry here: MIGRATIONS[5] = migrate_to_v5
#   3. Implement migrate_to_v5(new_content, old_dict) -> str
#   4. Document the change in specs/design/DES-001 (migration history section)
#
MIGRATIONS = {
    # Example (v5.0 structure change):
    # 5: migrate_to_v5,
}


def apply_version_migrations(old_major, new_major, new_content, old_config_dict):
    """
    Apply version-specific structural migrations in ascending order.

    Only migrations where old_major < new_major are applied,
    so multi-version upgrades (e.g. 4→6) are handled correctly.

    Args:
        old_major (int | None): Major version of old config, or None if unknown.
        new_major (int | None): Major version of new config, or None if unknown.
        new_content (str): New config.yaml text (post-template copy).
        old_config_dict (dict): Parsed old config (for migration functions).

    Returns:
        str: Updated new_content after all applicable migrations.
    """
    if not MIGRATIONS:
        return new_content

    if old_major is None:
        # Unknown version: apply all migrations as a safe default
        targets = sorted(MIGRATIONS.keys())
    elif new_major is None:
        # New version unknown: skip migrations
        return new_content
    else:
        targets = [v for v in sorted(MIGRATIONS.keys())
                   if old_major < v <= new_major]

    for v in targets:
        new_content = MIGRATIONS[v](new_content, old_config_dict)
        # Update old_config_dict from intermediate result so that
        # subsequent migrations see the transformed structure
        old_config_dict = _parse_config_yaml(new_content)

    return new_content


# ==============================================================================
# User settings extraction
# ==============================================================================

# Default output settings per section (to detect user customizations)
_DEFAULT_OUTPUT = {
    'rules': {
        'header_comment': 'Development documentation search index for query-rules skill',
        'metadata_name': 'Development Documentation Search Index',
    },
    'specs': {
        'header_comment': 'Project specification document search index for query-specs skill',
        'metadata_name': 'Project Specification Document Search Index',
    },
}

_DEFAULT_PARALLEL = {
    'max_workers': 5,
    'fallback_to_serial': True,
}


def extract_user_settings(old_dict):
    """
    Extract user-customized settings from the parsed old config.

    A setting is considered "user-customized" if:
      - root_dirs / doc_types_map / exclude: non-empty
      - output fields: value differs from the template default
      - parallel fields: value differs from the template default

    Returns:
        dict: Nested dict of settings to carry over. Empty if nothing to carry.
    """
    settings = {}

    for section in ('rules', 'specs'):
        section_data = old_dict.get(section, {})
        section_settings = {}

        # root_dirs: carry over if non-empty
        root_dirs = section_data.get('root_dirs', [])
        if isinstance(root_dirs, list) and root_dirs:
            section_settings['root_dirs'] = root_dirs

        # doc_types_map: carry over if non-empty
        doc_types_map = section_data.get('doc_types_map', {})
        if isinstance(doc_types_map, dict) and doc_types_map:
            section_settings['doc_types_map'] = doc_types_map

        # patterns.exclude: carry over if non-empty
        # Also collect section-level exclude (legacy: some configs placed it at indent=2)
        # Both are merged into patterns.exclude (where toc scripts actually read it)
        section_exclude = section_data.get('exclude', [])
        if not isinstance(section_exclude, list):
            section_exclude = []
        patterns_exclude = section_data.get('patterns', {}).get('exclude', [])
        if not isinstance(patterns_exclude, list):
            patterns_exclude = []
        combined_exclude = list(dict.fromkeys(section_exclude + patterns_exclude))
        if combined_exclude:
            section_settings.setdefault('patterns', {})['exclude'] = combined_exclude

        # output.header_comment: carry over if customized
        header_comment = section_data.get('output', {}).get('header_comment')
        if (header_comment and
                header_comment != _DEFAULT_OUTPUT[section]['header_comment']):
            section_settings.setdefault('output', {})['header_comment'] = header_comment

        # output.metadata_name: carry over if customized
        metadata_name = section_data.get('output', {}).get('metadata_name')
        if (metadata_name and
                metadata_name != _DEFAULT_OUTPUT[section]['metadata_name']):
            section_settings.setdefault('output', {})['metadata_name'] = metadata_name

        if section_settings:
            settings[section] = section_settings

    # common.parallel settings
    parallel = old_dict.get('common', {}).get('parallel', {})
    common_settings = {}

    max_workers = parallel.get('max_workers')
    if max_workers is not None and max_workers != _DEFAULT_PARALLEL['max_workers']:
        common_settings.setdefault('parallel', {})['max_workers'] = max_workers

    fallback = parallel.get('fallback_to_serial')
    if fallback is not None and fallback != _DEFAULT_PARALLEL['fallback_to_serial']:
        common_settings.setdefault('parallel', {})['fallback_to_serial'] = fallback

    if common_settings:
        settings['common'] = common_settings

    return settings


# ==============================================================================
# User settings application (text-based)
# ==============================================================================

def apply_user_settings(new_content, user_settings):
    """
    Apply user settings to new config.yaml text using line-by-line processing.

    Preserves comments and YAML formatting from the new template.

    Args:
        new_content (str): New config.yaml text (post-migration).
        user_settings (dict): From extract_user_settings().

    Returns:
        str: Updated config.yaml text.
    """
    if not user_settings:
        return new_content

    lines = new_content.split('\n')
    result = []
    current_section = None    # 'rules', 'specs', 'common'
    current_subsection = None  # 'patterns', 'output', 'parallel', etc.
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Track current section and subsection via indentation
        if stripped and not stripped.startswith('#') and ':' in stripped:
            indent = len(line) - len(line.lstrip())
            key = stripped.partition(':')[0].strip()

            if indent == 0 and key in ('rules', 'specs', 'common'):
                current_section = key
                current_subsection = None
            elif indent == 2 and current_section:
                current_subsection = key

        # --- root_dirs / doc_types_map ---
        # Replace "# root_dirs: []" with active values from old config
        if (current_section in ('rules', 'specs') and
                current_section in user_settings and
                'root_dirs' in user_settings[current_section] and
                re.match(r'^\s*#\s*root_dirs:\s*\[\]', line)):
            data = user_settings[current_section]
            root_dirs = data['root_dirs']
            doc_types_map = data.get('doc_types_map', {})

            result.append('  root_dirs:')
            for d in root_dirs:
                result.append(f'    - {_yaml_escape(d)}')

            if doc_types_map:
                result.append('  doc_types_map:')
                for path, doc_type in doc_types_map.items():
                    result.append(f'    {_yaml_escape(path)}: {_yaml_escape(doc_type)}')

            i += 1
            continue

        # Skip "# doc_types_map:" comment (replaced inline above)
        if (current_section in ('rules', 'specs') and
                current_section in user_settings and
                'root_dirs' in user_settings[current_section] and
                re.match(r'^\s*#\s*doc_types_map:', line)):
            i += 1
            continue

        # --- patterns.exclude ---
        if (current_section in ('rules', 'specs') and
                current_section in user_settings and
                current_subsection == 'patterns' and
                re.match(r'^    exclude:\s*\[\]\s*$', line)):
            exclude = user_settings[current_section].get('patterns', {}).get('exclude', [])
            if exclude:
                result.append('    exclude:')
                for item in exclude:
                    result.append(f'      - {_yaml_escape(item)}')
            else:
                result.append(line)
            i += 1
            continue

        # --- output.header_comment ---
        if (current_section in ('rules', 'specs') and
                current_section in user_settings and
                current_subsection == 'output' and
                re.match(r'^    header_comment:', line)):
            custom = user_settings[current_section].get('output', {}).get('header_comment')
            if custom:
                result.append(f'    header_comment: {_yaml_escape(custom)}')
            else:
                result.append(line)
            i += 1
            continue

        # --- output.metadata_name ---
        if (current_section in ('rules', 'specs') and
                current_section in user_settings and
                current_subsection == 'output' and
                re.match(r'^    metadata_name:', line)):
            custom = user_settings[current_section].get('output', {}).get('metadata_name')
            if custom:
                result.append(f'    metadata_name: {_yaml_escape(custom)}')
            else:
                result.append(line)
            i += 1
            continue

        # --- common.parallel.max_workers ---
        if (current_section == 'common' and
                'common' in user_settings and
                current_subsection == 'parallel' and
                re.match(r'^    max_workers:', line)):
            custom = user_settings['common'].get('parallel', {}).get('max_workers')
            if custom is not None:
                # Preserve inline comment (e.g. "# Concurrent subagents ...")
                comment_match = re.search(r'\s{2,}#.*$', line)
                comment = comment_match.group(0) if comment_match else ''
                result.append(f'    max_workers: {custom}{comment}')
            else:
                result.append(line)
            i += 1
            continue

        # --- common.parallel.fallback_to_serial ---
        if (current_section == 'common' and
                'common' in user_settings and
                current_subsection == 'parallel' and
                re.match(r'^    fallback_to_serial:', line)):
            custom = user_settings['common'].get('parallel', {}).get('fallback_to_serial')
            if custom is not None:
                val = 'true' if custom else 'false'
                result.append(f'    fallback_to_serial: {val}')
            else:
                result.append(line)
            i += 1
            continue

        result.append(line)
        i += 1

    return '\n'.join(result)


# ==============================================================================
# Main
# ==============================================================================

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <old_config_path> <new_config_path>",
              file=sys.stderr)
        sys.exit(1)

    old_config_path = sys.argv[1]
    new_config_path = sys.argv[2]

    # Path traversal check (CWE-22)
    cwd = Path.cwd().resolve()
    for arg_path in [old_config_path, new_config_path]:
        resolved = Path(arg_path).resolve()
        if not str(resolved).startswith(str(cwd) + os.sep) and resolved != cwd:
            print(f"Error: Path traversal detected: {arg_path}", file=sys.stderr)
            sys.exit(1)

    # Read old config
    try:
        with open(old_config_path, 'r', encoding='utf-8') as f:
            old_content = f.read()
    except FileNotFoundError:
        print(f"Error: {old_config_path} not found", file=sys.stderr)
        sys.exit(1)

    # Read new config
    try:
        with open(new_config_path, 'r', encoding='utf-8') as f:
            new_content = f.read()
    except FileNotFoundError:
        print(f"Error: {new_config_path} not found", file=sys.stderr)
        sys.exit(1)

    # Detect versions
    old_major = get_major_version(old_content)
    new_major = get_major_version(new_content)

    # Parse old config
    old_config_dict = _parse_config_yaml(old_content)

    # Stage 1: Version migrations (structural changes between major versions)
    updated = apply_version_migrations(old_major, new_major, new_content, old_config_dict)

    # Stage 2: User settings (always applied)
    user_settings = extract_user_settings(old_config_dict)
    updated = apply_user_settings(updated, user_settings)

    # Write result
    with open(new_config_path, 'w', encoding='utf-8') as f:
        f.write(updated)

    # Report
    if user_settings:
        for section, data in user_settings.items():
            keys = ', '.join(str(k) for k in data.keys())
            print(f"  {section}: carried over [{keys}]")
    else:
        print("  No user settings to carry over")

    if (old_major is not None and new_major is not None and old_major < new_major):
        print(f"  Applied migrations: v{old_major} → v{new_major}")


if __name__ == '__main__':
    main()
