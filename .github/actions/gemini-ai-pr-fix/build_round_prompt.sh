#!/usr/bin/env bash
# AI ジョブ（キーあり・PR のコードは実行しない）で、その回の指示文と対象ファイルを組み立てる。
#   - 1 回目: 準備ジョブが作った指示文（CI の失敗ログ）と対象ファイルをそのまま使う
#   - 2 回目以降: 前回の修正（適用済み）が検証で失敗したログを追記し、前回までに変更した
#     ファイルと、検証ログに出てくる追跡済みファイルを対象ファイルに加える
#   検証ログは PR のコードの出力（信頼しない）だが、AI への指示文として渡すだけで実行はしない。
#
# 入力（env）: CTX_DIR（prompt.md / target_files.txt）, ROUND, PREV_LOG, HEAD_SHA, VERIFY_COMMAND,
#              MAX_PROMPT_CHARS
# 出力（$GITHUB_ENV）: AI_PROMPT, TARGET_FILES
set -euo pipefail

: "${CTX_DIR:?CTX_DIR が未設定です}"
: "${HEAD_SHA:?HEAD_SHA が未設定です}"
ROUND="${ROUND:-1}"
MAX_PROMPT_CHARS="${MAX_PROMPT_CHARS:-20000}"
[[ "$ROUND" =~ ^[1-9]$ ]] || { echo "::error::ROUND が不正です: ${ROUND}"; exit 1; }

prompt="$(cat "${CTX_DIR}/prompt.md")"
read -r -a base_targets <<< "$(cat "${CTX_DIR}/target_files.txt" 2> /dev/null || true)"

targets=()
declare -A seen=()
add_target() {
  local p="${1#./}"
  p="${p#"${GITHUB_WORKSPACE:-/nonexistent}/"}"
  [ -z "$p" ] && return 0
  [ -n "${seen[$p]+x}" ] && return 0
  seen[$p]=1
  [[ "$p" == .github/workflows/* || "$p" == node_modules/* || "$p" == *..* ]] && return 0
  [[ "$p" =~ ^[A-Za-z0-9._@+/-]+$ ]] || return 0
  if [ "${#targets[@]}" -lt 10 ] && git ls-files --error-unmatch -- "$p" > /dev/null 2>&1 && [ -f "$p" ]; then
    targets+=("$p")
  fi
}
for t in "${base_targets[@]+"${base_targets[@]}"}"; do add_target "$t"; done

if [ "$ROUND" -gt 1 ]; then
  # 前回までに変更したファイル（適用済みの patch）を対象に含める
  while IFS= read -r p; do add_target "$p"; done < <(git diff --name-only "$HEAD_SHA" HEAD)

  log=""
  if [ -n "${PREV_LOG:-}" ] && [ -f "$PREV_LOG" ]; then
    log="$(sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "$PREV_LOG")"
  fi
  while IFS= read -r p; do add_target "$p"; done < <(grep -oE '[A-Za-z0-9_.@/-]+\.(ts|tsx|js|jsx|mjs|cjs|json|md|css|html|py)' <<< "$log" || true)

  section=$'\n\n'"## Previous attempt (round $((ROUND - 1))) failed verification"$'\n'
  section+="Your previous fix is already applied to the working tree, but verification still fails."$'\n'
  section+="Verification command: \`${VERIFY_COMMAND:-}\`"$'\n'
  section+="Fix the remaining errors shown in the log below, following the same rules. Keep the earlier changes unless they are the cause."$'\n\n'
  section+="### Verification log (last lines)"$'\n'
  budget=$((MAX_PROMPT_CHARS - ${#prompt} - ${#section} - 32))
  if [ "$budget" -lt 2000 ]; then
    # 元の指示文が長い場合は、元の CI ログ部分を削って検証ログの枠を確保する
    prompt="${prompt:0:$((MAX_PROMPT_CHARS / 2))}"$'\n'"[... truncated ...]"
    budget=$((MAX_PROMPT_CHARS - ${#prompt} - ${#section} - 32))
  fi
  if [ "${#log}" -gt "$budget" ]; then
    log="[... truncated ...]"$'\n'"${log: -$budget}"
  fi
  prompt+="${section}~~~~text"$'\n'"${log}"$'\n'"~~~~"
fi

delimiter="AI_PROMPT_EOF_$(cat /proc/sys/kernel/random/uuid 2> /dev/null || date +%s%N)"
if [[ "$prompt" == *"$delimiter"* ]]; then
  echo "::error::指示文にデリミタ文字列が含まれているため処理を中断します。"
  exit 1
fi
{
  echo "AI_PROMPT<<${delimiter}"
  printf '%s\n' "$prompt"
  echo "${delimiter}"
  echo "TARGET_FILES=${targets[*]+"${targets[*]}"}"
} >> "$GITHUB_ENV"

{
  echo "### 🧠 AI による修正: ${ROUND} 回目 (Fix Round ${ROUND})"
  echo ""
  if [ "${#targets[@]}" -gt 0 ]; then
    echo "- 対象ファイル (Target files): \`${targets[*]}\`"
  else
    echo "- 対象ファイル (Target files): 指定なし（リポジトリ構造から AI が判断）"
  fi
  echo "- 指示文の長さ (Prompt length): ${#prompt} 文字"
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
echo "round=${ROUND} targets=${targets[*]+"${targets[*]}"} prompt_chars=${#prompt}"
