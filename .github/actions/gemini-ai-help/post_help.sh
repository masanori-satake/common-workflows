#!/usr/bin/env bash
# Gemini AI エージェントのヘルプを Issue / PR にコメントする。
#   - /ai-help: ヘルプを表示（Issue なら Issue のコマンドを、PR なら PR のコマンドを先に表示）
#   - PR での有効な /ai-fix・/ai-bump patch|minor: 修正ワークフローが処理するため何もしない
#   - Issue での /ai-fix・/ai-bump: PR でのみ使えることを案内してヘルプを表示
#   - PR での /ai-bump（種別の指定なし・不正）: patch / minor の指定を案内してヘルプを表示
#   - そのほかの /ai-xxx（/ai-fixx 等）: 解釈できなかったことを伝えてヘルプを表示
#   コマンドの判定は修正ワークフローと共通の定義（gemini-ai-command/command_lib.sh）を使う。
#
# 入力（env）: GH_TOKEN, ISSUE_NUMBER, IS_PR（true / false）, COMMENT_BODY, GUIDE_URL
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER が未設定です}"
GUIDE_URL="${GUIDE_URL:-https://github.com/masanori-satake/common-workflows/blob/main/docs/ai-agent-setup.md}"

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../gemini-ai-command/command_lib.sh"
classify_ai_command "${COMMENT_BODY:-}"

if [ "${IS_PR:-false}" = "true" ] && { [ "$AI_CMD_KIND" = "fix" ] || [ "$AI_CMD_KIND" = "bump" ]; }; then
  echo "PR での ${AI_CMD_KIND} コマンドは修正ワークフローが処理するため、ヘルプは表示しません。"
  exit 0
fi
if [ "$AI_CMD_KIND" = "none" ]; then
  echo "/ai- コマンドではないため、ヘルプは表示しません。"
  exit 0
fi

# コメント本文をそのまま返さない（表示用に安全な文字だけ・30 文字まで）
command_safe="$(printf '%s' "$AI_CMD_NAME" | tr -cd 'A-Za-z0-9/_-' | cut -c1-30)"

note=""
if [ "$AI_CMD_KIND" = "help" ]; then
  note=""
elif [ "${IS_PR:-false}" != "true" ] && { [ "$AI_CMD_KIND" = "fix" ] || [ "$AI_CMD_KIND" = "bump" ] || [ "$AI_CMD_NAME" = "/ai-fix" ] || [ "$AI_CMD_NAME" = "/ai-bump" ]; }; then
  note="⚠️ \`${command_safe}\` は PR でのみ使えます。対象の PR にコメントしてください。"
elif [ "$AI_CMD_NAME" = "/ai-bump" ]; then
  note="⚠️ \`/ai-bump\` には更新種別として \`patch\` か \`minor\` を指定してください（例: \`/ai-bump patch\`）。"
else
  note="⚠️ \`${command_safe}\` は解釈できませんでした。使えるコマンドは次のとおりです。"
fi

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
- Gemini API 無料枠の上限（429）に達すると、自動で待機して再試行します。1 日の上限に達した場合は待たずに中止してお知らせするので、リセット（日本時間 16〜17 時ごろ）後にもう一度実行してください。
- AI の push では CI が自動で起動しないため、`/ai-fix`・`/ai-bump` の後は CI を自動で再実行します。Issue から作られた PR の CI は、PR を Close → Reopen すると起動します。
- 同じ Issue へのリクエストは、届いた順に 1 件ずつ処理します。
- 同じ PR へのリクエストは、準備（CI ログの収集）だけを届いた順に行い、前の処理の完了は待ちません。並行して動いた場合、後から終わった処理は PR ブランチが先に更新されているため push を中止することがあります。そのときは前の処理の結果を確認してから、もう一度コマンドを送ってください。
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
