#!/usr/bin/env bash
# PR コメントのコマンドを解析し、対象 PR が処理可能かを検証する。
#   /ai-fix [追加の指示]      CI の失敗を AI が解析・修正する
#   /ai-bump patch|minor      バージョンを更新する（AI は使わない）
#
# 検証内容: PR が Open であること、同一リポジトリのブランチであること（フォーク不可）、
#           チェックアウト済みのコミットが PR の最新 head であること。
#
# 入力（env）: GH_TOKEN, PR_NUMBER, COMMENT_BODY
# 出力（$GITHUB_OUTPUT）: mode, bump_type, head_ref, head_sha, base_ref
# 出力（$GITHUB_ENV）  : FIX_INSTRUCTION, PR_TITLE（複数行可・ランダムデリミタ）
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${PR_NUMBER:?PR_NUMBER が未設定です}"

body="${COMMENT_BODY//$'\r'/}"
first_line="${body%%$'\n'*}"
rest=""
[[ "$body" == *$'\n'* ]] && rest="${body#*$'\n'}"

mode=""
bump_type=""
instruction=""
if [[ "$first_line" =~ ^/ai-fix([[:space:]]+(.*))?$ ]]; then
  mode="fix"
  instruction="${BASH_REMATCH[2]:-}"
  [ -n "$rest" ] && instruction="${instruction:+${instruction}$'\n'}${rest}"
elif [[ "$first_line" =~ ^/ai-bump[[:space:]]+(patch|minor)[[:space:]]*$ ]]; then
  mode="bump"
  bump_type="${BASH_REMATCH[1]}"
else
  echo "::error::コマンドを解釈できません。'/ai-fix [指示]' または '/ai-bump patch|minor' を使用してください。"
  exit 1
fi

pr_json="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}")"
state="$(jq -r '.state' <<< "$pr_json")"
head_repo="$(jq -r '.head.repo.full_name // ""' <<< "$pr_json")"
head_ref="$(jq -r '.head.ref' <<< "$pr_json")"
head_sha="$(jq -r '.head.sha' <<< "$pr_json")"
base_ref="$(jq -r '.base.ref' <<< "$pr_json")"
title="$(jq -r '.title' <<< "$pr_json")"

if [ "$state" != "open" ]; then
  echo "::error::PR #${PR_NUMBER} は既に閉じられています。"
  exit 1
fi
if [ "$head_repo" != "$GITHUB_REPOSITORY" ]; then
  # フォークのコードを書き込み権限・API キー付きの環境で動かさない。push もできない。
  echo "::error::フォークからの PR は対象外です（head: ${head_repo:-不明}）。"
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$head_sha" ]; then
  echo "::error::チェックアウト後に PR が更新されました。もう一度コマンドを実行してください。"
  exit 1
fi

{
  echo "mode=${mode}"
  echo "bump_type=${bump_type}"
  echo "head_ref=${head_ref}"
  echo "head_sha=${head_sha}"
  echo "base_ref=${base_ref}"
} >> "$GITHUB_OUTPUT"

write_env() {
  local name="$1" value="$2" delimiter
  delimiter="EOF_$(cat /proc/sys/kernel/random/uuid 2> /dev/null || date +%s%N)"
  if [[ "$value" == *"$delimiter"* ]]; then
    echo "::error::入力にデリミタ文字列が含まれています。"
    exit 1
  fi
  printf '%s<<%s\n%s\n%s\n' "$name" "$delimiter" "$value" "$delimiter" >> "$GITHUB_ENV"
}
write_env FIX_INSTRUCTION "${instruction:0:4000}"
write_env PR_TITLE "$title"

{
  echo "### 🛠️ PR への AI 対応 (AI PR Request)"
  echo ""
  echo "| 項目 (Item) | 値 (Value) |"
  echo "| :--- | :--- |"
  echo "| PR | #${PR_NUMBER} (\`${head_ref}\` → \`${base_ref}\`) |"
  echo "| コマンド (Command) | \`/ai-${mode}${bump_type:+ ${bump_type}}\` |"
  echo "| head | \`${head_sha:0:7}\` |"
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
echo "mode=${mode} bump_type=${bump_type} head=${head_ref}@${head_sha:0:7} base=${base_ref}"
