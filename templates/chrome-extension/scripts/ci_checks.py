#!/usr/bin/env python3
"""共通CIポリシーチェックの単一エントリのテンプレート (CI Policy Checks Template).

common-workflows の base-ci.yml は、このファイル（scripts/ci_checks.py）が
存在すれば自動的に実行する。プロジェクト固有の Python チェックをここに集約し、
呼び出し側ワークフローの `with:` を空に保つのが狙い。

拡張方法:
  `CHECKS` に (ラベル, コマンド配列) を追加するだけ。例:
    ("ルート整合性", ["python3", "scripts/check_root_files.py"]),
    ("ポリシー確認", ["python3", "scripts/verify_project_policies.py"]),
"""

import subprocess
import sys

# ---------------------------------------------------------------------------
# ★ プロジェクトごとに編集する箇所 ★
# ---------------------------------------------------------------------------
CHECKS = [
    ("バージョン整合性 (Version Consistency)", ["python3", "scripts/check_version.py"]),
]


def main() -> int:
    failed = []
    for label, command in CHECKS:
        print(f"::group::{label}")
        result = subprocess.run(command)
        print("::endgroup::")
        if result.returncode != 0:
            failed.append(label)

    if failed:
        print("::error::以下のチェックに失敗しました: " + ", ".join(failed))
        return 1

    print("すべてのCIポリシーチェックに合格しました。 (All CI policy checks passed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
