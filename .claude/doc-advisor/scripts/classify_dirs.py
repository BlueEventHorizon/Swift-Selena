#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Synced from: bw-cc-plugins/plugins/doc-structure/scripts/classify_dirs.py
"""
ディレクトリスキャンスクリプト（.doc_structure.yaml 生成用）

プロジェクト内の Markdown ディレクトリを発見し、メタデータを JSON で出力する。
分類判定（category / doc_type）は行わない。AI が SKILL.md 内のルールに従って判定する。

Usage:
    python3 classify_dirs.py [project_root]
    python3 classify_dirs.py [project_root] --skip vendor,dist

Created by: k_terada
"""

import sys
import os
import json
import argparse
from pathlib import Path


# スキップするディレクトリ
SKIP_DIRS = {
    '.git', '.claude', '.github', '.vscode', '.idea',
    'node_modules', '__pycache__', '.tox', '.mypy_cache',
    'venv', '.venv', 'env', '.env',
    'dist', 'build', 'target', 'out',
    '.next', '.nuxt', '.svelte-kit',
    'vendor', 'Pods', '.gradle',
}

# これらのファイルが存在するディレクトリはソースコードディレクトリと判断しスキップ
SKIP_INDICATORS = {'package.json', 'Cargo.toml', 'go.mod', 'pom.xml', 'setup.py', 'pyproject.toml'}


def get_project_root(path=None):
    """Find project root by looking for .git directory."""
    start = Path(path) if path else Path.cwd()
    current = start.resolve()
    while current != current.parent:
        if (current / '.git').exists():
            return str(current)
        current = current.parent
    return str(start.resolve())


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description='プロジェクトの Markdown ディレクトリをスキャンし、メタデータを JSON で出力する'
    )
    parser.add_argument('project_root', nargs='?', default=None,
                        help='Project root directory (default: auto-detect from .git)')
    parser.add_argument('--skip', type=str, default='',
                        help='Comma-separated top-level directories to skip')
    return parser.parse_args()


def find_md_dirs(project_root):
    """
    Markdown ファイルを含むディレクトリを発見する（浅いスキャン）。

    .md ファイルが見つかったディレクトリの配下は探索しない。
    例: specs/ に .md があれば specs/login/requirements/ は探索されない。

    Returns:
        list of (relative_dir_path, md_file_count)
    """
    results = []
    root = Path(project_root)
    found_dirs = set()
    visited_real = set()  # 循環検出用（realpath で追跡）

    for dirpath, dirnames, filenames in os.walk(root, followlinks=True):
        current = Path(dirpath)
        real_path = current.resolve()

        # シンボリックリンクの循環検出
        if real_path in visited_real:
            dirnames[:] = []
            continue
        visited_real.add(real_path)

        rel = current.relative_to(root)
        rel_str = str(rel)

        # システムディレクトリ・隠しディレクトリを除外
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIRS
            and not d.startswith('.')
        ]

        # ルートディレクトリ自体はスキップ
        if rel_str == '.':
            continue

        # 祖先ディレクトリで既に .md が見つかっている場合はスキップ
        if any(rel_str.startswith(found + '/') or rel_str == found for found in found_dirs):
            dirnames[:] = []
            continue

        # ソースコードディレクトリはスキップ
        if any((current / ind).exists() for ind in SKIP_INDICATORS):
            continue

        # .md ファイルをカウント
        md_files = [f for f in filenames if f.endswith('.md')]
        if md_files:
            results.append((rel_str, len(md_files)))
            found_dirs.add(rel_str)
            dirnames[:] = []  # 配下の探索を停止

    return results


def is_readme_only(project_root, dir_path):
    """README/CHANGELOG 等のみを含むディレクトリか判定する。"""
    root = Path(project_root)
    dir_full = root / dir_path
    md_files = [f.name.lower() for f in dir_full.glob('*.md')]
    skip_names = {'readme.md', 'changelog.md', 'contributing.md', 'license.md',
                  'code_of_conduct.md', 'security.md'}
    return all(f in skip_names for f in md_files)


def extract_front_matter(filepath):
    """
    Markdown ファイルから YAML front matter を抽出する。

    Returns:
        dict or None
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read(4096)
    except (IOError, OSError):
        return None

    if not content.startswith('---'):
        return None

    end = content.find('---', 3)
    if end == -1:
        return None

    fm_content = content[3:end]
    result = {}
    for line in fm_content.split('\n'):
        line = line.strip()
        if ':' in line and not line.startswith('#'):
            key, _, val = line.partition(':')
            result[key.strip()] = val.strip().strip('"\'')

    return result


def scan_directories(project_root, skip_prefixes=None):
    """
    ディレクトリスキャン + メタデータ収集。
    分類判定は行わない。

    Returns:
        list[dict]: 各ディレクトリのメタデータ
    """
    md_dirs = find_md_dirs(project_root)

    if skip_prefixes:
        md_dirs = [(d, c) for d, c in md_dirs if not any(
            d == prefix or d.startswith(prefix + '/') for prefix in skip_prefixes
        )]

    results = []
    root = Path(project_root)

    for dir_path, md_count in md_dirs:
        dir_full = root / dir_path

        # frontmatter の doc_type 値を収集（生データ）
        doc_type_values = []
        for md_file in dir_full.glob('*.md'):
            fm = extract_front_matter(md_file)
            if fm and 'doc_type' in fm:
                doc_type_values.append(fm['doc_type'].lower())

        results.append({
            'dir': dir_path,
            'md_count': md_count,
            'readme_only': is_readme_only(project_root, dir_path),
            'path_components': list(Path(dir_path).parts),
            'frontmatter_doc_types': doc_type_values or None,
        })

    return results


def output_scan(project_root, directories):
    """スキャン結果を JSON で出力する。"""
    output = {
        'project_root': project_root,
        'directories': directories,
    }
    print(json.dumps(output, indent=2, ensure_ascii=False))


def main():
    args = parse_args()
    project_root = get_project_root(args.project_root)

    skip_prefixes = None
    if args.skip:
        skip_prefixes = [s.strip().rstrip('/') for s in args.skip.split(',') if s.strip()]

    directories = scan_directories(project_root, skip_prefixes)
    output_scan(project_root, directories)
    return 0


if __name__ == '__main__':
    sys.exit(main())
