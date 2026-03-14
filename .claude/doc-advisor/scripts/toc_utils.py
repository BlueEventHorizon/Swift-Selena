#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# doc-advisor-version-xK9XmQ: 4.4
"""
ToC Auto-Generation Common Utilities

Common functions used by merge-rules-toc, merge-specs-toc, create-toc-checksums.
Uses only standard library.
"""

import fnmatch
import os
import re
import shutil
import unicodedata
from pathlib import Path


# System files that are always excluded (not configurable)
SYSTEM_EXCLUDE_PATTERNS_RULES = ['.toc_work', 'rules_toc.yaml', '.toc_checksums.yaml']
SYSTEM_EXCLUDE_PATTERNS_SPECS = ['.toc_work', 'specs_toc.yaml', '.toc_checksums.yaml']


def get_system_exclude_patterns(category):
    """
    Get system exclude patterns that are always applied.

    Args:
        category: 'rules' or 'specs'

    Returns:
        list: System exclude patterns
    """
    if category == 'rules':
        return SYSTEM_EXCLUDE_PATTERNS_RULES.copy()
    elif category == 'specs':
        return SYSTEM_EXCLUDE_PATTERNS_SPECS.copy()
    return []


def normalize_path(path_str):
    """
    Normalize path string to NFC for consistent comparison.

    macOS stores filenames in NFD (decomposed) form, while config files
    and user input typically use NFC (composed) form. This causes string
    comparison to fail for Japanese characters with dakuten/handakuten
    (e.g., プ as U+30D7 vs フ+゚ as U+30D5+U+309A).
    """
    return unicodedata.normalize('NFC', str(path_str))


def get_project_root():
    """
    Detect project root (searches for .git or .claude directory)

    Returns:
        Path: Path to project root

    Raises:
        RuntimeError: When project root cannot be found
    """
    current = Path(__file__).parent.absolute()

    # Search up to 10 levels
    for _ in range(10):
        if (current / ".git").exists() or (current / ".claude").exists():
            return current
        parent = current.parent
        if parent == current:
            break
        current = parent

    raise RuntimeError("Project root not found (.git or .claude directory required)")


def validate_path_within_base(path, base_dir):
    """
    Validate that a path resolves within the base directory.
    Prevents path traversal attacks via ../ sequences (CWE-22).
    Supports symlinked directories by checking the logical path
    (without resolving symlinks) for containment, then returning
    the joined path for file access.

    Args:
        path: Path to validate (str or Path)
        base_dir: Allowed base directory (str or Path)

    Returns:
        Path: The joined path (base_dir / path) for existence checks

    Raises:
        ValueError: If path contains traversal sequences escaping base_dir

    Note:
        Symlinks within base_dir may point outside it; such access is intentionally
        permitted (project-configured symlinks). Only ../ traversal sequences that
        escape base_dir in the logical path are rejected.
    """
    # シンボリックリンクを解決せずに論理パスで包含チェック
    # （.. を正規化しつつシンボリックリンクは辿らない）
    joined = Path(base_dir, path)
    # os.path.normpath で .. を解決（シンボリックリンクは辿らない）
    normalized = os.path.normpath(str(joined))
    base_normalized = os.path.normpath(str(base_dir))
    if not normalized.startswith(base_normalized + os.sep) and normalized != base_normalized:
        raise ValueError(f"Path traversal detected: {path}")
    return joined


def resolve_config_path(config_value, default_base, project_root):
    """
    Resolve configuration path value.

    If the path starts with '.claude/', it is resolved relative to project_root.
    Otherwise, it is resolved relative to default_base.

    Args:
        config_value: Path string from configuration
        default_base: Default base directory (e.g., SPECS_DIR, RULES_DIR)
        project_root: Project root directory

    Returns:
        Path: Resolved absolute path
    """
    path_str = str(config_value).rstrip('/')
    if path_str.startswith('.claude/'):
        return project_root / path_str
    return default_base / path_str


def find_config_file():
    """
    Find configuration file.

    Location: {CWD}/.claude/doc-advisor/config.yaml

    Returns:
        Path: Path to configuration file

    Raises:
        FileNotFoundError: When no configuration file is found
    """
    project_config = Path.cwd() / ".claude/doc-advisor/config.yaml"
    if project_config.exists():
        return project_config

    raise FileNotFoundError(
        "Configuration file not found. Please create one at:\n"
        "  - .claude/doc-advisor/config.yaml\n"
        "Run setup.sh to generate the configuration file."
    )


def load_config(target=None):
    """
    Load config.yaml and return configuration dictionary.

    config.yaml is the sole runtime configuration (FR-08-1).
    root_dirs and doc_types_map must be pre-configured by setup.sh
    (from .doc_structure.yaml) or /setup-config skill.
    This function does NOT fall back to .doc_structure.yaml at runtime.

    Args:
        target: 'rules' or 'specs'. If specified, returns only that section

    Returns:
        dict: Configuration dictionary
    """
    try:
        config_path = find_config_file()
    except FileNotFoundError:
        # Return default configuration if no file found
        defaults = _get_default_config()
        if target:
            return defaults.get(target, {})
        return defaults

    with open(config_path, 'r', encoding='utf-8') as f:
        content = f.read()

    config = _parse_config_yaml(content)

    # Backward compatibility: root_dir (string) → root_dirs (list)
    for section in ('rules', 'specs'):
        if section in config:
            sec = config[section]
            if 'root_dir' in sec and 'root_dirs' not in sec:
                sec['root_dirs'] = [sec.pop('root_dir')]

    if target:
        return config.get(target, {})
    return config


def _get_default_config():
    """Return default configuration"""
    return {
        'rules': {
            'root_dirs': ['rules/'],
            'toc_file': '.claude/doc-advisor/toc/rules/rules_toc.yaml',
            'checksums_file': '.claude/doc-advisor/toc/rules/.toc_checksums.yaml',
            'work_dir': '.claude/doc-advisor/toc/rules/.toc_work/',
            'patterns': {
                'target_glob': '**/*.md',
                'exclude': []  # User-defined only; system files excluded separately
            },
            'output': {
                'header_comment': 'Development documentation search index for query-rules skill',
                'metadata_name': 'Development Document Search Index'
            }
        },
        'specs': {
            'root_dirs': ['specs/'],
            'toc_file': '.claude/doc-advisor/toc/specs/specs_toc.yaml',
            'checksums_file': '.claude/doc-advisor/toc/specs/.toc_checksums.yaml',
            'work_dir': '.claude/doc-advisor/toc/specs/.toc_work/',
            'patterns': {
                'target_glob': '**/*.md',
                'exclude': []  # User-defined only; system files excluded separately
            },
            'output': {
                'header_comment': 'Project specification document search index for query-specs skill',
                'metadata_name': 'Project Specification Document Search Index'
            }
        },
        'common': {
            'parallel': {
                'max_workers': 5,
                'fallback_to_serial': True
            }
        }
    }


def _parse_config_yaml(content):
    """
    Parse config.yaml (simple YAML parser)

    Handles up to 4 levels of nesting:
    - Level 0: Top-level sections (rules, specs, common)
    - Level 2: Subsections (root_dirs, patterns, output)
    - Level 4: Sub-subsections (target_glob, exclude)
    - Level 6: Items (key-value pairs or list items)
    """
    result = {}
    current_section = None
    current_subsection = None
    current_subsubsection = None
    current_list = None
    current_dict = None

    lines = content.split('\n')

    for i, line in enumerate(lines):
        stripped = line.strip()

        # Skip comments and empty lines
        if not stripped or stripped.startswith('#'):
            continue

        # Calculate indent level
        indent = len(line) - len(line.lstrip())

        if ':' in stripped and not stripped.startswith('- '):
            key, _, value = stripped.partition(':')
            key = key.strip()
            value = value.strip()

            if indent == 0:
                # Top-level section
                current_section = key
                result[key] = {}
                current_subsection = None
                current_subsubsection = None
                current_list = None
                current_dict = None
            elif indent == 2 and current_section:
                # Subsection
                current_subsection = key
                if value:
                    result[current_section][key] = _parse_value(value)
                    current_list = None
                else:
                    # Look ahead to determine if list or dict
                    if _lookahead_is_list(lines, i + 1, parent_indent=2):
                        result[current_section][key] = []
                        current_list = result[current_section][key]
                    else:
                        result[current_section][key] = {}
                        current_list = None
                current_subsubsection = None
                current_dict = None
            elif indent == 4 and current_section and current_subsection:
                # Sub-subsection - look ahead to determine if list or dict
                current_subsubsection = key
                if value:
                    result[current_section][current_subsection][key] = _parse_value(value)
                    current_list = None
                    current_dict = None
                else:
                    # Look ahead to determine structure type
                    is_list = _lookahead_is_list(lines, i + 1)
                    if is_list:
                        result[current_section][current_subsection][key] = []
                        current_list = result[current_section][current_subsection][key]
                        current_dict = None
                    else:
                        result[current_section][current_subsection][key] = {}
                        current_dict = result[current_section][current_subsection][key]
                        current_list = None
            elif indent == 6 and current_dict is not None:
                # Key-value pair inside sub-subsection dict
                current_dict[key] = _parse_value(value) if value else ''
        elif stripped.startswith('- ') and current_list is not None:
            item = stripped[2:].strip().strip('"\'')
            # Strip inline comments (e.g., "plan  # comment" → "plan")
            if '  #' in item and not item.startswith('"'):
                item = item[:item.index('  #')].strip()
            current_list.append(item)

    return result


def _lookahead_is_list(lines, start_idx, parent_indent=4):
    """
    Look ahead in lines to determine if the next content is a list or dict.

    Args:
        lines: List of all lines
        start_idx: Index to start looking from
        parent_indent: Indent level of the parent key

    Returns:
        bool: True if next content is a list (starts with '- ')
    """
    for i in range(start_idx, min(start_idx + 10, len(lines))):
        line = lines[i]
        stripped = line.strip()

        # Skip comments and empty lines
        if not stripped or stripped.startswith('#'):
            continue

        indent = len(line) - len(line.lstrip())

        # If we hit a line with less or equal indent, stop looking
        if indent <= parent_indent:
            break

        # Check if it's a list item or key-value
        if stripped.startswith('- '):
            return True
        if ':' in stripped:
            return False

    # Default to list for backward compatibility
    return True


def _parse_value(value):
    """Parse value (string, number, boolean, or list including inline list format)."""
    value = value.strip()

    # Strip inline comments (not inside quotes)
    if not value.startswith('"') and '  #' in value:
        value = value[:value.index('  #')].strip()

    # Inline list: [] or [a, b, c]
    if value.startswith('[') and value.endswith(']'):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [item.strip().strip('"\'') for item in inner.split(',')]

    value = value.strip('"\'')

    if value.lower() == 'true':
        return True
    if value.lower() == 'false':
        return False

    try:
        return int(value)
    except ValueError:
        pass

    return value


def expand_root_dir_globs(dirs, project_root):
    """
    Expand glob patterns in root_dirs paths.

    config.yaml root_dirs supports patterns like "specs/*/requirements/"
    which need to be expanded to actual directories before file scanning.

    Args:
        dirs: List of directory path strings (may contain globs)
        project_root: Path to project root

    Returns:
        list: Expanded directory path strings
    """
    expanded = []
    for dir_path in dirs:
        if '*' in dir_path or '?' in dir_path:
            pattern = dir_path.rstrip('/')
            matches = sorted(project_root.glob(pattern))
            for match in matches:
                if match.is_dir():
                    rel = str(match.relative_to(project_root))
                    expanded.append(rel + '/')
        else:
            expanded.append(dir_path)
    return expanded if expanded else dirs


def parse_simple_yaml(content):
    """
    Simple YAML parser (for entry files)

    Separates _meta section and normal entries.

    Args:
        content: YAML file content

    Returns:
        tuple: (meta_dict, entry_dict)
    """
    result = {}
    current_key = None
    current_list = None
    in_meta = False
    meta = {}

    lines = content.split('\n')
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped or stripped.startswith('#'):
            i += 1
            continue

        if stripped == '_meta:':
            in_meta = True
            i += 1
            continue

        if in_meta:
            if line.startswith('  ') and ':' in stripped:
                key, _, value = stripped.partition(':')
                meta[key.strip()] = value.strip().strip('"\'')
            elif not line.startswith(' '):
                in_meta = False
            else:
                i += 1
                continue

        if not line.startswith(' ') and ':' in line:
            key, _, value = line.partition(':')
            key = key.strip()
            value = value.strip()

            if value == '[]':
                # Inline empty array (e.g., "keywords: []")
                current_key = key
                current_list = []
                result[key] = current_list
            elif value:
                result[key] = value.strip('"\'')
                current_key = None
                current_list = None
            else:
                current_key = key
                current_list = []
                result[key] = current_list
            i += 1
            continue

        if current_list is not None and stripped.startswith('- '):
            item = stripped[2:].strip().strip('"\'')
            current_list.append(item)
            i += 1
            continue

        i += 1

    return meta, result


def load_entry_file(filepath):
    """
    Load and parse entry file

    Args:
        filepath: File path (str or Path)

    Returns:
        tuple: (meta_dict, entry_dict)

    Raises:
        IOError: When file read fails
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        return parse_simple_yaml(content)
    except (IOError, OSError, PermissionError) as e:
        raise IOError(f"Entry file read error: {filepath} - {e}") from e


def yaml_escape(s):
    """
    Escape string for YAML output

    Args:
        s: String to escape

    Returns:
        str: Escaped string
    """
    if not s:
        return '""'

    # Convert to string if not already
    s = str(s)

    # Check if first character is a YAML indicator (block plain scalar rule)
    first_char_indicators = set('-?:,[]{}#&*!|>\'"% @`~')
    needs_quotes = s[0] in first_char_indicators

    # Patterns special ANYWHERE in block plain scalar
    # ": " and " #" are YAML spec restrictions
    # '"' and "'" cause round-trip issues with parse_simple_yaml's strip()
    if not needs_quotes:
        needs_quotes = ': ' in s or ' #' in s or '"' in s or "'" in s

    # Trailing colon or trailing space
    if not needs_quotes:
        needs_quotes = s.endswith(':') or s.endswith(' ')

    # Control characters always need quoting
    if not needs_quotes:
        needs_quotes = any(c in s for c in '\n\r\t')

    # Check if it looks like a number (would be parsed as int/float)
    if not needs_quotes:
        try:
            float(s)
            needs_quotes = True
        except ValueError:
            pass

    # Check if it's a YAML boolean or null keyword
    if s.lower() in ('true', 'false', 'yes', 'no', 'on', 'off', 'null', 'none', '~'):
        needs_quotes = True

    if needs_quotes:
        # Escape backslash first, then double quote
        escaped = s.replace('\\', '\\\\').replace('"', '\\"')
        # Escape newline and tab
        escaped = escaped.replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
        return f'"{escaped}"'

    return s


def backup_existing_file(file_path):
    """
    Backup existing file (with .bak extension)

    Args:
        file_path: File path to backup (str or Path)
    """
    file_path = Path(file_path)
    if file_path.exists():
        backup_path = file_path.with_suffix('.yaml.bak')
        shutil.copy(file_path, backup_path)
        print(f"Backup created: {backup_path}")


def load_checksums(checksums_file):
    """
    Get file list from checksum file

    Args:
        checksums_file: Path to checksum file (str or Path)

    Returns:
        set: Set of file paths
    """
    checksums_file = Path(checksums_file)

    if not checksums_file.exists():
        return set()

    try:
        with open(checksums_file, 'r', encoding='utf-8') as f:
            content = f.read()

        files = set()
        in_checksums = False
        for line in content.split('\n'):
            stripped = line.strip()
            if stripped == 'checksums:':
                in_checksums = True
                continue
            if in_checksums and ': ' in stripped:
                parts = stripped.rsplit(': ', 1)
                if len(parts) == 2:
                    filepath = parts[0].strip()
                    files.add(filepath)

        return files
    except Exception as e:
        print(f"Warning: Checksum file read error: {e}")
        print("Fallback: Skipping deletion detection")
        return set()


def cleanup_work_dir(work_dir):
    """
    Delete work directory

    Args:
        work_dir: Directory path to delete (str or Path)

    Returns:
        bool: True on success, False on failure
    """
    work_dir = Path(work_dir)
    if work_dir.exists():
        try:
            shutil.rmtree(work_dir)
            print(f"Cleanup complete: {work_dir}")
            return True
        except (OSError, PermissionError) as e:
            print(f"Warning: Cleanup failed: {work_dir} - {e}")
            print("   Please delete manually")
            return False
    return True


def extract_id_from_filename(filename):
    """
    DEPRECATED: This function is no longer recommended.

    Document identification should use file path instead of filename-based ID.
    See DES-003_document_identifier.md for details.

    This function is kept for backward compatibility but should not be used
    in new code. The file path (relative to the root directory) serves as
    the unique identifier for each document.

    ---
    Original docstring:
    Extract document ID from filename (generic regex version)

    Args:
        filename: Filename (path also accepted)

    Returns:
        str or None: Extracted ID, None if not found

    Examples:
        'SCR-001_foo.md' → 'SCR-001'
        'DES-042_bar.md' → 'DES-042'
        'CUSTOM-123_baz.md' → 'CUSTOM-123'
    """
    import warnings
    warnings.warn(
        "extract_id_from_filename is deprecated. Use file path as document identifier.",
        DeprecationWarning,
        stacklevel=2
    )
    # Get only filename part if path is provided
    if '/' in filename:
        filename = filename.split('/')[-1]

    # Match [A-Z]+-\d+ pattern
    match = re.match(r'([A-Z]+-\d+)', filename)
    if match:
        return match.group(1)
    return None


def should_exclude(filepath, root_dir, exclude_patterns):
    """
    Check if file should be excluded

    Args:
        filepath: File path to check (Path)
        root_dir: Root directory (Path)
        exclude_patterns: List of exclusion patterns

    Returns:
        bool: True if should be excluded

    Note:
        - All patterns are matched against directory path only (filename excluded)
        - Patterns containing '/' are matched as path substring
        - Patterns without '/' are matched as exact directory name
        - This prevents 'plan' from excluding 'planning.md'
        - NFC normalization is applied for macOS NFD compatibility
    """
    rel_path = normalize_path(filepath.relative_to(root_dir))
    path_parts = rel_path.split('/')
    dir_parts = path_parts[:-1]  # ファイル名を除く
    dir_path = '/'.join(dir_parts)  # ディレクトリパスのみ

    for pattern in exclude_patterns:
        # 先頭・末尾の / を除去し NFC 正規化
        normalized = normalize_path(pattern.strip('/'))

        if '/' in normalized:
            # パターンに / が含まれる場合はパス部分文字列としてマッチ
            if normalized in dir_path:
                return True
        else:
            # ディレクトリ名として完全一致でチェック
            if normalized in dir_parts:
                return True
    return False


def rglob_follow_symlinks(root_dir, pattern):
    """
    シンボリックリンクを follow して再帰的にファイルを検索する。

    inode を追跡してシンボリックリンクループを防止し、
    同じファイルへの複数パスを重複排除する。

    Args:
        root_dir: 検索開始ディレクトリ (Path or str)
        pattern: glob パターン (例: "*.md", "**/*.md")

    Yields:
        Path: マッチしたファイルパス

    Note:
        - シンボリックリンクのループを検出して無限再帰を防止
        - 同じファイルへの複数パス（シンボリックリンク経由）は一度だけ yield
        - "**/" を含むパターンは再帰的に検索、含まないパターンは直下のみ
    """
    root_dir = Path(root_dir)
    seen_inodes = set()

    # パターンを解析
    # "**/*.md" -> 再帰的に検索、"*.md" -> 直下のみ
    if '**' in pattern:
        # "**/*.md" -> "*.md", "**/*.yaml" -> "*.yaml"
        file_pattern = pattern.replace('**/', '').replace('**', '')
        if not file_pattern:
            file_pattern = '*'
        recursive = True
    else:
        file_pattern = pattern
        recursive = False

    for dirpath, dirnames, filenames in os.walk(root_dir, followlinks=True):
        current_path = Path(dirpath)

        # ディレクトリの inode をチェック（ループ防止）
        try:
            stat_info = current_path.stat()
            dir_inode = (stat_info.st_dev, stat_info.st_ino)
            if dir_inode in seen_inodes:
                # シンボリックリンクループを検出、このディレクトリをスキップ
                dirnames.clear()  # サブディレクトリへの再帰を防止
                continue
            seen_inodes.add(dir_inode)
        except OSError:
            # stat に失敗した場合はスキップ
            continue

        # ファイルをマッチング
        for filename in filenames:
            if fnmatch.fnmatch(filename, file_pattern):
                filepath = current_path / filename
                # ファイルの inode もチェック（同じファイルへの複数パスを防止）
                try:
                    file_stat = filepath.stat()
                    file_inode = (file_stat.st_dev, file_stat.st_ino)
                    if file_inode in seen_inodes:
                        continue
                    seen_inodes.add(file_inode)
                except OSError:
                    continue
                yield filepath

        # 非再帰モードの場合は最初のディレクトリのみ
        if not recursive:
            break
