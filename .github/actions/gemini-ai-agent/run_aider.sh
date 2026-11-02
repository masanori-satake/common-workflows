#!/usr/bin/env bash
# Aider を Gemini API で実行する。
#   - 429 / ResourceExhausted を検知したら指数バックオフ（30s → 60s → 120s）で再試行
#   - TEST_COMMAND 指定時は --auto-test で修正後にテストを実行し、失敗時は AI が自己修正
#   - TARGET_FILES 指定時はそのファイルのみをコンテキストに渡し、リポジトリマップを無効化
#
# GitHub トークンはこのスクリプトに渡さない（Aider・テストと同じプロセスツリーに置かない）。
# Issue 上の状況更新は action.yml の前後の専用ステップで行う。
#
# 入力（env）: AI_PROMPT, TARGET_FILES, GEMINI_API_KEY, MODEL_NAME, TEST_COMMAND,
#              MAX_RETRIES, INITIAL_DELAY
# 出力（$GITHUB_OUTPUT）: agent_status, test_status, attempts
set -euo pipefail

: "${AI_PROMPT:?AI_PROMPT が未設定です（extract_request.sh が先に実行されている必要があります）}"
if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "::error::GEMINI_API_KEY が未設定です。呼び出し側で secrets を渡してください。"
  exit 1
fi

MODEL_NAME="${MODEL_NAME:-gemini-3.8-flash}"
MAX_RETRIES="${MAX_RETRIES:-4}"
DELAY="${INITIAL_DELAY:-30}"
WORK_DIR="${RUNNER_TEMP:-/tmp}/aider"
LOG_FILE="${WORK_DIR}/aider_output.log"
PROMPT_FILE="${WORK_DIR}/prompt.md"
mkdir -p "$WORK_DIR"

# 指示文はファイル経由で渡す（引数長制限と特殊文字の問題を避ける）
printf '%s\n' "$AI_PROMPT" > "$PROMPT_FILE"

# Gemini 無料枠のレートリミット（litellm 経由のエラー表記を含む）
RATE_LIMIT_PATTERN='RateLimitError|RESOURCE_EXHAUSTED|ResourceExhausted|429 Too Many Requests|Too Many Requests|rate limited you'
# 再試行しても回復しない API エラー（キー不正・モデル名誤り等）
FATAL_PATTERN='litellm\.(AuthenticationError|PermissionDeniedError|NotFoundError|BadRequestError)|API key not valid'

read -r -a FILES <<< "${TARGET_FILES:-}"

if [[ ! "$MODEL_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "::error::model_name に使用できない文字が含まれています: ${MODEL_NAME}"
  exit 1
fi

# Aider に既定設定が無い新しいモデルでも適切に動くよう、モデル設定を明示する。
#   - edit_format: diff-fenced（Gemini 向けの差分形式。未知モデル既定の whole は毎回
#     ファイル全体を送受信するため無料枠のトークンを浪費する）
#   - use_temperature: false（temperature を送らず API 既定値を使う。Gemini 3 系は
#     既定値以外の temperature で応答品質が低下し得る）
MODEL_SETTINGS_FILE="${WORK_DIR}/model-settings.yml"
cat > "$MODEL_SETTINGS_FILE" <<EOF
- name: gemini/${MODEL_NAME}
  edit_format: diff-fenced
  use_repo_map: true
  use_temperature: false
EOF

# リポジトリ由来の Aider 設定を読み込ませない。Aider は git ルートの .aider.conf.yml・.env・
# .aider.model.settings.yml・.aider.model.metadata.json を自動で読み込むため、リポジトリ（PR）に
# 置くだけで API の送信先やテストコマンド等を書き換えられる。.env は --env-file を指定しても
# git ルートのものが読み込まれるため、実行中はファイル自体を退避する（終了時に元へ戻す）。
EMPTY_CONFIG="${WORK_DIR}/empty.aider.conf.yml"
EMPTY_ENV="${WORK_DIR}/empty.env"
# 設定ファイルは空のマッピング（{}）にする。空ファイルは YAML として None になり、
# Aider（configargparse）が「key: value の形式ではない」としてエラー終了するため
printf '{}\n' > "$EMPTY_CONFIG"
: > "$EMPTY_ENV"
QUARANTINE_DIR="${WORK_DIR}/quarantine"
QUARANTINE_FILES=(.env .aider.conf.yml .aider.model.settings.yml .aider.model.metadata.json)
mkdir -p "$QUARANTINE_DIR"
quarantine_repo_config() {
  local f
  for f in "${QUARANTINE_FILES[@]}"; do
    if [ -e "$f" ] || [ -L "$f" ]; then
      if [ -e "${QUARANTINE_DIR}/${f}" ] || [ -L "${QUARANTINE_DIR}/${f}" ]; then
        rm -rf -- "$f" # 再試行時の作業ツリー復元で戻った分（退避済み）は削除するだけ
      else
        mv -- "$f" "${QUARANTINE_DIR}/${f}"
        echo "::notice::リポジトリの ${f} を Aider の実行中だけ退避しました。"
      fi
    fi
  done
}
restore_repo_config() {
  local f
  for f in "${QUARANTINE_FILES[@]}"; do
    if [ -e "${QUARANTINE_DIR}/${f}" ] || [ -L "${QUARANTINE_DIR}/${f}" ]; then
      rm -rf -- "$f"
      mv -- "${QUARANTINE_DIR}/${f}" "$f"
    fi
  done
}
trap restore_repo_config EXIT

ARGS=(
  --model "gemini/${MODEL_NAME}"
  --model-settings-file "$MODEL_SETTINGS_FILE"
  --config "$EMPTY_CONFIG"
  --env-file "$EMPTY_ENV"
  --yes-always
  --no-auto-commits
  --no-dirty-commits
  --no-gitignore
  --no-check-update
  --analytics-disable
  --no-show-model-warnings
  --no-pretty
  --no-stream
  --no-fancy-input
  --no-restore-chat-history
  # --yes-always と組み合わせると任意のシェル実行・URL 取得が自動承認されるため無効化
  --no-suggest-shell-commands
  --no-detect-urls
  --chat-history-file "${WORK_DIR}/chat-history.md"
  --input-history-file "${WORK_DIR}/input-history.txt"
  --message-file "$PROMPT_FILE"
)
TEST_SCRIPT="${WORK_DIR}/run_tests.sh"
if [ -n "${TEST_COMMAND:-}" ]; then
  # テストはリポジトリのコード（AI が編集し得る）を実行するため、API キーを渡さない。
  # Aider の自動テスト subprocess は Aider の環境変数を継承するので、ラッパー経由で除去する。
  # TEST_COMMAND をスクリプトファイルに書き出すことで、引数のクォート問題も避ける。
  printf '%s\n' "$TEST_COMMAND" > "$TEST_SCRIPT"
  ARGS+=(--auto-test --test-cmd "env -u GEMINI_API_KEY bash $(printf '%q' "$TEST_SCRIPT")")
fi
if [ "${#FILES[@]}" -gt 0 ]; then
  # 対象ファイル指定時はリポジトリマップを送らずトークン消費を抑える
  ARGS+=(--map-tokens 0)
fi

# 再試行前に作業ツリーを初期状態へ戻す（途中まで適用された編集の二重適用を防ぐ）。
# .aider* と .gitignore 対象（node_modules 等）は残す。
reset_worktree() {
  git checkout -- . 2> /dev/null || true
  git clean -fdq -e '.aider*'
}

echo "対象ファイル (Target files): ${FILES[*]+"${FILES[*]}"}"

attempt=1
agent_status="failed"
while :; do
  echo "::group::試行 ${attempt}/${MAX_RETRIES}: Aider 実行 (Attempt ${attempt}/${MAX_RETRIES})"
  quarantine_repo_config
  set +e
  aider "${ARGS[@]}" "${FILES[@]+"${FILES[@]}"}" 2>&1 | tee "$LOG_FILE"
  exit_code=${PIPESTATUS[0]}
  set -e
  echo "::endgroup::"
  cp "$LOG_FILE" "${WORK_DIR}/aider_output.attempt${attempt}.log"

  # Aider は API エラー時も終了コード 0 を返すことがあるため、ログ内容で判定する
  if grep -qE "$RATE_LIMIT_PATTERN" "$LOG_FILE"; then
    echo "::warning::Gemini API のレートリミット (429) を検知しました。(Rate limit detected)"
  elif grep -qE "$FATAL_PATTERN" "$LOG_FILE"; then
    echo "::error::Gemini API が回復不能なエラーを返しました。API キーとモデル名を確認してください。"
    break
  elif [ "$exit_code" -ne 0 ]; then
    echo "::error::Aider がレートリミット以外のエラーで終了しました (exit code: ${exit_code})。"
    break
  else
    echo "Aider の実行が完了しました。(Aider executed successfully)"
    agent_status="success"
    break
  fi

  if [ "$attempt" -ge "$MAX_RETRIES" ]; then
    echo "::error::最大試行回数 (${MAX_RETRIES}) に達しました。(Max retries reached)"
    break
  fi

  echo "${DELAY} 秒待機して再試行します... (Backing off ${DELAY}s)"
  reset_worktree
  sleep "$DELAY"
  DELAY=$((DELAY * 2))
  attempt=$((attempt + 1))
done

# 最終テスト結果の確認（PR を Draft にするかの判定に使う）。
# テストには API キーを渡さない。
test_status="skipped"
if [ "$agent_status" = "success" ] && [ -n "${TEST_COMMAND:-}" ]; then
  # 最終テストはリポジトリの設定ファイルを戻した状態で実行する
  restore_repo_config
  echo "::group::最終テストの実行 (Final Test Run)"
  if env -u GEMINI_API_KEY bash "$TEST_SCRIPT" > "${WORK_DIR}/final_test.log" 2>&1; then
    test_status="passed"
  else
    test_status="failed"
  fi
  tail -n 100 "${WORK_DIR}/final_test.log"
  echo "::endgroup::"
fi

{
  echo "agent_status=${agent_status}"
  echo "test_status=${test_status}"
  echo "attempts=${attempt}"
} >> "$GITHUB_OUTPUT"

{
  echo "### 🛠️ Aider 実行結果 (Aider Result)"
  echo ""
  echo "| 項目 (Item) | 値 (Value) |"
  echo "| :--- | :--- |"
  echo "| モデル (Model) | \`gemini/${MODEL_NAME}\` |"
  echo "| 試行回数 (Attempts) | ${attempt} / ${MAX_RETRIES} |"
  echo "| 実行結果 (Agent) | $([ "$agent_status" = success ] && echo '✅ success' || echo '❌ failed') |"
  echo "| 最終テスト (Test) | ${test_status} |"
  echo ""
} >> "$GITHUB_STEP_SUMMARY"

if [ "$agent_status" != "success" ]; then
  exit 1
fi
