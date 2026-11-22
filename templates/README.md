# リポジトリ標準テンプレートと開始手順

2026-11-22 に統一したルール（ブランチルールと pre-commit 標準セット）を、新しいリポジトリへ確実に適用するための正本と手順です。「標準」は文章ではなくこのテンプレートツリーの実ファイルを指し、ずれは diff で検出します。

## テンプレートツリー

種別ごとの雛形が既にあります。新規リポジトリは対応するツリーをコピーして始めます。

| ツリー | 用途 |
|---|---|
| `templates/vscode-extension/` | VS Code 拡張（呼び出し側ワークフロー、scripts、package.json 雛形を含む） |
| `templates/chrome-extension/` | Chrome 拡張（同上） |
| `templates/obsidian-plugin/` | Obsidian プラグイン |

## 2026-11-22 の標準（pre-commit と Markdown）

| ファイル | 内容 | 出どころ |
|---|---|---|
| `.markdownlint.json`（両ツリー） | Markdown 検査の設定 | TabMagnet-Solo 版に統一 |
| `vscode-extension/.pre-commit-config.yaml` | 共通コア＋markdownlint＋check-version | SkillTrace-Solo |
| `vscode-extension/scripts/check-version.js` | 版バンプと版整合性のチェック（`.markdownlint.json` は対象外に含む） | SkillTrace-Solo |
| `chrome-extension/.pre-commit-config.yaml` | ci: ブロック標準形＋共通コア＋markdownlint＋prettier | Replace-Solo（固有の除外指定は除去済み） |

## 新規リポジトリの開始手順

1. **ファイル配置**: 種別ツリーをコピーする。
   - Chrome 側の local フック（check-root-files、check-version、audit-production-dependencies）は、対応する `scripts/` がある場合だけ有効にする。check-version は版を持つリポジトリでは必須。
   - ルート許可リスト（check_root_files.py）には `.markdownlint.json` を必ず含める。
2. **README**: シリーズ標準形式にする（冒頭にバッヂ4点＋言語切替、English 全文 → Japanese 全文の同節構成）。見出しの H1 は英語タイトル1つだけ（日本語側は H2 の「日本語」の下に置く。markdownlint の MD025 対策）。
3. **CI**: code-quality の呼び出し側ワークフロー（base CI）が入っていることを確認する。ストアへ公開するものは store-release の呼び出し側も追加する。
4. **ルールセット**: 「main」を型Pで作成する（PR 必須、承認0件、古いレビューの却下あり、ブランチ削除と force push は禁止）。初回 CI が緑になったら、必須ステータスチェックに base CI「品質検証・ビルド (Validate & Build)」を追加する。
5. **リポジトリ所有者の操作**（エージェントからはできない）: pre-commit.ci の対象リポジトリへ追加する。デプロイキーを登録する（公開鍵はエージェントが渡す）。リリース自動化を使う場合は Secrets を登録する。
6. **ダッシュボード**: アイデアダッシュボードと Solo/Duo シリーズダッシュボードに入っているか確認し、なければ追加する。

## 例外（意図的に標準と違うもの）

- QuickLog-Solo: eslint／stylelint／jest はプラグイン構成の local フックのまま維持する。
- DeskDeck-Solo、My-VSIX: 古典的ブランチ保護（型A）のままで同等とみなす。
- C2M-Export: Python 主体のため ruff 系の標準が別にある。
- 停止中のリポジトリ（SiteSearch-Solo、TidyGroup-Solo）は対象外。

## ずれ検査

月1回、全リポジトリの設定ファイルをこのテンプレートと突き合わせ、ルールセットと必須チェックの状態も確認します。ファイルのずれは修正 PR を作って報告し、GitHub 側設定のずれは報告のみとします（Muse の定期ジョブで実施）。
