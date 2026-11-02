#!/usr/bin/env bash
# 公開ジョブで、適用済みの作業結果（BASE_SHA..HEAD のコミット）を作業ブランチへ push し、
# PR を作成して Issue に通知する。リポジトリのコードは実行しない（commit / push はフックを無効化）。
#   - 作業結果の patch は apply_patch.sh で検証・適用済み（.github/workflows/ の変更は拒否済み）
#   - 最後の検証が失敗した場合は Draft PR として作成する
#
# 入力（env）: GH_TOKEN, BASE_BRANCH, BASE_SHA, ISSUE_NUMBER, MODEL_NAME, VERIFY_COMMAND,
#              TEST_STATUS, ATTEMPTS, TARGET_FILES, RUN_URL, GITHUB_RUN_ID,
#              STATUS_SCRIPT, STATUS_COMMENT_ID（状況表示用・任意）
# 出力（$GITHUB_OUTPUT）: pr_url
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${BASE_BRANCH:?BASE_BRANCH が未設定です}"
: "${BASE_SHA:?BASE_SHA が未設定です}"

ISSUE_REF="${ISSUE_NUMBER:+#${ISSUE_NUMBER}}"

comment_issue() {
  if [ -n "${ISSUE_NUMBER:-}" ]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$1"
  fi
}

# コミットの有無ではなく最終的な内容で判定する（後の回で前の回の変更を元に戻した場合も「変更なし」）
if git diff --quiet "$BASE_SHA" HEAD; then
  echo "AI による変更はありませんでした。(No changes detected by AI)"
  echo "ℹ️ 変更なし: AI による変更はありませんでした。" >> "$GITHUB_STEP_SUMMARY"
  echo "pr_url=" >> "$GITHUB_OUTPUT"
  comment_issue "ℹ️ Gemini AI エージェントを実行しましたが、変更はありませんでした。[実行ログ](${RUN_URL})"
  exit 0
fi

if [ -n "${STATUS_SCRIPT:-}" ] && [ -f "$STATUS_SCRIPT" ]; then
  bash "$STATUS_SCRIPT" update "📤 PR を作成中" "変更をブランチに push し、Pull Request を作成しています。" || true
fi

branch="chore/ai-issue-${ISSUE_NUMBER:-manual}-${GITHUB_RUN_ID}"
git checkout -q -b "$branch"

# checkout は persist-credentials: false のため、push 時のみ gh の認証ヘルパーを使う
gh auth setup-git
git -c core.hooksPath=/dev/null push -u origin "$branch"

verify_label="${VERIFY_COMMAND:-}"
case "${TEST_STATUS:-skipped}" in
  passed) test_line="✅ 成功 (\`${verify_label}\`)" ;;
  failed) test_line="❌ 失敗 (\`${verify_label}\`) — Draft PR として作成しました" ;;
  *) test_line="⏭️ 未実行（検証コマンドなし）" ;;
esac

body_file="${RUNNER_TEMP:-/tmp}/aider/pr_body.md"
mkdir -p "$(dirname "$body_file")"
{
  echo "## 概要 (Summary)"
  echo ""
  echo "Gemini AI エージェント（Aider + \`gemini/${MODEL_NAME}\`）が ${ISSUE_REF:-手動実行} の指示に基づいて自動生成した変更です。"
  echo "マージ前に必ず人間がレビューしてください。"
  echo ""
  echo "| 項目 (Item) | 値 (Value) |"
  echo "| :--- | :--- |"
  echo "| 対象 Issue | ${ISSUE_REF:-なし} |"
  echo "| 対象ファイル指定 (Files) | ${TARGET_FILES:-なし（AI が判断）} |"
  echo "| 検証 (Lint → テスト → ビルド) | ${test_line} |"
  echo "| AI による修正回数 (Rounds) | ${ATTEMPTS:-1} |"
  echo "| 実行ログ (Run) | [${GITHUB_RUN_ID}](${RUN_URL}) |"
  echo ""
  echo "> ℹ️ \`.github/workflows/\` への変更は GITHUB_TOKEN で push できないため、AI の作業結果から除外しています。"
  echo ""
  echo "> ℹ️ GITHUB_TOKEN で作成した PR では CI が自動起動しません。CI を実行するには PR を一度 Close → Reopen してください。"
  if [ -n "${ISSUE_NUMBER:-}" ]; then
    echo ""
    echo "Refs #${ISSUE_NUMBER}"
  fi
} > "$body_file"

pr_args=(
  --repo "$GITHUB_REPOSITORY"
  --base "$BASE_BRANCH"
  --head "$branch"
  --title "chore(ai): ${ISSUE_REF:-手動実行} の自動修正 (Gemini)"
  --body-file "$body_file"
)
if [ "${TEST_STATUS:-}" = "failed" ]; then
  pr_args+=(--draft)
fi

pr_url="$(gh pr create "${pr_args[@]}")"
echo "PR を作成しました: ${pr_url}"
echo "pr_url=${pr_url}" >> "$GITHUB_OUTPUT"
echo "✅ PR を作成しました (Pull Request created): ${pr_url}" >> "$GITHUB_STEP_SUMMARY"

# URL の直後に全角文字を続けると GitHub の自動リンクが URL の一部として取り込むため、
# URL は行末に置く。状況コメントの書き換えでは通知が飛ばないため、結果はこのコメントで通知する。
comment_issue "🤖 Gemini AI エージェントが PR を作成しました。"$'\n\n'"- PR: ${pr_url}"$'\n'"- 検証: ${test_line}"
