#!/usr/bin/env bash
# Gemini AI エージェントのヘルプを Issue / PR にコメントする。
#   - /ai-help: ヘルプを表示（Issue なら Issue のコマンドを、PR なら PR のコマンドを先に表示）
#   - Issue での /ai-fix・/ai-bump: PR でのみ使えることを案内してヘルプを表示
#   - そのほかの /ai-xxx: 解釈できなかったことを伝えてヘルプを表示
#
# 入力（env）: GH_TOKEN, ISSUE_NUMBER, IS_PR（true / false）, COMMENT_BODY, GUIDE_URL
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER が未設定です}"
GUIDE_URL="${GUIDE_URL:-https://github.com/masanori-satake/common-workflows/blob/main/docs/ai-agent-setup.md}"

body="${COMMENT_BODY//$'\r'/}"
first_line="${body%%$'\n'*}"
command="${first_line%%[[:space:]]*}"
# コメント本文をそのまま返さない（表示用に安全な文字だけ・30 文字まで）
command_safe="$(printf '%s' "$command" | tr -cd 'A-Za-z0-9/_-' | cut -c1-30)"

note=""
case "$command" in
  /ai-help) ;;
  /ai-fix | /ai-bump)
    if [ "${IS_PR:-false}" != "true" ]; then
      note="⚠️ \`${command_safe}\` は PR でのみ使えます。対象の PR にコメントしてください。"
    fi
    ;;
  *)
    note="⚠️ \`${command_safe}\` は解釈できませんでした。使えるコマンドは次のとおりです。"
    ;;
esac

issue_section=$(cat << 'EOF'
#### Issue で使うコマンド

| 操作 | 内容 |
| :--- | :--- |
| `ai-task` ラベルを付ける | Issue のタイトルと本文を指示として、AI が修正して PR を作成します |
| `/ai <指示>` とコメント | コメントの指示で AI が修正して PR を作成します（Issue 本文も背景として渡します）。追加の指示ややり直しに使います |
| 本文やコメントに `Files: src/a.ts, src/b.ts` と書く | AI に渡すファイルを限定します（無料枠のトークン節約のため推奨） |
EOF
)

pr_section=$(cat << 'EOF'
#### PR で使うコマンド

| コメント | 内容 |
| :--- | :--- |
| `/ai-fix [追加の指示]` | 失敗した CI のログを AI が解析して修正し、PR ブランチに push します。修正後は Lint → テスト → ビルドで検証し、失敗したら最大 3 回まで再修正します |
| `/ai-bump minor` | バージョンを X.Y.Z → X.(Y+1).0 に更新します（新機能の追加、既存機能の拡張、仕様変更） |
| `/ai-bump patch` | バージョンを X.Y.Z → X.Y.(Z+1) に更新します（不具合修正、軽微な UI 調整、README などの更新） |
EOF
)

common_section=$(cat << 'EOF'
#### 共通

| コメント | 内容 |
| :--- | :--- |
| `/ai-help` | このヘルプを表示します |

#### 状況表示の見方

- コマンドを受け付けると 👀 が付き、完了すると 🚀（成功）または 😕（失敗・中断）に変わります。
- 「🤖 Gemini AI エージェント」の状況コメントが段階ごとに書き換わります。結果は通知が届くよう別のコメントでも知らせます。
- PR では安全のため、作業中は「⚙️ 作業ジョブで処理中」のまま数分〜数十分更新されません。進み具合は状況コメントの実行ログから確認できます。

#### 知っておくこと

- コマンドを使えるのは、リポジトリの Owner / Member / Collaborator だけです。フォークからの PR は対象外です。
- AI の変更は誤りを含むことがあります。必ず差分をレビューしてからマージしてください。
- バージョンチェックの失敗は AI では直しません。AGENTS.md の基準で更新種別を判断し、`/ai-bump minor` か `/ai-bump patch` をコメントしてください。
- `.github/workflows/` のファイルは AI では変更できません（GitHub の制約）。
- Gemini API 無料枠の上限（429）に達すると、自動で待機して再試行します。1 日の上限に達した場合は、リセット（日本時間 16〜17 時ごろ）後にもう一度実行してください。
- AI の push では CI が自動で起動しないため、`/ai-fix`・`/ai-bump` の後は CI を自動で再実行します。Issue から作られた PR の CI は、PR を Close → Reopen すると起動します。
- 同じ Issue / PR へのリクエストは、届いた順に処理します。
EOF
)

msg="### 🤖 Gemini AI エージェントのヘルプ"
if [ -n "$note" ]; then
  msg+=$'\n\n'"${note}"
fi
if [ "${IS_PR:-false}" = "true" ]; then
  msg+=$'\n\n'"${pr_section}"$'\n\n'"${issue_section}"
else
  msg+=$'\n\n'"${issue_section}"$'\n\n'"${pr_section}"
fi
msg+=$'\n\n'"${common_section}"
msg+=$'\n\n'"詳しくは導入ガイドを参照してください。"$'\n\n'"- 導入ガイド: ${GUIDE_URL}"

gh issue comment "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$msg"
{
  echo "### ❓ ヘルプを表示しました (Help Posted)"
  echo ""
  echo "- コマンド (Command): \`${command_safe}\`"
  echo "- 対象 (Target): $([ "${IS_PR:-false}" = true ] && echo PR || echo Issue) #${ISSUE_NUMBER}"
} >> "$GITHUB_STEP_SUMMARY"
