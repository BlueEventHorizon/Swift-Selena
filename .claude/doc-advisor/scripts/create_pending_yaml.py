#!/usr/bin/env python3
# doc-advisor-version-xK9XmQ: 4.4
"""
Generate pending YAML templates in .claude/doc-advisor/toc/{target}/.toc_work/

Usage:
    python3 .claude/doc-advisor/scripts/create_pending_yaml.py --target rules [--full]
    python3 .claude/doc-advisor/scripts/create_pending_yaml.py --target specs [--full]

Options:
    --target  Target category: rules or specs (required)
    --full    Process all files (default: changed files only)

Run from: Project root
"""

import sys
import argparse
import hashlib
import re
from datetime import datetime, timezone

from toc_utils import get_project_root, load_config, should_exclude, resolve_config_path, get_system_exclude_patterns, rglob_follow_symlinks, normalize_path, expand_root_dir_globs

# Global configuration (initialized in init_config())
CONFIG = None
PROJECT_ROOT = None
ROOT_DIRS = None  # list of (root_dir_path, root_dir_name)
TOC_WORK_DIR = None
CHECKSUMS_FILE = None
TOC_FILE = None
PATTERNS_CONFIG = None
TARGET_GLOB = None
EXCLUDE_PATTERNS = None
TARGET = None  # 'rules' or 'specs'
DOC_TYPES_MAP = None  # path → doc_type name (from config.yaml)

# Pending YAML templates
PENDING_TEMPLATE_RULES = """_meta:
  source_file: {source_file}
  doc_type: {doc_type}
  status: pending
  updated_at: null

title: null
purpose: null
content_details: []
applicable_tasks: []
keywords: []
"""

PENDING_TEMPLATE_SPECS = """_meta:
  source_file: {source_file}
  doc_type: {doc_type}
  status: pending
  updated_at: null

title: null
purpose: null
content_details: []
applicable_tasks: []
keywords: []
"""

# Directory name → doc_type mapping for fallback inference
DOC_TYPE_KEYWORDS = {
    'requirement': 'requirement', 'requirements': 'requirement',
    'design': 'design', 'designs': 'design',
    'plan': 'plan', 'plans': 'plan', 'planning': 'plan',
    'api': 'api', 'apis': 'api',
    'reference': 'reference', 'references': 'reference', 'ref': 'reference',
    'rule': 'rule', 'rules': 'rule',
    'spec': 'spec', 'specs': 'spec',
}


def parse_args():
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(
        description='Generate pending YAML templates for ToC generation'
    )
    parser.add_argument('--target', required=True, choices=['rules', 'specs'],
                        help='Target category: rules or specs')
    parser.add_argument('--full', action='store_true',
                        help='Process all files (default: changed files only)')
    return parser.parse_args()


def init_config(target):
    """
    Initialize configuration.

    Args:
        target: 'rules' or 'specs'

    Returns:
        bool: True on success, False on failure
    """
    global CONFIG, PROJECT_ROOT, ROOT_DIRS, TOC_WORK_DIR, CHECKSUMS_FILE
    global TOC_FILE, PATTERNS_CONFIG, TARGET_GLOB, EXCLUDE_PATTERNS, TARGET, DOC_TYPES_MAP

    TARGET = target

    try:
        CONFIG = load_config(target)
        PROJECT_ROOT = get_project_root()
    except RuntimeError as e:
        print(f"Error: {e}")
        return False
    except FileNotFoundError as e:
        print(f"Error: {e}")
        return False

    default_dir = f'{target}/'
    root_dirs_config = CONFIG.get('root_dirs', [default_dir])
    if isinstance(root_dirs_config, str):
        root_dirs_config = [root_dirs_config]
    # Expand glob patterns in root_dirs (e.g., "specs/*/requirements/")
    root_dirs_config = expand_root_dir_globs(root_dirs_config, PROJECT_ROOT)
    ROOT_DIRS = []
    for entry in root_dirs_config:
        name = entry.rstrip('/')
        ROOT_DIRS.append((PROJECT_ROOT / name, name))

    first_dir = ROOT_DIRS[0][0] if ROOT_DIRS else PROJECT_ROOT / target
    TOC_WORK_DIR = resolve_config_path(CONFIG.get('work_dir', '.toc_work'), first_dir, PROJECT_ROOT)
    CHECKSUMS_FILE = resolve_config_path(CONFIG.get('checksums_file', '.toc_checksums.yaml'), first_dir, PROJECT_ROOT)
    TOC_FILE = resolve_config_path(CONFIG.get('toc_file', f'{target}_toc.yaml'), first_dir, PROJECT_ROOT)
    PATTERNS_CONFIG = CONFIG.get('patterns', {})
    TARGET_GLOB = PATTERNS_CONFIG.get('target_glob', '**/*.md')
    # System patterns (always excluded) + user-defined patterns
    EXCLUDE_PATTERNS = get_system_exclude_patterns(target) + PATTERNS_CONFIG.get('exclude', [])
    DOC_TYPES_MAP = CONFIG.get('doc_types_map', {})
    return True


def determine_doc_type(root_dir_name):
    """Determine doc_type from root_dir path using config.yaml doc_types_map"""
    if DOC_TYPES_MAP:
        normalized = root_dir_name.rstrip('/')
        for path, doc_type in DOC_TYPES_MAP.items():
            if path.rstrip('/') == normalized:
                return doc_type
    # Fallback: infer from directory name
    dir_lower = root_dir_name.rstrip('/').split('/')[-1].lower()
    if dir_lower in DOC_TYPE_KEYWORDS:
        return DOC_TYPE_KEYWORDS[dir_lower]
    # Default by category
    return TARGET.rstrip('s') if TARGET else 'unknown'


def get_pending_template():
    """Get the pending YAML template for the current target"""
    if TARGET == 'specs':
        return PENDING_TEMPLATE_SPECS
    return PENDING_TEMPLATE_RULES


def has_substantive_content(filepath, min_content_lines=1):
    """
    Check if file has content beyond headers, blank lines, and frontmatter.

    Args:
        filepath: Path to the file
        min_content_lines: Minimum number of substantive lines required

    Returns:
        bool: True if file has enough substantive content
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except (IOError, OSError, PermissionError):
        return False

    if not content.strip():
        return False  # Empty file

    content_lines = 0
    in_frontmatter = False
    for line in content.splitlines():
        stripped = line.strip()

        # YAML frontmatter delimiter
        if stripped == '---':
            in_frontmatter = not in_frontmatter
            continue
        if in_frontmatter:
            continue

        # Skip empty lines and header-only lines
        if not stripped or stripped.startswith('#'):
            continue

        content_lines += 1
        if content_lines >= min_content_lines:
            return True

    return False


def get_all_md_files():
    """Get list of target .md files across all root_dirs (symlink-aware)"""
    md_files = []
    file_root_map = {}  # filepath -> (root_dir, root_dir_name)

    for root_dir, root_dir_name in ROOT_DIRS:
        if not root_dir.exists():
            print(f"Warning: {root_dir} does not exist, skipping")
            continue
        for filepath in rglob_follow_symlinks(root_dir, TARGET_GLOB):
            if should_exclude(filepath, root_dir, EXCLUDE_PATTERNS):
                continue
            md_files.append(filepath)
            file_root_map[filepath] = (root_dir, root_dir_name)

    md_files.sort()
    return md_files, file_root_map


def calculate_file_hash(filepath):
    """
    Calculate SHA256 hash of file

    Returns:
        str: Hash value, None on error
    """
    try:
        with open(filepath, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except (IOError, OSError, PermissionError) as e:
        print(f"Warning: File read error: {filepath} - {e}")
        return None


def load_checksums():
    """Load existing checksum file (standard library only)"""
    if not CHECKSUMS_FILE.exists():
        return {}

    checksums = {}
    try:
        with open(CHECKSUMS_FILE, "r", encoding="utf-8") as f:
            in_checksums = False
            for line in f:
                stripped = line.strip()
                if stripped == "checksums:":
                    in_checksums = True
                    continue
                if in_checksums and stripped and not stripped.startswith("#"):
                    match = re.match(r"^\s+(.+?):\s*([a-f0-9]+)\s*$", line)
                    if match:
                        filepath = match.group(1)
                        hash_val = match.group(2)
                        checksums[filepath] = hash_val
    except (IOError, OSError, PermissionError) as e:
        print(f"Warning: Failed to read checksums file: {e}")
        return {}

    return checksums


def get_source_file_path(md_file, root_dir, root_dir_name):
    """Get project-relative path with root_dir prefix"""
    rel_path = normalize_path(md_file.relative_to(root_dir))
    return f"{root_dir_name}/{rel_path}"


def get_yaml_filename(source_file):
    """Generate YAML filename from source_file using path hash.

    Uses SHA256 hash to avoid:
    - Filename length limits (macOS 255 bytes)
    - Case-insensitive filesystem collisions
    - Special characters in directory/file names
    The original path is preserved in _meta.source_file inside the YAML.
    """
    hash_val = hashlib.sha256(source_file.encode('utf-8')).hexdigest()[:16]
    return f"{hash_val}.yaml"


def create_pending_yaml(source_file, doc_type):
    """
    Create pending YAML file

    Args:
        source_file: Project-relative source file path
        doc_type: Document type (e.g., 'rule', 'requirement', 'design')

    Returns:
        Path: Created file path, None on error
    """
    yaml_name = get_yaml_filename(source_file)
    yaml_path = TOC_WORK_DIR / yaml_name
    template = get_pending_template()

    try:
        with open(yaml_path, "w", encoding="utf-8") as f:
            f.write(template.format(source_file=source_file, doc_type=doc_type))
        return yaml_path
    except (IOError, OSError, PermissionError) as e:
        print(f"Warning: File write error: {yaml_path} - {e}")
        return None


def save_pending_checksums(all_files, file_root_map):
    """Save checksums snapshot at Phase 1 time to .toc_work/

    Used to replace .toc_checksums.yaml after merge (Phase 3).
    This ensures that files modified during Phase 2 will be
    detected as changed in the next incremental run.
    """
    checksums = {}
    for md_file in all_files:
        root_dir, root_dir_name = file_root_map[md_file]
        source_file = get_source_file_path(md_file, root_dir, root_dir_name)
        hash_value = calculate_file_hash(md_file)
        if hash_value is not None:
            checksums[source_file] = hash_value

    pending_checksums_path = TOC_WORK_DIR / ".toc_checksums_pending.yaml"
    lines = [
        "# Phase 1 snapshot - used to replace .toc_checksums.yaml after merge",
        "# Auto-generated - do not edit",
        f"generated_at: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
        f"file_count: {len(checksums)}",
        "checksums:",
    ]
    for path, hash_val in sorted(checksums.items()):
        lines.append(f"  {path}: {hash_val}")

    try:
        with open(pending_checksums_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')
        print(f"Saved pending checksums: {len(checksums)} files")
    except (IOError, OSError, PermissionError) as e:
        print(f"Warning: Failed to save pending checksums: {e}")


def main():
    args = parse_args()

    # Initialize configuration
    if not init_config(args.target):
        return 1

    full_mode = args.full
    toc_name = f"{TARGET}_toc.yaml"

    # Force full mode if toc file doesn't exist
    if not TOC_FILE.exists():
        full_mode = True
        print(f"{toc_name} not found, running in full mode")

    # Force full mode if checksums doesn't exist
    if not full_mode and not CHECKSUMS_FILE.exists():
        full_mode = True
        print(".toc_checksums.yaml not found, running in full mode")

    # Get target files
    all_files, file_root_map = get_all_md_files()

    if full_mode:
        # Full mode: process all files
        target_files = all_files
        deleted_files = []
        print(f"Full mode: processing {len(target_files)} files")
    else:
        # Incremental mode: changed files only
        old_checksums = load_checksums()
        current_files = {}
        for f in all_files:
            root_dir, root_dir_name = file_root_map[f]
            current_files[get_source_file_path(f, root_dir, root_dir_name)] = f

        target_files = []

        # Detect new/changed files
        for source_file, full_path in current_files.items():
            current_hash = calculate_file_hash(full_path)
            if current_hash is None:
                continue  # Skip on hash calculation failure
            old_hash = old_checksums.get(source_file)

            if old_hash is None:
                print(f"  [New] {source_file}")
                target_files.append(full_path)
            elif current_hash != old_hash:
                print(f"  [Modified] {source_file}")
                target_files.append(full_path)

        # Detect deleted files
        deleted_files = [
            sf for sf in old_checksums.keys()
            if sf not in current_files
        ]
        for sf in deleted_files:
            print(f"  [Deleted] {sf}")

        if not target_files and not deleted_files:
            print(f"No changes - {toc_name} is up to date")
            return 0

        if not target_files and deleted_files:
            print(f"\nDeleted files only: {len(deleted_files)} files")
            print("Use --delete-only with merge script")
            return 0

        print(f"\nIncremental mode: {len(target_files)} changes, {len(deleted_files)} deletions")

    # Create .toc_work directory
    TOC_WORK_DIR.mkdir(parents=True, exist_ok=True)

    # Save Phase 1 checksums snapshot (for all target files, not just changed ones)
    save_pending_checksums(all_files, file_root_map)

    # Generate pending YAMLs
    created_files = []
    skipped_files = []
    failed_count = 0
    for md_file in target_files:
        root_dir, root_dir_name = file_root_map[md_file]
        source_file = get_source_file_path(md_file, root_dir, root_dir_name)

        # Skip empty/stub files (no substantive content)
        if not has_substantive_content(md_file):
            print(f"  [Skipped] {source_file} (empty or headers only)")
            skipped_files.append(source_file)
            continue

        doc_type = determine_doc_type(root_dir_name)
        yaml_path = create_pending_yaml(source_file, doc_type)
        if yaml_path is None:
            failed_count += 1
            continue
        created_files.append(source_file)

    if skipped_files:
        print(f"\nSkipped {len(skipped_files)} empty/stub files")

    if failed_count > 0:
        print(f"\nWarning: {failed_count} files failed to create")

    print(f"\nCreated {len(created_files)} pending YAMLs:")
    for sf in created_files:
        print(f"  - {sf}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
