#!/usr/bin/env python3
"""拡張機能パッケージング(ZIP)のテンプレート (Extension Packaging Template).

`projects/app` 配下を Chrome 拡張機能用の ZIP としてまとめ、`releases/` に出力する。
base-release.yml は `releases/*.zip` を Release アセットとして添付するため、
本スクリプトを `npm run build` から呼び出す構成を推奨する。

このスクリプトは **テンプレート** であり、各プロジェクトの都合に合わせて
下記の設定定数を編集して使う。

拡張ポイント:
  - SOURCE_DIR   : ZIP 化する対象ディレクトリ
  - VERSION_FILE : バージョン取得元の JSON（"version" フィールド）
  - ZIP_PREFIX   : 出力 ZIP 名の接頭辞（既定はリポジトリ名を推奨）
  - EXCLUDE_*    : 除外するディレクトリ/ファイルのルール
  - RENAME_MAP   : ZIP 内でリネームするファイル（例: manifest.chrome.json → manifest.json）
"""

from __future__ import annotations

import json
import os
import sys
import zipfile

# ---------------------------------------------------------------------------
# ★ プロジェクトごとに編集する箇所 ★
# ---------------------------------------------------------------------------
SOURCE_DIR = "projects/app"
VERSION_FILE = "projects/app/manifest.json"
ZIP_PREFIX = os.path.basename(os.getcwd())  # 既定: リポジトリ（作業）ディレクトリ名
OUTPUT_DIR = "releases"

# 除外するディレクトリ名（完全一致）。ただし _locales は残す。
EXCLUDE_DIRS = {"test-results", "node_modules"}
# 除外するファイル名（小文字比較）
EXCLUDE_FILES = {"thumbs.db"}
# ZIP 内でのリネーム（arcname → 変更後）
RENAME_MAP = {"manifest.chrome.json": "manifest.json"}


def _is_hidden(name: str) -> bool:
    return name.startswith(".")


def get_version() -> str:
    with open(VERSION_FILE, "r", encoding="utf-8") as f:
        version = json.load(f).get("version")
    if not version:
        print(f"Error: {VERSION_FILE} に version がありません。", file=sys.stderr)
        sys.exit(1)

    # タグ push 時の想定バージョンと一致するか検証（任意）
    expected = os.environ.get("EXPECTED_VERSION", "")
    ref = os.environ.get("GITHUB_REF", "")
    if not expected and ref.startswith("refs/tags/v"):
        expected = ref[len("refs/tags/v"):]
    if expected.startswith("v"):
        expected = expected[1:]
    if expected and expected != version:
        print(f"Error: タグのバージョン '{expected}' と {VERSION_FILE} の '{version}' が一致しません。", file=sys.stderr)
        sys.exit(1)

    return version


def create_package() -> None:
    if not os.path.isdir(SOURCE_DIR):
        print(f"Error: 対象ディレクトリが見つかりません: {SOURCE_DIR}", file=sys.stderr)
        sys.exit(1)

    version = get_version()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    zip_name = f"{ZIP_PREFIX}-v{version}.zip"
    zip_path = os.path.join(OUTPUT_DIR, zip_name)

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(SOURCE_DIR):
            # 除外ディレクトリと隠しディレクトリを枝刈り（_locales は残す）
            dirs[:] = [
                d for d in dirs
                if d == "_locales" or (d not in EXCLUDE_DIRS and not _is_hidden(d) and not d.startswith("_"))
            ]
            for file in files:
                if _is_hidden(file) or file.lower() in EXCLUDE_FILES:
                    continue
                filepath = os.path.join(root, file)
                arcname = os.path.relpath(filepath, SOURCE_DIR).replace(os.path.sep, "/")
                arcname = RENAME_MAP.get(arcname, arcname)
                zipf.write(filepath, arcname)

    print(f"Created package: {zip_path}")


if __name__ == "__main__":
    create_package()
