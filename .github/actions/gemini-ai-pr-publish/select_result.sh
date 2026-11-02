#!/usr/bin/env bash
# 公開ジョブで、各ジョブ（ai-N / verify-N / bump）の結果から公開する作業結果を選ぶ。
#   - /ai-fix: 変更を作った最後の回の累積 patch と、その回の検証結果を使う
#   - /ai-bump: bump ジョブの patch を使う
#   ai / verify / bump ジョブの出力は信頼しない値として扱い、apply_patch.sh で形式を検証する。
#
# 入力（env）: NEEDS_JSON（toJSON(needs)）, MODE, WORK_ACTION, ARTIFACT_PREFIX, MAX_ROUNDS
# 出力（$GITHUB_OUTPUT）: patch_artifact, has_patch, rounds, test_status, new_version, attempts, work_failed
set -euo pipefail

: "${NEEDS_JSON:?NEEDS_JSON が未設定です}"
: "${ARTIFACT_PREFIX:?ARTIFACT_PREFIX が未設定です}"
MAX_ROUNDS="${MAX_ROUNDS:-3}"

need() { jq -r --arg j "$1" --arg k "$2" '.[$j][$k] // ""' <<< "$NEEDS_JSON"; }
need_out() { jq -r --arg j "$1" --arg k "$2" '.[$j].outputs[$k] // ""' <<< "$NEEDS_JSON"; }

patch_artifact=""
has_patch=false
rounds=0
test_status=""
new_version=""
work_failed=false

if [ "${WORK_ACTION:-}" = "patch" ] && [ "${MODE:-}" = "bump" ]; then
  if [ "$(need bump result)" = "success" ]; then
    new_version="$(need_out bump new_version)"
    if [ "$(need_out bump has_patch)" = "true" ]; then
      patch_artifact="${ARTIFACT_PREFIX}-patch-bump"
      has_patch=true
    fi
  else
    work_failed=true
  fi
elif [ "${WORK_ACTION:-}" = "patch" ] && [ "${MODE:-}" = "fix" ]; then
  for n in $(seq 1 "$MAX_ROUNDS"); do
    result="$(need "ai-${n}" result)"
    [ -z "$result" ] || [ "$result" = "skipped" ] && break
    rounds="$n"
    if [ "$result" != "success" ]; then
      # 1 回目が失敗した場合は作業結果なし。2 回目以降の失敗は、それまでの結果を公開する
      [ "$n" -eq 1 ] && work_failed=true
      rounds=$((n - 1))
      break
    fi
    if [ "$(need_out "ai-${n}" changed)" = "true" ]; then
      patch_artifact="${ARTIFACT_PREFIX}-patch-${n}"
      has_patch=true
      # 検証ジョブが成功以外（失敗・タイムアウト・キャンセル等）で終わった場合は、検証は通っていないので failed とする
      if [ "$(need "verify-${n}" result)" = "success" ]; then
        test_status="$(need_out "verify-${n}" status)"
      else
        test_status=failed
      fi
    fi
  done
fi

{
  echo "patch_artifact=${patch_artifact}"
  echo "has_patch=${has_patch}"
  echo "rounds=${rounds}"
  echo "attempts=${rounds}"
  echo "test_status=${test_status}"
  echo "new_version=${new_version}"
  echo "work_failed=${work_failed}"
} >> "$GITHUB_OUTPUT"
echo "mode=${MODE:-} action=${WORK_ACTION:-} rounds=${rounds} patch=${patch_artifact:-none} test=${test_status:-none} failed=${work_failed}"
