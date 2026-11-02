#!/usr/bin/env bash
# /ai-fix で AI に修正させない場合の案内を PR にコメントする。
#   - version: バージョンチェックの失敗（更新種別の判断は人が行う）
#   - none   : 失敗した CI が無い（実行中を含む）
#
# 入力（env）: GH_TOKEN, PR_NUMBER, REASON, PENDING_COUNT, RUN_URL
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"

case "${REASON:-none}" in
  version)
    msg="🔢 バージョンチェックが失敗しています。バージョンの更新種別は人が判断するため、AI では修正していません。"
    msg+=$'\n\n'"AGENTS.md の基準で更新種別を決め、次のどちらかをコメントしてください。"
    msg+=$'\n\n'"| コメント | 更新内容 | 使う場面 |"
    msg+=$'\n'"| :--- | :--- | :--- |"
    msg+=$'\n'"| \`/ai-bump minor\` | X.Y.Z → X.(Y+1).0 | 新機能の追加、既存機能の拡張、仕様変更 |"
    msg+=$'\n'"| \`/ai-bump patch\` | X.Y.Z → X.Y.(Z+1) | 不具合修正、軽微な UI 調整、README などパッケージ同梱ドキュメントの更新 |"
    msg+=$'\n\n'"バージョン更新の後もほかのチェックが失敗する場合は、改めて \`/ai-fix\` をコメントしてください。"
    ;;
  *)
    if [ "${PENDING_COUNT:-0}" -gt 0 ]; then
      msg="⏳ この PR の CI は実行中です（${PENDING_COUNT} 件）。完了して失敗した場合に、改めて \`/ai-fix\` をコメントしてください。"
    else
      msg="ℹ️ この PR の最新コミットで失敗している CI はありません。"
      msg+=$'\n\n'"CI 以外の修正を依頼したい場合は、Issue に作業内容を書いて \`ai-task\` ラベルを付けてください。"
    fi
    ;;
esac
msg+=$'\n\n'"- 実行ログ: ${RUN_URL}"

gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$msg"
echo "ℹ️ 案内をコメントしました (Guidance posted): ${REASON:-none}" >> "$GITHUB_STEP_SUMMARY"
