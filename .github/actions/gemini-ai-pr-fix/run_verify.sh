#!/usr/bin/env bash
# 検証ジョブ（キーなし・トークンなし）で、AI の修正を適用した状態を検証する。
#   依存関係のインストール（INSTALL_COMMAND）→ Lint → テスト → ビルド（VERIFY_COMMAND）
#   - インストールの失敗も検証の失敗として扱い、ログを残す（AI の変更で npm ci が壊れた場合も
#     次の回の AI がログを見て直せるようにする）
#   - 検証の失敗はジョブの失敗にしない（結果は status として次の回・公開ジョブへ渡す）
#   - ログの末尾を、次の回の AI への指示文用に保存する
#
# 入力（env）: INSTALL_COMMAND（空ならインストールしない）, VERIFY_COMMAND, LOG_TAIL_LINES
# 出力（$GITHUB_OUTPUT）: status（passed / failed / skipped）
# 出力（ファイル）: $RUNNER_TEMP/ai-verify/verify.log
set -uo pipefail

LOG_TAIL_LINES="${LOG_TAIL_LINES:-200}"
OUT_DIR="${RUNNER_TEMP:-/tmp}/ai-verify"
mkdir -p "$OUT_DIR"
SCRIPT="${OUT_DIR}/verify.sh"
FULL_LOG="${OUT_DIR}/verify.full.log"

if [ -z "${VERIFY_COMMAND:-}" ] && [ -z "${INSTALL_COMMAND:-}" ]; then
  echo "検証コマンドが無いため、検証をスキップします。"
  echo "status=skipped" >> "$GITHUB_OUTPUT"
  : > "${OUT_DIR}/verify.log"
  exit 0
fi

# インストールと検証を 1 つのスクリプトにまとめ、最初に失敗したところで止める
{
  echo "set -e"
  [ -n "${INSTALL_COMMAND:-}" ] && printf '%s\n' "$INSTALL_COMMAND"
  [ -n "${VERIFY_COMMAND:-}" ] && printf '%s\n' "$VERIFY_COMMAND"
} > "$SCRIPT"
label="${INSTALL_COMMAND:+${INSTALL_COMMAND} && }${VERIFY_COMMAND:-}"
echo "::group::検証の実行 (Run Verification): ${label}"
bash "$SCRIPT" > "$FULL_LOG" 2>&1
rc=$?
cat "$FULL_LOG"
echo "::endgroup::"

tail -n "$LOG_TAIL_LINES" "$FULL_LOG" > "${OUT_DIR}/verify.log"
if [ "$rc" -eq 0 ]; then
  status=passed
else
  status=failed
fi
echo "status=${status}" >> "$GITHUB_OUTPUT"
{
  echo "### 🧪 検証結果 (Verification)"
  echo ""
  echo "- コマンド (Command): \`${label}\`"
  echo "- 結果 (Result): $([ "$status" = passed ] && echo '✅ 成功' || echo "❌ 失敗 (exit ${rc})")"
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
echo "status=${status} (exit ${rc})"
exit 0
