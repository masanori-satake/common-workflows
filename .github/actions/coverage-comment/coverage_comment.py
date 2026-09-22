#!/usr/bin/env python3
"""カバレッジサマリを PR に sticky コメントとして投稿する共通スクリプト.

jest / vitest いずれも `json-summary` レポーターで出力する
`coverage/coverage-summary.json` を入力とし、ランナー非依存で集計する。
第三者 Action には依存せず、GitHub CLI (gh) で PR コメントを作成/更新する。

環境変数:
  COVERAGE_FILE   : coverage-summary.json のパス（既定: coverage/coverage-summary.json）
  MIN_COVERAGE    : 行カバレッジの下限(%)。0 なら閾値チェックをしない（既定: 0）
  PR_NUMBER       : コメント対象の PR 番号（無ければコメント投稿をスキップ）
  GITHUB_REPOSITORY: owner/repo（gh 用）
  GH_TOKEN / GITHUB_TOKEN: gh 認証用トークン

sticky コメントは本文中のマーカー <!-- coverage-report --> で既存コメントを識別し、
あれば更新、なければ新規作成する。
"""

from __future__ import annotations

import json
import os
import subprocess
import sys

MARKER = "<!-- coverage-report -->"


def _pct(node: dict, key: str) -> float:
    try:
        return float(node.get(key, {}).get("pct", 0) or 0)
    except (AttributeError, TypeError, ValueError):
        return 0.0


def build_markdown(total: dict, min_coverage: float) -> tuple[str, bool]:
    lines_pct = _pct(total, "lines")
    statements_pct = _pct(total, "statements")
    functions_pct = _pct(total, "functions")
    branches_pct = _pct(total, "branches")

    passed = (min_coverage <= 0) or (lines_pct >= min_coverage)
    status_icon = "✅" if passed else "❌"

    body = [
        MARKER,
        "### 🧪 カバレッジレポート (Coverage Report)",
        "",
        "| 指標 (Metric) | カバレッジ (Coverage) |",
        "| :--- | ---: |",
        f"| 行 (Lines) | {lines_pct:.2f}% |",
        f"| 文 (Statements) | {statements_pct:.2f}% |",
        f"| 関数 (Functions) | {functions_pct:.2f}% |",
        f"| 分岐 (Branches) | {branches_pct:.2f}% |",
    ]
    if min_coverage > 0:
        body.append("")
        body.append(f"{status_icon} 行カバレッジ下限: {min_coverage:.2f}%（現在 {lines_pct:.2f}%）")
    body.append("")
    return "\n".join(body), passed


def post_sticky_comment(pr_number: str, body: str) -> None:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if not pr_number or not repo:
        print("PR 番号またはリポジトリ情報が無いため、コメント投稿をスキップします。")
        return

    # 既存の sticky コメントを探す
    comment_id = ""
    try:
        result = subprocess.run(
            ["gh", "api", f"repos/{repo}/issues/{pr_number}/comments", "--paginate"],
            capture_output=True, text=True, check=True,
        )
        comments = json.loads(result.stdout)
        for c in comments:
            if MARKER in (c.get("body") or ""):
                comment_id = str(c.get("id"))
                break
    except subprocess.CalledProcessError as e:
        print(f"既存コメントの取得に失敗しました（新規投稿にフォールバック）: {e.stderr}", file=sys.stderr)

    # body をファイル経由で渡す（改行・多言語対応）
    tmp = "_coverage_comment_body.md"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(body)

    try:
        if comment_id:
            subprocess.run(
                ["gh", "api", "-X", "PATCH", f"repos/{repo}/issues/comments/{comment_id}",
                 "-F", f"body=@{tmp}"],
                check=True,
            )
            print(f"既存のカバレッジコメント (id={comment_id}) を更新しました。")
        else:
            subprocess.run(
                ["gh", "api", "-X", "POST", f"repos/{repo}/issues/{pr_number}/comments",
                 "-F", f"body=@{tmp}"],
                check=True,
            )
            print("カバレッジコメントを新規投稿しました。")
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def write_summary(body: str) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write(body + "\n")


def main() -> int:
    coverage_file = os.environ.get("COVERAGE_FILE", "coverage/coverage-summary.json")
    try:
        min_coverage = float(os.environ.get("MIN_COVERAGE", "0") or "0")
    except ValueError:
        min_coverage = 0.0

    if not os.path.exists(coverage_file):
        print(f"{coverage_file} が見つかりません。カバレッジコメントをスキップします。")
        return 0

    with open(coverage_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    total = data.get("total", {})
    body, passed = build_markdown(total, min_coverage)

    write_summary(body)
    post_sticky_comment(os.environ.get("PR_NUMBER", ""), body)

    if not passed:
        print(f"::error::行カバレッジが下限 {min_coverage:.2f}% を下回っています。", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
