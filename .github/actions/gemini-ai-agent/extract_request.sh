#!/usr/bin/env bash
# GitHub イベント（Issue / Issue コメント）から AI への指示文と対象ファイルを抽出し、
# $GITHUB_ENV に AI_PROMPT / TARGET_FILES として安全に書き出す。
#
# 入力（すべて env 経由。${{ }} の直接埋め込みはスクリプトインジェクションになるため使わない）:
#   EVENT_NAME, ISSUE_NUMBER, ISSUE_TITLE, ISSUE_BODY, COMMENT_BODY,
#   COMMAND_PREFIX, MAX_PROMPT_CHARS, MAX_TARGET_FILES
#
# 対象ファイル指定: 本文中の "Files: path/a.ts, path/b.ts" 行（大文字小文字不問、
# 箇条書き記号・太字・バッククォート可）。コメントに無ければ Issue 本文から探す。
# Git 追跡済みの通常ファイルで、安全な文字のみからなる相対パスだけを受け付ける。
set -euo pipefail
export LC_ALL=C.UTF-8 # ${#var} / ${var:0:n} を文字単位で扱う

MAX_PROMPT_CHARS="${MAX_PROMPT_CHARS:-20000}"
MAX_TARGET_FILES="${MAX_TARGET_FILES:-20}"

# GitHub の本文は CRLF のことがあるため CR を除去する
strip_cr() { printf '%s' "${1//$'\r'/}"; }

issue_title="$(strip_cr "${ISSUE_TITLE:-}")"
issue_body="$(strip_cr "${ISSUE_BODY:-}")"
comment_body="$(strip_cr "${COMMENT_BODY:-}")"

# ---------------------------------------------------------------------------
# 指示文の組み立て
# ---------------------------------------------------------------------------
instruction=""
case "${EVENT_NAME:-}" in
  issues)
    instruction="$issue_body"
    ;;
  issue_comment)
    instruction="$comment_body"
    prefix="${COMMAND_PREFIX:-}"
    if [ -n "$prefix" ] && [[ "$instruction" == "$prefix"* ]]; then
      instruction="${instruction#"$prefix"}"
    fi
    ;;
  *)
    instruction="Perform general code improvements."
    ;;
esac

# 文字列全体の前後の空白・空行を除去（行内のインデントは保持する）
instruction="${instruction#"${instruction%%[![:space:]]*}"}"
instruction="${instruction%"${instruction##*[![:space:]]}"}"

if [ -z "$instruction" ] && [ -z "$issue_title" ]; then
  echo "::error::指示文が空です。Issue 本文またはコメントに作業内容を記述してください。"
  exit 1
fi

TRUNC_MARK=$'\n\n'"[... truncated ...]"
truncated=false

# 指示文（コメント起動ではコメント、Issue 起動では本文）を先頭に置き、上限内に必ず残す。
# コメント起動時の Issue 本文は背景情報として後ろに置き、残りの文字数に収まる分だけ含める。
prompt="# Task: GitHub Issue #${ISSUE_NUMBER:-N/A}"$'\n\n'"## Title"$'\n'"${issue_title}"
if [ "${EVENT_NAME:-}" = "issue_comment" ]; then
  prompt+=$'\n\n'"## Instruction (from comment)"$'\n'"${instruction}"
else
  prompt+=$'\n\n'"## Description"$'\n'"${instruction}"
fi

if [ "${#prompt}" -gt "$MAX_PROMPT_CHARS" ]; then
  prompt="${prompt:0:$MAX_PROMPT_CHARS}${TRUNC_MARK}"
  truncated=true
elif [ "${EVENT_NAME:-}" = "issue_comment" ] && [ -n "$issue_body" ]; then
  bg_header=$'\n\n'"## Issue description (background, for reference only)"$'\n'
  remaining=$((MAX_PROMPT_CHARS - ${#prompt} - ${#bg_header}))
  if [ "${#issue_body}" -le "$remaining" ]; then
    prompt+="${bg_header}${issue_body}"
  elif [ "$remaining" -gt 0 ]; then
    prompt+="${bg_header}${issue_body:0:$remaining}${TRUNC_MARK}"
    truncated=true
  else
    truncated=true
  fi
fi

if [ "$truncated" = true ]; then
  echo "::warning::指示文が ${MAX_PROMPT_CHARS} 文字を超えたため切り詰めました（指示部分を優先して保持）。"
fi

# ---------------------------------------------------------------------------
# 対象ファイルの抽出と検証
# ---------------------------------------------------------------------------
# "Files:" 行の値部分だけを取り出す（複数行あれば連結）
extract_files_lines() {
  printf '%s\n' "$1" \
    | grep -iE '^[[:space:]]*([-*+][[:space:]]+)?(\*\*|__)?files(\*\*|__)?[[:space:]]*:' \
    | sed -E 's/^[^:]*:[[:space:]]*//; s/^(\*\*|__)[[:space:]]*//' \
    || true
}

files_raw="$(extract_files_lines "$comment_body")"
if [ -z "$files_raw" ]; then
  files_raw="$(extract_files_lines "$issue_body")"
fi

accepted=()
rejected=()
declare -A seen=()

# カンマ・空白区切りでトークン化
read -r -a tokens <<< "$(printf '%s' "$files_raw" | tr ',\n\t' '   ')"
for tok in "${tokens[@]+"${tokens[@]}"}"; do
  # 装飾（バッククォート・引用符）と先頭の ./ を除去
  tok="${tok//\`/}"; tok="${tok//\"/}"; tok="${tok//\'/}"
  tok="${tok#./}"
  [ -z "$tok" ] && continue

  reason=""
  if [[ ! "$tok" =~ ^[A-Za-z0-9._@+/-]+$ ]]; then
    reason="使用できない文字を含む"
  elif [[ "$tok" == /* || "$tok" == -* ]]; then
    reason="絶対パス・オプション形式は不可"
  elif [[ "/$tok/" == */../* ]]; then
    reason="親ディレクトリ参照 (..) は不可"
  elif ! git ls-files --error-unmatch -- "$tok" > /dev/null 2>&1 || [ ! -f "$tok" ]; then
    reason="Git 追跡済みのファイルではない"
  elif [ -n "${seen[$tok]+x}" ]; then
    continue
  elif [ "${#accepted[@]}" -ge "$MAX_TARGET_FILES" ]; then
    reason="上限 ${MAX_TARGET_FILES} 件を超過"
  fi

  if [ -n "$reason" ]; then
    rejected+=("$tok|$reason")
  else
    accepted+=("$tok")
    seen[$tok]=1
  fi
done

# ---------------------------------------------------------------------------
# $GITHUB_ENV への書き出し（ランダムなデリミタで複数行値を安全に渡す）
# ---------------------------------------------------------------------------
delimiter="AI_PROMPT_EOF_$(cat /proc/sys/kernel/random/uuid 2> /dev/null || date +%s%N)"
if [[ "$prompt" == *"$delimiter"* ]]; then
  echo "::error::指示文にデリミタ文字列が含まれているため処理を中断します。"
  exit 1
fi
{
  echo "AI_PROMPT<<${delimiter}"
  printf '%s\n' "$prompt"
  echo "${delimiter}"
} >> "$GITHUB_ENV"

# 受理したパスは安全な文字のみ（改行なし）なので単一行で渡せる
echo "TARGET_FILES=${accepted[*]+"${accepted[*]}"}" >> "$GITHUB_ENV"

# ---------------------------------------------------------------------------
# サマリー出力
# ---------------------------------------------------------------------------
{
  echo "### 🤖 AI への指示内容 (AI Request)"
  echo ""
  echo "- イベント (Event): \`${EVENT_NAME:-}\` / Issue: #${ISSUE_NUMBER:-N/A}"
  echo "- 指示文の長さ (Prompt length): ${#prompt} 文字$([ "$truncated" = true ] && echo '（切り詰めあり）')"
  echo ""
  if [ "${#accepted[@]}" -eq 0 ] && [ "${#rejected[@]}" -eq 0 ]; then
    echo "対象ファイル指定なし（リポジトリマップから AI が判断します）。"
  else
    echo "| ファイル (File) | 状態 (Status) |"
    echo "| :--- | :--- |"
    for f in "${accepted[@]+"${accepted[@]}"}"; do
      echo "| \`$f\` | ✅ 対象 |"
    done
    for r in "${rejected[@]+"${rejected[@]}"}"; do
      echo "| \`${r%%|*}\` | ⚠️ 除外: ${r#*|} |"
    done
  fi
  echo ""
} >> "$GITHUB_STEP_SUMMARY"

echo "対象ファイル: ${accepted[*]+"${accepted[*]}"}"
for r in "${rejected[@]+"${rejected[@]}"}"; do
  echo "::warning::対象ファイルから除外: ${r%%|*}（${r#*|}）"
done
