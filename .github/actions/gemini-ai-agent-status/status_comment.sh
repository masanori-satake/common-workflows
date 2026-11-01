#!/usr/bin/env bash
# Issue 上に Gemini AI エージェントの処理状況を表示する。
#   - 起動元（コメント起動ならそのコメント、ラベル起動なら Issue 本文）に 👀 リアクション
#   - 1 件の状況コメントを段階ごとに書き換え（経過を時刻付きで追記）
#   - 完了時に 👀 を外し、成功なら 🚀・失敗なら 😕 を付ける
#
# 使い方:
#   status_comment.sh ack                         受付（リアクション + 状況コメント作成）
#   status_comment.sh update <見出し> [詳細]      状況コメントの書き換え
#   status_comment.sh finish <pr|nochange|failure|cancelled> [PR URL]
#
# 入力（env）: GITHUB_REPOSITORY, ISSUE_NUMBER, EVENT_NAME, TRIGGER_COMMENT_ID,
#              STATUS_COMMENT_ID, REACTION_ID, RUN_URL,
#              STATUS_GH_TOKEN（未設定なら GH_TOKEN）
# 出力（ack 時の $GITHUB_OUTPUT）: comment_id, reaction_id
#
# 状況表示は補助機能のため、API エラー等が起きてもジョブは失敗させない（常に exit 0）。
set -uo pipefail

GH_TOKEN="${STATUS_GH_TOKEN:-${GH_TOKEN:-}}"
export GH_TOKEN
MODE="${1:-}"
REPO="${GITHUB_REPOSITORY:-}"
ISSUE="${ISSUE_NUMBER:-}"
MARKER='<!-- gemini-ai-agent-status -->'

if [ -z "$GH_TOKEN" ] || [ -z "$REPO" ] || [ -z "$ISSUE" ]; then
  echo "状況表示をスキップします（トークンまたは Issue 番号なし）。"
  exit 0
fi

now() { TZ=Asia/Tokyo date '+%H:%M:%S'; }

# 起動元へのリアクションの API パス
reaction_path() {
  if [ "${EVENT_NAME:-}" = "issue_comment" ] && [ -n "${TRIGGER_COMMENT_ID:-}" ]; then
    echo "repos/${REPO}/issues/comments/${TRIGGER_COMMENT_ID}/reactions"
  else
    echo "repos/${REPO}/issues/${ISSUE}/reactions"
  fi
}

# 状況コメント本文を組み立てる: render <見出し> <詳細> <経過（改行区切り）>
render() {
  local headline="$1" detail="$2" history="$3"
  printf '%s\n' "$MARKER"
  printf '### 🤖 Gemini AI エージェント\n\n'
  printf '**現在の状況:** %s\n' "$headline"
  if [ -n "$detail" ]; then
    printf '\n%s\n' "$detail"
  fi
  printf '\n**経過 (History, JST):**\n\n%s\n' "$history"
  printf '\n🔗 [実行ログ (Run log)](%s)\n' "${RUN_URL:-}"
}

# 既存の状況コメントから経過行（"- `HH:MM:SS` ..."）を取り出す
current_history() {
  # shellcheck disable=SC2016 # バッククォートは Markdown のリテラル（展開不要）
  gh api "repos/${REPO}/issues/comments/${STATUS_COMMENT_ID}" --jq '.body' 2> /dev/null \
    | grep -E '^- `[0-9]{2}:[0-9]{2}:[0-9]{2}`' || true
}

update_comment() {
  local headline="$1" detail="${2:-}"
  if [ -z "${STATUS_COMMENT_ID:-}" ]; then
    echo "状況コメント ID が無いため更新をスキップします: ${headline}"
    return 0
  fi
  local history
  history="$(current_history)"
  history="${history:+${history}$'\n'}- \`$(now)\` ${headline}"
  if gh api -X PATCH "repos/${REPO}/issues/comments/${STATUS_COMMENT_ID}" \
    -f body="$(render "$headline" "$detail" "$history")" > /dev/null; then
    echo "状況を更新しました: ${headline}"
  else
    echo "::warning::状況コメントの更新に失敗しました（処理は継続します）。"
  fi
}

case "$MODE" in
  ack)
    reaction_id="$(gh api -X POST "$(reaction_path)" -f content=eyes --jq '.id' 2> /dev/null || true)"
    headline="📥 受付しました"
    detail="まもなく開始します。同じ Issue で実行中の処理がある場合は、その完了後に順番に開始します。"
    comment_id="$(gh api -X POST "repos/${REPO}/issues/${ISSUE}/comments" \
      -f body="$(render "$headline" "$detail" "- \`$(now)\` ${headline}")" --jq '.id' 2> /dev/null || true)"
    [ -z "$comment_id" ] && echo "::warning::状況コメントの作成に失敗しました（処理は継続します）。"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      {
        echo "comment_id=${comment_id}"
        echo "reaction_id=${reaction_id}"
      } >> "$GITHUB_OUTPUT"
    fi
    echo "受付通知: comment_id=${comment_id:-none} reaction_id=${reaction_id:-none}"
    ;;

  update)
    update_comment "${2:-⚙️ 処理中}" "${3:-}"
    ;;

  finish)
    result="${2:-failure}"
    pr_url="${3:-}"
    case "$result" in
      pr)
        update_comment "✅ 完了: PR を作成しました" "${pr_url}"
        reaction="rocket"
        ;;
      nochange)
        update_comment "ℹ️ 完了: 変更はありませんでした" "指示が曖昧な場合や対象ファイルが除外された場合に起こります。実行ログの Summary を確認してください。"
        reaction="rocket"
        ;;
      cancelled)
        update_comment "⏹️ 中断されました" "タイムアウトまたは手動キャンセルにより停止しました。"
        reaction="confused"
        ;;
      *)
        update_comment "❌ 失敗しました" "実行ログでエラー内容を確認してください。"
        reaction="confused"
        ;;
    esac
    if [ -n "${REACTION_ID:-}" ]; then
      gh api -X DELETE "$(reaction_path)/${REACTION_ID}" > /dev/null 2>&1 || true
    fi
    gh api -X POST "$(reaction_path)" -f content="$reaction" > /dev/null 2>&1 || true
    ;;

  *)
    echo "::warning::不明なモードです: ${MODE}"
    ;;
esac

exit 0
