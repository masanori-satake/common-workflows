/**
 * README.md のページ内リンク（目次・言語切り替え）を検証するスクリプト。
 *
 * VS Code の拡張機能詳細ページでは、見出しから自動生成される ID（絵文字・日本語を含む）や
 * `<a name="...">` ではページ内ジャンプが機能しない場合があるため、本プロジェクトでは
 * 見出しの直前に ASCII の `<a id="..."></a>` を明示的に置く規約としている。
 *
 * 検証内容:
 *   1. `##` / `###` 見出しの直前の行に `<a id="..."></a>` があること（付け忘れ防止）
 *   2. `<a id="...">` の ID が ASCII（英小文字・数字・ハイフン）で、重複していないこと
 *   3. ページ内リンク `](#xxx)` / `href="#xxx"` のリンク先が明示的な ID として存在すること
 *
 * Usage: node scripts/check-readme-anchors.js [README.md のパス]
 */
const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
// 引数はカレントディレクトリ基準、省略時はリポジトリ直下の README.md
const readmePath = process.argv[2] ? path.resolve(process.argv[2]) : path.join(rootDir, 'README.md');

// ID の付与を必須とする見出しレベル（`##` と `###`）
const REQUIRED_HEADING = /^#{2,3}\s/;
const ANCHOR_LINE = /^<a id="([^"]+)"><\/a>\s*$/;
const VALID_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

const lines = fs.readFileSync(readmePath, 'utf8').split(/\r?\n/);
const errors = [];
const ids = new Map(); // id -> 行番号
const links = []; // { id, line }

let inFence = false;
lines.forEach((line, index) => {
  const lineNo = index + 1;

  // フェンスドコードブロック内は検証対象外
  if (/^\s*(```|~~~)/.test(line)) {
    inFence = !inFence;
    return;
  }
  if (inFence) {
    return;
  }

  // インラインコード（`...`）内の記述は説明文として扱い、検証対象外とする
  const text = line.replace(/`[^`]*`/g, '');

  for (const match of text.matchAll(/<a\s[^>]*\bid="([^"]+)"/g)) {
    const id = match[1];
    if (!VALID_ID.test(id)) {
      errors.push(`L${lineNo}: ID "${id}" は ASCII の英小文字・数字・ハイフンのみで記述してください`);
    }
    if (ids.has(id)) {
      errors.push(`L${lineNo}: ID "${id}" が重複しています（初出: L${ids.get(id)}）`);
    } else {
      ids.set(id, lineNo);
    }
  }

  for (const match of text.matchAll(/\]\(#([^)\s]+)\)|href="#([^"]+)"/g)) {
    links.push({ id: match[1] || match[2], line: lineNo });
  }

  if (REQUIRED_HEADING.test(line)) {
    const prev = index > 0 ? lines[index - 1] : '';
    if (!ANCHOR_LINE.test(prev)) {
      errors.push(`L${lineNo}: 見出し "${line.trim()}" の直前に <a id="..."></a> がありません`);
    }
  }
});

for (const link of links) {
  if (!ids.has(link.id)) {
    errors.push(`L${link.line}: リンク先 "#${link.id}" に対応する <a id="${link.id}"> がありません`);
  }
}

const relPath = path.relative(rootDir, readmePath);
const summary = errors.length === 0
  ? `### README アンカーチェック: 成功\n\n\`${relPath}\`: ${links.length} 件のリンク、${ids.size} 件の ID を検証しました。\n`
  : `### README アンカーチェック: 失敗\n\n${errors.map((e) => `- ${e}`).join('\n')}\n`;

// GitHub Actions 上では実行結果をジョブサマリーにも出力する
if (process.env.GITHUB_STEP_SUMMARY) {
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${summary}\n`, 'utf8');
}

if (errors.length > 0) {
  console.error(`README anchor check FAILED (${relPath}):`);
  errors.forEach((e) => console.error(`  ${e}`));
  process.exit(1);
}
console.log(`README anchor check PASSED (${relPath}): ${links.length} links, ${ids.size} ids.`);
