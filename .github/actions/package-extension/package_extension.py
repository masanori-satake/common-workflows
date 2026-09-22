#!/usr/bin/env python3
"""拡張機能の素材ディレクトリを ZIP 化する共通スクリプト.

リリース ZIP のファイル名をエコシステム全体で統一する（{リポジトリ名}-v{version}.zip）ため、
ZIP 生成を common-workflows の base-release 側に集約する。各プロジェクトの build スクリプトは
ZIP を作らず、素材（projects/app）を用意するだけでよい。

環境変数:
  SOURCE_DIR       : ZIP に含める素材ディレクトリ（例: projects/app）
  ZIP_NAME         : 出力 ZIP のファイル名（例: OmniView-Solo-v1.1.6.zip）
  MANIFEST_RENAME  : ZIP 内リネーム "元:新"（例: manifest.chrome.json:manifest.json）。空なら無し

除外ルール（Solo 各プロジェクトの従来挙動の和集合）:
  - ディレクトリ: test-results / node_modules / _metadata / ドット始まり / アンダースコア始まり
    ただし _locales は残す
  - ファイル: ドット始まり / thumbs.db
"""

from __future__ import annotations

import os
import sys
import zipfile

EXCLUDE_DIRS = {"test-results", "node_modules", "_metadata"}
EXCLUDE_FILES = {"thumbs.db"}


def main() -> int:
    source_dir = os.environ.get("SOURCE_DIR", "")
    zip_name = os.environ.get("ZIP_NAME", "")
    manifest_rename = os.environ.get("MANIFEST_RENAME", "")

    if not source_dir or not zip_name:
        print("Error: SOURCE_DIR と ZIP_NAME は必須です。", file=sys.stderr)
        return 1

    if not os.path.isdir(source_dir):
        print(f"Error: 素材ディレクトリが見つかりません: {source_dir}", file=sys.stderr)
        return 1

    rename_from = rename_to = ""
    if manifest_rename:
        parts = manifest_rename.split(":", 1)
        rename_from = parts[0]
        rename_to = parts[1] if len(parts) > 1 else parts[0]

    with zipfile.ZipFile(zip_name, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(source_dir):
            # _locales は残しつつ、除外/隠し/アンダースコア始まりディレクトリを枝刈り
            dirs[:] = [
                d for d in dirs
                if d == "_locales"
                or (d not in EXCLUDE_DIRS and not d.startswith(".") and not d.startswith("_"))
            ]
            for f in files:
                if f.startswith(".") or f.lower() in EXCLUDE_FILES:
                    continue
                filepath = os.path.join(root, f)
                arcname = os.path.relpath(filepath, source_dir).replace(os.path.sep, "/")
                if rename_from and arcname == rename_from:
                    arcname = rename_to
                zf.write(filepath, arcname)

    print(f"Created package: {zip_name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
