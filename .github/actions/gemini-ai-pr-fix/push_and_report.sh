#!/usr/bin/env bash
# 修正を PR ブランチへ push し、失敗していた CI を再実行して PR にコメントで報告する。
#   - 公開ジョブで実行する。コミットは作業ジョブが作成し、apply_patch.sh が新しい checkout に適用済み
#     （このスクリプトはリポジトリのコードを実行しない）
#   - push 前に PR が Open のままで、head（SHA・ブランチ・リポジトリ）が処理開始時から変わっていないことを
#     API で確認し、push 先と CI 再実行の --ref には API から取得した head ブランチを使う
#   - push は git フックを無効化して行う
#   - GITHUB_TOKEN の push では CI が起動しないため、workflow_dispatch で再実行する
#
# 入力（env）: GH_TOKEN, MODE, PR_NUMBER, HEAD_REF, HEAD_SHA, RERUN_WORKFLOWS,
#              MODEL_NAME, TEST_STATUS, ATTEMPTS, VERIFY_COMMAND, NEW_VERSION, BUMP_TYPE,
#              RUN_URL, STATUS_SCRIPT, STATUS_COMMENT_ID
# 出力（$GITHUB_OUTPUT）: result（pushed / nochange）, commit_url
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${HEAD_REF:?HEAD_REF が未設定です}"
: "${HEAD_SHA:?HEAD_SHA が未設定です}"

status() {
  if [ -n "${STATUS_SCRIPT:-}" ] && [ -f "$STATUS_SCRIPT" ]; then
    bash "$STATUS_SCRIPT" update "$@" || true
  fi
}
comment_pr() {
  gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$1"
}


if [ "$(git rev-parse HEAD)" = "$HEAD_SHA" ]; then
  echo "変更はありませんでした。(No changes)"
  echo "result=nochange" >> "$GITHUB_OUTPUT"
  echo "commit_url=" >> "$GITHUB_OUTPUT"
  msg="ℹ️ Gemini AI エージェントを実行しましたが、変更はありませんでした。"
  msg+=$'\n\n'"コードの問題ではない失敗（ネットワーク・GitHub 側の障害など）の可能性があります。CI を再実行するか、\`/ai-fix <追加の指示>\` で原因のヒントを伝えてください。"
  msg+=$'\n\n'"- 実行ログ: ${RUN_URL}"
  comment_pr "$msg"
  exit 0
fi

# push 前の確認: 処理中に PR が閉じられた・更新された場合は push しない
pr_json="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}")"
if [ "$(jq -r '.state' <<< "$pr_json")" != "open" ]; then
  echo "::error::処理中に PR が閉じられたため、push を中止しました。"
  exit 1
fi
if [ "$(jq -r '.head.sha' <<< "$pr_json")" != "$HEAD_SHA" ]; then
  echo "::error::処理中に PR ブランチが更新されたため、push を中止しました。もう一度コマンドを実行してください。"
  exit 1
fi
# push 先は API から取得した現在の head だけを使う（作業ジョブの出力 HEAD_REF は照合にのみ使う）
api_head_ref="$(jq -r '.head.ref // ""' <<< "$pr_json")"
api_head_repo="$(jq -r '.head.repo.full_name // ""' <<< "$pr_json")"
if [ "$api_head_repo" != "$GITHUB_REPOSITORY" ]; then
  echo "::error::PR の head リポジトリ（${api_head_repo:-不明}）がこのリポジトリと一致しないため、push を中止しました。"
  exit 1
fi
if [ -z "$api_head_ref" ] || [ "$api_head_ref" != "$HEAD_REF" ]; then
  echo "::error::PR の head ブランチ（${api_head_ref:-不明}）が作業時の値（${HEAD_REF}）と一致しないため、push を中止しました。"
  exit 1
fi
if ! git check-ref-format --branch "$api_head_ref" > /dev/null 2>&1; then
  echo "::error::PR の head ブランチ名が不正なため、push を中止しました。"
  exit 1
fi
HEAD_REF="$api_head_ref"

status "📤 PR ブランチに push 中" "\`${HEAD_REF}\` に修正コミットを push しています。"
gh auth setup-git
git -c core.hooksPath=/dev/null push origin "HEAD:refs/heads/${HEAD_REF}"
new_sha="$(git rev-parse HEAD)"
commit_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/commit/${new_sha}"

# 失敗していた CI を再実行（workflow_dispatch が定義されていないワークフローは手動対応）
rerun_lines=""
rerun_failed=""
for wf in ${RERUN_WORKFLOWS:-}; do
  if gh workflow run "$wf" --repo "$GITHUB_REPOSITORY" --ref "$HEAD_REF" > /dev/null 2>&1; then
    rerun_lines+="- \`${wf}\`: 再実行しました"$'\n'
  else
    rerun_lines+="- \`${wf}\`: 再実行できませんでした（workflow_dispatch 未定義の可能性）"$'\n'
    rerun_failed=true
  fi
done

if [ "${MODE:-fix}" = "bump" ]; then
  headline="🔢 バージョンを ${NEW_VERSION:-?} に更新しました（${BUMP_TYPE:-?}）。"
  details="- 更新ファイル: package.json / package-lock.json / README.md / CHANGELOG.md など"$'\n'
  details+="- CHANGELOG.md の説明は PR タイトルから作成しています。必要に応じて書き直してください。"$'\n'
else
  case "${TEST_STATUS:-skipped}" in
    passed) test_line="✅ 成功" ;;
    failed) test_line="❌ 失敗（上限回数まで修正しても検証が通りませんでした。差分を確認し、必要なら \`/ai-fix <追加の指示>\` で再依頼してください）" ;;
    *) test_line="⏭️ 未実行" ;;
  esac
  headline="🛠️ CI の失敗を修正するコミットを push しました。"
  details="- 検証コマンド: \`${VERIFY_COMMAND:-なし}\`"$'\n'
  details+="- 検証結果: ${test_line}"$'\n'
  details+="- 修正回数（AI と検証の往復）: ${ATTEMPTS:-1}"$'\n'
fi

msg="${headline}"$'\n\n'"${details}- コミット: ${commit_url}"$'\n'"- 実行ログ: ${RUN_URL}"
if [ -n "$rerun_lines" ]; then
  msg+=$'\n\n'"**CI の再実行**"$'\n\n'"${rerun_lines}"
fi
if [ -n "$rerun_failed" ] || [ -z "$rerun_lines" ]; then
  msg+=$'\n'"> ℹ️ GITHUB_TOKEN による push では CI が自動起動しません。必要に応じて PR を Close → Reopen して CI を実行してください。"
fi
msg+=$'\n\n'"マージ前に必ず差分をレビューしてください。"
comment_pr "$msg"

{
  echo "result=pushed"
  echo "commit_url=${commit_url}"
} >> "$GITHUB_OUTPUT"
echo "✅ PR ブランチに push しました (Pushed): ${commit_url}" >> "$GITHUB_STEP_SUMMARY"
