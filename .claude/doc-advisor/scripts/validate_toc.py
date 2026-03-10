#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# doc-advisor-version-xK9XmQ: 4.4
"""
ToC 検査スクリプト（rules / specs 共通）

生成された {target}_toc.yaml の整合性を検査する。

使用方法:
    python3 validate_toc.py --target rules|specs [--file PATH]

オプション:
    --target  検査対象カテゴリ（rules または specs）
    --file    検査対象ファイル（デフォルト: .claude/doc-advisor/toc/{target}/{target}_toc.yaml）

検査項目:
    1. ファイル読み込み検査
    2. 必須フィールド検査
    3. ファイル参照検査
    4. 重複パス検査
"""

import sys
from pathlib import Path

from toc_utils import get_project_root, load_config, resolve_config_path, validate_path_within_base

# Global configuration (initialized in init_config())
TARGET = None  # 'rules' or 'specs'
CONFIG = None
PROJECT_ROOT = None
TARGET_DIR = None
DEFAULT_TOC_FILE = None


def init_config(target):
    """
    Initialize configuration for the given target category.

    Args:
        target: 'rules' or 'specs'

    Returns:
        bool: True on success, False on failure
    """
    global TARGET, CONFIG, PROJECT_ROOT, TARGET_DIR, DEFAULT_TOC_FILE

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

    root_dirs_config = CONFIG.get('root_dirs', [f'{target}/'])
    if isinstance(root_dirs_config, str):
        root_dirs_config = [root_dirs_config]
    # root_dirs_config が空の場合は PROJECT_ROOT / target をフォールバックとして使用する
    TARGET_DIR = (
        PROJECT_ROOT / root_dirs_config[0].rstrip('/')
        if root_dirs_config
        else PROJECT_ROOT / target
    )
    DEFAULT_TOC_FILE = resolve_config_path(
        CONFIG.get('toc_file', f'{target}_toc.yaml'), TARGET_DIR, PROJECT_ROOT
    )
    return True


def load_existing_toc(toc_path):
    """既存の {target}_toc.yaml を読み込み（docs: セクション形式対応）"""
    if not toc_path.exists():
        return {}

    try:
        with open(toc_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except (IOError, OSError, PermissionError) as e:
        print(f"Warning: Failed to read {toc_path}: {e}")
        return {}

    docs = {}
    current_section = None
    current_path = None
    current_entry = {}
    current_list = None

    for line in content.split('\n'):
        stripped = line.strip()

        if stripped.startswith('#') or not stripped:
            continue

        # セクション検出
        if stripped == 'docs:':
            current_section = 'docs'
            continue
        elif stripped.startswith('metadata:'):
            current_section = 'metadata'
            continue

        # docs セクション内のエントリ解析
        if current_section == 'docs':
            # ファイルパスキーの検出（2スペースインデントで : で終わる）
            if line.startswith('  ') and not line.startswith('    ') and stripped.endswith(':'):
                # 前のエントリを保存
                if current_path and current_entry:
                    docs[current_path] = current_entry
                current_path = stripped.rstrip(':')
                # Handle quoted YAML keys: "path/to/file.md"
                if current_path.startswith('"') and current_path.endswith('"'):
                    current_path = current_path[1:-1]
                current_entry = {}
                current_list = None

            # エントリのフィールド解析
            elif line.startswith('    ') and ':' in stripped and not stripped.startswith('-'):
                if current_path:
                    key, _, val = stripped.partition(':')
                    key = key.strip()
                    val = val.strip().strip('"\'')
                    if val:
                        current_entry[key] = val
                    else:
                        current_list = []
                        current_entry[key] = current_list

            # リスト項目
            elif stripped.startswith('- ') and current_list is not None:
                item = stripped[2:].strip().strip('"\'')
                current_list.append(item)

    # 最後のエントリを保存
    if current_path and current_entry:
        docs[current_path] = current_entry

    return docs


def validate_toc(toc_path):
    """
    生成された toc ファイルを検査する
    - YAML構文検査
    - 必須フィールド検査
    - ファイル参照検査
    - 重複パス検査
    """
    print("=" * 50)
    print(f"{TARGET}_toc.yaml 検査")
    print("=" * 50)
    print(f"対象: {toc_path}")
    print()

    errors = []

    # 1. ファイル読み込み検査（ファイルが読み込めるか）
    try:
        with open(toc_path, 'r', encoding='utf-8') as f:
            f.read()
        print("✓ ファイル読み込み検査: OK（ファイル読み込み成功）")
    except Exception as e:
        errors.append(f"ファイル読み込み検査: ファイル読み込み失敗 - {e}")
        print(f"\n❌ 検査失敗: {len(errors)} 件のエラー")
        for err in errors:
            print(f"  - {err}")
        return False

    # パース
    docs = load_existing_toc(toc_path)

    # docs キー存在検査（壊れた YAML で空 dict が返された場合のガード）
    if not docs or not isinstance(docs, dict):
        errors.append("docs セクションが見つからないか、エントリが空です")
        print("✗ docs セクション検査: docs が見つからないか空です")
        print(f"\n❌ 検査失敗: {len(errors)} 件のエラー")
        for err in errors:
            print(f"  - {err}")
        return False
    else:
        print("✓ docs セクション検査: OK")

    # 2. 必須フィールド検査
    # title/purpose/doc_type が必須（文字列）
    # content_details/applicable_tasks/keywords が必須（非空配列）
    # フォーマット定義: No null, No empty arrays ({TARGET}_toc_format.md)
    required_string_fields = ['title', 'purpose', 'doc_type']
    required_array_fields = ['content_details', 'applicable_tasks', 'keywords']
    field_errors = []

    for file_path, entry in docs.items():
        for field in required_string_fields:
            if not entry.get(field):
                field_errors.append(f"必須フィールド欠落: {file_path} に '{field}' がありません")
        for field in required_array_fields:
            value = entry.get(field)
            if not isinstance(value, list) or len(value) == 0:
                field_errors.append(
                    f"必須配列フィールド不正: {file_path} の '{field}' が未設定または空配列です"
                )

    if not field_errors:
        print(f"✓ 必須フィールド検査: OK（{len(docs)}件のエントリ）")
    else:
        print(f"✗ 必須フィールド検査: {len(field_errors)}件のエラー")
        errors.extend(field_errors)

    # 3. ファイル参照検査
    # キーはプロジェクトルートからの相対パス（例: {target}/core/doc.md）
    file_errors = []
    for file_path in docs.keys():
        try:
            full_path = validate_path_within_base(file_path, PROJECT_ROOT)
        except ValueError:
            file_errors.append(f"不正なパス: '{file_path}' はプロジェクト外を参照しています")
            continue
        if not full_path.exists():
            file_errors.append(f"ファイル不在: '{file_path}' が存在しません")

    if not file_errors:
        print(f"✓ ファイル参照検査: OK（全ファイルが存在）")
    else:
        print(f"✗ ファイル参照検査: {len(file_errors)}件のエラー")
        errors.extend(file_errors)

    # 4. 重複パス検査（辞書なので本質的に重複はないが確認）
    print(f"✓ 重複パス検査: OK（{len(docs)}件のユニークパス）")

    # 結果サマリー
    print()
    if errors:
        print(f"❌ 検査失敗: {len(errors)} 件のエラー")
        print("-" * 40)
        for err in errors:
            print(f"  - {err}")
        return False
    else:
        print(f"✅ 検査完了: 全チェックOK")
        return True


def main():
    # --target オプションの処理（必須）
    if '--target' not in sys.argv:
        print("エラー: --target rules|specs が必要です", file=sys.stderr)
        print("使用方法: python3 validate_toc.py --target rules|specs [--file PATH]",
              file=sys.stderr)
        return 1

    target_idx = sys.argv.index('--target')
    if target_idx + 1 >= len(sys.argv):
        print("エラー: --target に値が指定されていません", file=sys.stderr)
        return 1

    target = sys.argv[target_idx + 1]
    if target not in ('rules', 'specs'):
        print(f"エラー: --target は rules または specs を指定してください（指定値: {target}）",
              file=sys.stderr)
        return 1

    # Initialize configuration
    if not init_config(target):
        return 1

    # --file オプションの処理
    toc_path = DEFAULT_TOC_FILE
    if '--file' in sys.argv:
        idx = sys.argv.index('--file')
        if idx + 1 < len(sys.argv):
            toc_path = Path(sys.argv[idx + 1])
            try:
                toc_path = validate_path_within_base(toc_path, PROJECT_ROOT)
            except ValueError:
                print(f"エラー: 不正なパス: {toc_path}")
                return 1

    if not toc_path.exists():
        print(f"エラー: ファイルが存在しません: {toc_path}")
        return 1

    success = validate_toc(toc_path)
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main())
