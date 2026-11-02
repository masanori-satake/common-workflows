#!/usr/bin/env bash
# 作業ジョブの出力を検証し、作業結果の patch を新しい checkout に適用する（公開ジョブ用）。
#   - 作業ジョブは PR のコードを実行するため、その出力と patch は信頼しない
#   - チェックアウトしたコミットが作業の起点（HEAD_SHA）と一致することを確認する
#   - patch は git フックを無効化して git am で適用する（PR のコードは実行しない）
#   - .github/workflows/ を変更する patch は拒否する（GITHUB_TOKEN では push できない）
#
# 入力（env）: PATCH_FILE, HEAD_SHA, MODE, ATTEMPTS, TEST_STATUS, NEW_VERSION, RERUN_WORKFLOWS, VERIFY_COMMAND
# 出力（$GITHUB_OUTPUT）: commits, attempts, test_status, new_version, rerun_workflows, verify_command（検証済みの値）
set -euo pipefail

: "${HEAD_SHA:?HEAD_SHA が未設定です}"

# ---- 作業ジョブの出力を検証（不正な値は既定値に置き換える） ----
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::HEAD_SHA が不正です。"; exit 1; }
attempts="${ATTEMPTS:-}"
[[ "$attempts" =~ ^[0-9]{1,2}$ ]] || attempts=""
case "${TEST_STATUS:-}" in passed | failed | skipped) test_status="$TEST_STATUS" ;; *) test_status="" ;; esac
new_version="${NEW_VERSION:-}"
[[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || new_version=""
rerun=()
for wf in ${RERUN_WORKFLOWS:-}; do
  [[ "$wf" =~ ^[A-Za-z0-9._-]+\.ya?ml$ ]] && rerun+=("$wf")
done
# 検証コマンドはコメント内のコード表記に入れるため、バッククォートと改行を除く
verify="${VERIFY_COMMAND:-}"
verify="${verify//\`/}"
verify="${verify//$'\n'/ }"

if [ "$(git rev-parse HEAD)" != "$HEAD_SHA" ]; then
  echo "::error::作業中に PR ブランチが更新されたため、push を中止しました。もう一度コマンドを実行してください。"
  exit 1
fi

# ---- patch の適用 ----
commits=0
if [ -n "${PATCH_FILE:-}" ] && [ -s "$PATCH_FILE" ]; then
  if ! git -c core.hooksPath=/dev/null am --keep-cr --no-3way "$PATCH_FILE"; then
    git am --abort || true
    echo "::error::作業結果の patch を適用できませんでした。"
    exit 1
  fi
  if git diff --name-only "$HEAD_SHA" HEAD | grep -q '^\.github/workflows/'; then
    echo "::error::作業結果に .github/workflows/ の変更が含まれているため、push を中止しました。"
    git diff --name-only "$HEAD_SHA" HEAD | grep '^\.github/workflows/' || true
    exit 1
  fi
  commits="$(git rev-list --count "${HEAD_SHA}..HEAD")"
fi
echo "適用したコミット数: ${commits}"
git --no-pager log --oneline "${HEAD_SHA}..HEAD" || true
git --no-pager diff --stat "$HEAD_SHA" HEAD || true

{
  echo "commits=${commits}"
  echo "attempts=${attempts}"
  echo "test_status=${test_status}"
  echo "new_version=${new_version}"
  echo "rerun_workflows=${rerun[*]+"${rerun[*]}"}"
  echo "verify_command=${verify}"
} >> "$GITHUB_OUTPUT"
{
  echo "### 📦 作業結果の適用 (Apply Work Result)"
  echo ""
  echo "- モード (Mode): \`${MODE:-}\`"
  echo "- 適用したコミット数 (Commits): ${commits}"
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
