# VSCode 拡張機能テンプレート (VSCode Extension Template)

新規 VSCode 拡張機能プロジェクトの立ち上がりを助けるスターターテンプレートです。
`common-workflows` リポジトリの再利用可能ワークフロー（`base-ci-vscode.yml` /
`base-release-vscode.yml` / `base-security.yml`）を `@v1` タグで参照し、
標準準拠の CI/CD をコピーするだけで利用できます。

<a id="usage"></a>
## 利用方法

1. このディレクトリ（`templates/vscode-extension/`）の中身を新規リポジトリの
   ルートにコピーします。

2. `package.json` をプロジェクト固有の値に書き換えます:
   - `name` / `displayName` / `publisher` / `version` / `description`
   - `engines.vscode`（必要に応じて）
   - `main`（ビルド方式に応じて `./out/extension.js` または `./dist/extension.js`）
   - `scripts.build` / `scripts.lint` / `scripts.test` を実装に合わせて書き換え
     （`scripts.lint` を書き換える際は、末尾の `&& npm run check-readme-anchors` を残してください）

3. `scripts/update-version.js` の「★ プロジェクトごとに編集する箇所 ★」を
   プロジェクト固有の VSIX ファイル名プレフィックスに書き換えます。
   詳細は `scripts/README.md` を参照してください。

4. `.vscodeignore` をビルド方式に合わせて調整します。esbuild 等でバンドルして
   `dist/` を出力する場合は、`out/**` と `node_modules/**` の除外を有効にします。
   `npx vsce ls` で VSIX に同梱されるファイルを確認し、拡張機能の実行に不要な
   ファイルが含まれていないことを確かめてください。

5. リポジトリのシークレットに以下を設定します:
   - `VSCE_PAT` — Visual Studio Marketplace 公開用 PAT
   - `OVSX_PAT` — Open VSX Registry 公開用 PAT

6. `common-workflows` リポジトリの `v1` タグが最新 commit を指していることを
   確認してください（タグの移動はユーザーが手動で行います）。

7. プロジェクトの `README.md` では、`##` / `###` 見出しの直前に ASCII の
   `<a id="..."></a>` を置き、目次などのページ内リンクはその ID を参照します。
   VS Code の拡張機能詳細ページでは、絵文字や日本語を含む見出しの自動 ID や
   `<a name="...">` ではジャンプできない場合があるためです。
   `scripts/check-readme-anchors.js` が `npm run lint` と pre-commit フックでこの規約を検査します。

8. （任意）Gemini AI エージェントを使う場合は、
   [Gemini AI エージェント導入ガイド](https://github.com/masanori-satake/common-workflows/blob/main/docs/ai-agent-setup.md)
   に従って `GEMINI_API_KEY` シークレット・`ai-task` ラベル・Actions の PR 作成許可を設定します。
   使わない場合は `.github/workflows/ai-coder-trigger.yml` を削除してください。

<a id="files"></a>
## 含まれるファイル

| パス | 役割 |
| :--- | :--- |
| `.github/workflows/code-quality.yml` | CI 呼出: `base-ci-vscode.yml@v1`（push / PR / 手動） |
| `.github/workflows/release-package.yml` | リリース呼出: `base-release-vscode.yml@v1`（main から手動） |
| `.github/workflows/security-scan.yml` | セキュリティスキャン呼出: `base-security.yml@v1`（push / PR / 定期） |
| `.github/workflows/ai-coder-trigger.yml` | AI エージェント呼出: `gemini-ai-agent-template.yml@v1`（Issue ラベル / `/ai` コメント）、`gemini-ai-pr-fix-template.yml@v1`（PR の `/ai-fix` / `/ai-bump` コメント） |
| `.github/osv-scanner.toml` | OSV-Scanner 設定（devDependencies の脆弱性を合否判定から除外） |
| `scripts/check-version.js` | 版整合性 ＋ 版バンプ検査（正本テンプレート・編集不要） |
| `scripts/update-version.js` | 版一括更新（★ VSIX ファイル名正規表現を編集） |
| `scripts/check-readme-anchors.js` | README のページ内リンク・見出し ID 検査（正本テンプレート・編集不要） |
| `scripts/run-pre-commit-check.sh` | pre-commit フック用エントリ（正本テンプレート・編集不要） |
| `scripts/README.md` | スクリプトの役割と編集指針 |
| `.pre-commit-config.yaml` | pre-commit フック定義（正本テンプレート・編集不要） |
| `package.json` | スターター用 npm scripts 定義 |
| `tsconfig.json` | strict モード TypeScript 設定 |
| `.editorconfig` | エディタ設定（スペース2・LF・UTF-8） |
| `.gitignore` | 無視対象定義（node_modules / dist / out / *.vsix / .agents 等） |
| `.vscodeignore` | VSIX から除外するファイルの定義（★ ビルド方式に合わせて調整） |

<a id="workflows"></a>
## ワークフローの動作

- **コード品質検証 (code-quality.yml):** push / PR 時に版チェック・Lint・
  テスト（xvfb ラップ）・ビルドを実行します。
- **リリース (release-package.yml):** main ブランチから手動実行（workflow_dispatch）
  で VSIX 生成 → Marketplace 公開 → Open VSX 公開 → GitHub Release 作成を行います。
- **セキュリティスキャン (security-scan.yml):** push / PR / 定期実行で
  npm audit と OSV-Scanner を実行します。
- **AI エージェント (ai-coder-trigger.yml):** Issue への `ai-task` ラベル付与または
  `/ai` コメントで、Aider + Gemini API がコードを修正し PR を作成します。PR に `/ai-fix` と
  コメントすると失敗した CI を修正し、`/ai-bump patch|minor` でバージョンを更新します。
