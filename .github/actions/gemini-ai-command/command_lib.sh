#!/usr/bin/env bash
# shellcheck disable=SC2034 # AI_CMD_* は source した呼び出し側で使う変数
# Gemini AI エージェントの `/ai-` コマンドの判定（単一の定義）。
# 修正ワークフロー（受付・resolve_request.sh）とヘルプ（post_help.sh）が同じ境界で判定するため、
# コマンドの受け付け条件はこのファイルだけで定義する。GitHub の条件式（startsWith）は前段の
# 粗い絞り込みにのみ使い、最終的な判定はここで行う。
#
# 使い方: source command_lib.sh; classify_ai_command "$COMMENT_BODY"
# 設定する変数:
#   AI_CMD_KIND        fix / bump / help / unknown（`/ai-` で始まるが解釈できない）/ none（`/ai-` で始まらない）
#   AI_CMD_NAME        1 行目の最初の語（表示用ではない。表示する場合は呼び出し側で安全な文字に絞る）
#   AI_CMD_BUMP_TYPE   bump の場合の patch / minor
#   AI_CMD_INSTRUCTION fix の場合の追加の指示（1 行目の残りと 2 行目以降）

classify_ai_command() {
  local body="${1//$'\r'/}"
  local first_line="${body%%$'\n'*}"
  local rest=""
  [[ "$body" == *$'\n'* ]] && rest="${body#*$'\n'}"

  AI_CMD_KIND=none
  AI_CMD_NAME="${first_line%%[[:space:]]*}"
  AI_CMD_BUMP_TYPE=""
  AI_CMD_INSTRUCTION=""

  if [[ "$first_line" =~ ^/ai-fix([[:space:]]+(.*))?$ ]]; then
    AI_CMD_KIND=fix
    AI_CMD_INSTRUCTION="${BASH_REMATCH[2]:-}"
    if [ -n "$rest" ]; then
      AI_CMD_INSTRUCTION="${AI_CMD_INSTRUCTION:+${AI_CMD_INSTRUCTION}$'\n'}${rest}"
    fi
  elif [[ "$first_line" =~ ^/ai-bump[[:space:]]+(patch|minor)[[:space:]]*$ ]]; then
    AI_CMD_KIND=bump
    AI_CMD_BUMP_TYPE="${BASH_REMATCH[1]}"
  elif [[ "$first_line" =~ ^/ai-help([[:space:]].*)?$ ]]; then
    AI_CMD_KIND=help
  elif [[ "$first_line" == /ai-* ]]; then
    AI_CMD_KIND=unknown
  fi
}
