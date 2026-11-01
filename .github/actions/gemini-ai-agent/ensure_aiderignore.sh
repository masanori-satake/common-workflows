#!/usr/bin/env bash
# .aiderignore がリポジトリに無い場合に既定の除外リストを生成する。
# 巨大なビルド成果物・依存関係・ロックファイル・秘密情報を AI の読込対象から外し、
# コンテキスト超過とトークン浪費を防ぐ。生成したファイルは PR にコミットしない
# （create_pr.sh が .aider* を除外する）。
set -euo pipefail

if [ -f .aiderignore ]; then
  echo "既存の .aiderignore を使用します。"
  echo "- \`.aiderignore\`: リポジトリ既存のものを使用" >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

cat > .aiderignore <<'EOF'
# --- 依存関係 (Dependencies) ---
node_modules/
venv/
.venv/
__pycache__/
# --- ビルド成果物・キャッシュ (Build outputs & caches) ---
dist/
build/
out/
coverage/
.vscode-test/
*.vsix
*.zip
*.log
# --- ロックファイル（巨大でトークンを浪費する） (Lockfiles) ---
*.lock
package-lock.json
pnpm-lock.yaml
# --- VCS・CI 定義（GITHUB_TOKEN ではワークフローを更新できない） (VCS & CI) ---
.git/
.github/workflows/
# --- 秘密情報 (Secrets) ---
.env
.env.*
*.pem
*.key
EOF

echo ".aiderignore を自動生成しました。"
echo "- \`.aiderignore\`: 既定の除外リストを自動生成" >> "$GITHUB_STEP_SUMMARY"
