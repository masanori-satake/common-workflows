#!/usr/bin/env bash
# /ai-bump patch|minor: ベースブランチのバージョンを基準に新しいバージョンを決め、
# プロジェクトの update-version スクリプトで関連ファイルを一括更新してコミットする。
# AI は使わない（決定的な処理のため）。
#   - CHANGELOG.md の自動生成プレースホルダーは、PR タイトルから作った説明文に置き換える
#   - 更新後に整合性を検証する（VS Code 拡張機能: scripts/check-version.js --check-bump、
#     Chrome 拡張機能: scripts/check_version.py）
#   - update-version スクリプトは VS Code テンプレートの scripts/update-version.js、
#     Chrome テンプレートの scripts/update_version.py（package.json の scripts.update-version から呼ぶ）
#
# 入力（env）: BUMP_TYPE, BASE_REF, PR_NUMBER, PR_TITLE
# 出力（$GITHUB_OUTPUT）: new_version, old_version, changed
set -euo pipefail

: "${BUMP_TYPE:?BUMP_TYPE が未設定です}"
: "${BASE_REF:?BASE_REF が未設定です}"

if [ ! -f package.json ]; then
  echo "::error::package.json が無いため、バージョンを更新できません。"
  exit 1
fi

current="$(node -p "require('./package.json').version")"
base="$(git show "origin/${BASE_REF}:package.json" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).version))")"
if [[ ! "$base" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "::error::ベースブランチ (${BASE_REF}) のバージョンを解釈できません: ${base}"
  exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
case "$BUMP_TYPE" in
  minor) new="${major}.$((minor + 1)).0" ;;
  patch) new="${major}.${minor}.$((patch + 1))" ;;
  *)
    echo "::error::不明な更新種別です: ${BUMP_TYPE}"
    exit 1
    ;;
esac
echo "base=${base} current=${current} -> new=${new} (${BUMP_TYPE})"

if node -e "process.exit(require('./package.json').scripts?.['update-version'] ? 0 : 1)"; then
  npm run update-version -- "$new"
elif [ -f scripts/update-version.js ]; then
  node scripts/update-version.js "$new"
else
  echo "::error::update-version スクリプト（package.json の scripts.update-version または scripts/update-version.js）がありません。common-workflows のテンプレート（VS Code: scripts/update-version.js、Chrome: scripts/update_version.py）を導入してください。"
  exit 1
fi

# CHANGELOG.md: update-version が挿入する「### 追加 (Added)」+ 空の「- 」を実際の説明に置き換える
if [ -f CHANGELOG.md ]; then
  title="${PR_TITLE:-変更}"
  prefix="${title%%:*}"
  desc="$title"
  [[ "$title" == *:* ]] && desc="${title#*:}"
  desc="${desc#"${desc%%[![:space:]]*}"}"
  case "${prefix%%(*}" in
    feat) category="追加 (Added)" ;;
    fix) category="修正 (Fixed)" ;;
    *) category="変更 (Changed)" ;;
  esac
  NEW_VERSION="$new" CATEGORY="$category" DESC="${desc} (#${PR_NUMBER:-?})" node -e '
    const fs = require("fs");
    const { NEW_VERSION: v, CATEGORY: c, DESC: d } = process.env;
    const text = fs.readFileSync("CHANGELOG.md", "utf8");
    const esc = v.replace(/\./g, "\\.");
    const re = new RegExp("(## \\[" + esc + "\\][^\\n]*\\n\\n)### [^\\n]*\\n- *\\n");
    if (re.test(text)) {
      fs.writeFileSync("CHANGELOG.md", text.replace(re, (m, h) => h + "### " + c + "\n- " + d + "\n"));
      console.log("CHANGELOG.md の項目を記入しました: " + c + " / " + d);
    } else {
      console.log("CHANGELOG.md に置き換え対象のプレースホルダーが無いため、そのままにします。");
    }
  '
fi

# 整合性とバージョン昇格の検証
if [ -f scripts/check-version.js ]; then
  VERSION_BASE_REF="origin/${BASE_REF}" node scripts/check-version.js --check-bump
elif [ -f scripts/check_version.py ]; then
  python3 scripts/check_version.py
fi

changed=false
if [ -n "$(git status --porcelain -- . ':(exclude).aider*')" ]; then
  git add -A -- . ':(exclude).aider*' ':(exclude).github/workflows'
  git commit -q -m "chore: バージョンを ${new} に更新 (${BUMP_TYPE})" -m "Refs #${PR_NUMBER:-?}"
  changed=true
fi

{
  echo "new_version=${new}"
  echo "old_version=${current}"
  echo "changed=${changed}"
} >> "$GITHUB_OUTPUT"
{
  echo "### 🔢 バージョン更新 (Version Bump)"
  echo ""
  echo "| 項目 (Item) | 値 (Value) |"
  echo "| :--- | :--- |"
  echo "| 種別 (Type) | \`${BUMP_TYPE}\` |"
  echo "| ベース (Base, ${BASE_REF}) | \`${base}\` |"
  echo "| 更新前 (Before) | \`${current}\` |"
  echo "| 更新後 (After) | \`${new}\` |"
  echo ""
} >> "$GITHUB_STEP_SUMMARY"
