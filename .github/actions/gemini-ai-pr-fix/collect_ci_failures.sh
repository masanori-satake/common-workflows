#!/usr/bin/env bash
# PR の head コミットで失敗した CI を集め、AI への指示文と対象ファイルを組み立てる。
#   - ワークフローごとに最新の実行だけを見る（再実行で成功済みなら対象外）
#   - 失敗ステップのログ末尾だけを渡してトークンを節約する
#   - ログに出てくる Git 追跡済みファイルを対象ファイルとして抽出する
#   - バージョンチェックの失敗は AI に直させず、/ai-bump の案内に回す
#
# 入力（env）: GH_TOKEN, PR_NUMBER, HEAD_SHA, PR_TITLE, FIX_INSTRUCTION, TEST_COMMAND,
#              LOG_TAIL_LINES, MAX_PROMPT_CHARS
# 出力（$GITHUB_OUTPUT）: failed_count, pending_count, version_check_failed,
#                         failed_workflows / all_workflows（再実行対象のワークフローファイル名）,
#                         verify_command
# 出力（$GITHUB_ENV）  : AI_PROMPT, TARGET_FILES
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN が未設定です}"
: "${HEAD_SHA:?HEAD_SHA が未設定です}"
LOG_TAIL_LINES="${LOG_TAIL_LINES:-200}"
MAX_PROMPT_CHARS="${MAX_PROMPT_CHARS:-20000}"
WORK_DIR="${RUNNER_TEMP:-/tmp}/aider"
mkdir -p "$WORK_DIR"
VERSION_STEP_PATTERN='Check Version Bump|版バンプ|バージョン更新'

# head コミットの実行をワークフローごとに最新 1 件へ絞る（自分自身の実行は除く）
runs_json="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs?head_sha=${HEAD_SHA}&per_page=100" \
  --jq "[.workflow_runs[] | select(.id != ${GITHUB_RUN_ID:-0})] | group_by(.workflow_id) | map(max_by(.created_at))")"

failed_ids=()
mapfile -t failed_ids < <(jq -r '.[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .id' <<< "$runs_json")
pending_count="$(jq '[.[] | select(.status != "completed")] | length' <<< "$runs_json")"
failed_workflows="$(jq -r '[.[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .path | split("/") | last] | unique | join(" ")' <<< "$runs_json")"
# /ai-bump では新しいコミットで全 CI をやり直すため、完了済みの全ワークフローを再実行対象にする
all_workflows="$(jq -r '[.[] | select(.status == "completed") | .path | split("/") | last] | unique | join(" ")' <<< "$runs_json")"

failed_steps=""
logs=""
for id in "${failed_ids[@]+"${failed_ids[@]}"}"; do
  wf_name="$(jq -r --argjson id "$id" '.[] | select(.id == $id) | .name' <<< "$runs_json")"
  # shellcheck disable=SC2016 # $j は jq の変数（シェル展開不要）
  steps="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${id}/jobs" \
    --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name as $j
          | (.steps // [])[] | select(.conclusion == "failure" or .conclusion == "timed_out") | "\($j) / \(.name)"' || true)"
  while IFS= read -r s; do
    [ -n "$s" ] && failed_steps+="- ${wf_name} / ${s}"$'\n'
  done <<< "$steps"
  # "<job>\t<step>\t<timestamp> <line>" 形式から本文だけを取り出し、ANSI エスケープを除去
  log="$(gh run view "$id" --repo "$GITHUB_REPOSITORY" --log-failed 2> /dev/null \
    | cut -f3- | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z ?//; s/\x1b\[[0-9;]*[A-Za-z]//g' \
    | tail -n "$LOG_TAIL_LINES" || true)"
  logs+="### ${wf_name} (run ${id})"$'\n'"~~~~text"$'\n'"${log}"$'\n'"~~~~"$'\n\n'
done
failed_count="${#failed_ids[@]}"

version_check_failed=false
if grep -qE "$VERSION_STEP_PATTERN" <<< "$failed_steps"; then
  version_check_failed=true
fi

# 検証コマンド: CI と同じ順に Lint → テスト → ビルド（package.json がある場合）
verify_command="${TEST_COMMAND:-}"
if [ -f package.json ]; then
  verify_command="npm run lint --if-present${TEST_COMMAND:+ && ${TEST_COMMAND}} && npm run build --if-present"
fi

{
  echo "failed_count=${failed_count}"
  echo "pending_count=${pending_count}"
  echo "version_check_failed=${version_check_failed}"
  echo "failed_workflows=${failed_workflows}"
  echo "all_workflows=${all_workflows}"
  echo "verify_command=${verify_command}"
} >> "$GITHUB_OUTPUT"

{
  echo "### 🔎 CI の失敗 (Failed Checks)"
  echo ""
  if [ "$failed_count" -eq 0 ]; then
    echo "失敗した CI はありません（実行中: ${pending_count} 件）。"
  else
    printf '%s\n' "$failed_steps"
    echo "- バージョンチェックの失敗 (Version check failed): \`${version_check_failed}\`"
  fi
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
printf '%s' "$logs" > "${WORK_DIR}/ci_failures.md"
echo "failed=${failed_count} pending=${pending_count} version_check_failed=${version_check_failed}"
printf '%s' "$failed_steps"

# 失敗が無い、またはバージョンチェックの失敗なら AI 用の指示文は作らない
if [ "$failed_count" -eq 0 ] || [ "$version_check_failed" = true ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 対象ファイル: ログに出てくる Git 追跡済みファイル（最大 10 件、ワークフロー定義は除く）
# ---------------------------------------------------------------------------
targets=()
declare -A seen=()
while IFS= read -r p; do
  p="${p#./}"
  p="${p#"${GITHUB_WORKSPACE:-/nonexistent}/"}"
  [ -z "$p" ] || [ -n "${seen[$p]+x}" ] && continue
  seen[$p]=1
  [[ "$p" == .github/workflows/* || "$p" == node_modules/* || "$p" == *..* ]] && continue
  if git ls-files --error-unmatch -- "$p" > /dev/null 2>&1 && [ -f "$p" ]; then
    targets+=("$p")
  fi
  [ "${#targets[@]}" -ge 10 ] && break
done < <(grep -oE '[A-Za-z0-9_.@/-]+\.(ts|tsx|js|jsx|mjs|cjs|json|md|css|html|py)' <<< "$logs" || true)

# ---------------------------------------------------------------------------
# 指示文の組み立て（ログは上限内に収まるよう切り詰める）
# ---------------------------------------------------------------------------
header="# Task: Fix the CI failure in Pull Request #${PR_NUMBER:-?}"$'\n\n'
header+="## PR title"$'\n'"${PR_TITLE:-}"$'\n\n'
header+="## Failed checks (workflow / job / step)"$'\n'"${failed_steps}"$'\n'
if [ -n "${FIX_INSTRUCTION:-}" ]; then
  header+="## Additional instruction (from the PR comment)"$'\n'"${FIX_INSTRUCTION}"$'\n\n'
fi
rules="## Rules"$'\n'
rules+="- Identify the root cause from the logs and fix it in the source or test code."$'\n'
rules+="- Do not weaken, skip, or delete tests, lint rules, or type checks to make the checks pass."$'\n'
rules+="- Do not modify .github/workflows/, the version in package.json / package-lock.json, or CHANGELOG.md."$'\n'
rules+="- If the failure is caused by the environment (network, registry, GitHub outage) rather than the code, make no changes."$'\n'
logs_header="## Failure logs (last ${LOG_TAIL_LINES} lines of each failed run)"$'\n\n'

budget=$((MAX_PROMPT_CHARS - ${#header} - ${#rules} - ${#logs_header} - 32))
if [ "$budget" -lt 0 ]; then budget=0; fi
if [ "${#logs}" -gt "$budget" ]; then
  # エラーはログ末尾に出ることが多いため、末尾側を残す
  logs="[... truncated ...]"$'\n'"${logs: -$budget}"
  echo "::warning::CI ログが長いため末尾 ${budget} 文字に切り詰めました。"
fi
prompt="${header}${rules}"$'\n'"${logs_header}${logs}"

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

echo "対象ファイル: ${targets[*]+"${targets[*]}"}"
{
  if [ "${#targets[@]}" -gt 0 ]; then
    echo "- 対象ファイル (Target files): \`${targets[*]}\`"
  else
    echo "- 対象ファイル (Target files): 指定なし（リポジトリ構造から AI が判断）"
  fi
  echo "- 指示文の長さ (Prompt length): ${#prompt} 文字"
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
