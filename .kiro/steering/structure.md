# プロジェクト構成

```
common-workflows/
├── .github/
│   └── workflows/
│       ├── base-ci.yml          # 再利用可能: 型チェック・Lint・テスト・ビルド
│       ├── base-release.yml     # 再利用可能: バージョン抽出・ZIP 作成・GitHub Release 公開
│       └── base-security.yml   # 再利用可能: npm audit 脆弱性スキャン
├── docs/
│   └── workflow-guidelines.md  # エコシステム全体の標準ガイドライン（正式仕様）
├── templates/
│   ├── chrome-extension/       # Chrome 拡張機能プロジェクト用スターターテンプレート
│   │   ├── .github/workflows/
│   │   │   ├── ci.yml          # 呼び出し側: base-ci.yml@v1 を参照
│   │   │   └── release.yml     # 呼び出し側: base-release.yml@v1 を参照
│   │   ├── .editorconfig
│   │   ├── .gitignore
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── obsidian-plugin/        # Obsidian プラグイン用スターターテンプレート
│   │   ├── .editorconfig
│   │   └── .gitignore
│   └── vscode-extension/       # VS Code 拡張機能用スターターテンプレート
│       ├── .editorconfig
│       └── .gitignore
└── README.md
```

## 重要な規約

### 基盤ワークフロー（`/.github/workflows/`）

CI/CD ロジックの正式な実装場所。これらは `workflow_call` ターゲットであり、直接トリガーされることはない。すべてのジョブに以下を必須とする：

- `timeout-minutes`（通常 10 分）
- `permissions` は必要最小限（CI は `contents: read`、リリースは `contents: write`）
- 呼び出し側ワークフローに `concurrency` ブロックを設定し、古いビルドをキャンセルする

### テンプレート（`/templates/<種別>/`）

新規プロジェクトのボイラープレート。該当するテンプレートディレクトリを新リポジトリにコピーするだけで、標準準拠の CI/CD をすぐに利用できる。各テンプレートの呼び出しワークフローは `@v1` タグで基盤ワークフローを参照する。

### 呼び出し側ワークフローのファイル名（各プロジェクトリポジトリ内）

| ファイル名 | 役割 |
| :--- | :--- |
| `code-quality.yml` | `base-ci.yml` を呼び出す |
| `release-package.yml` | `base-release.yml` を呼び出す |
| `security-scan.yml` | `base-security.yml` を呼び出す |

### スクリプト分離（`/scripts/`）

10 行を超えるシェルスクリプトや JavaScript は YAML の `run:` ブロックに直接埋め込まず、消費プロジェクトの `scripts/` ディレクトリに外部ファイルとして分離する。実行結果は `$GITHUB_STEP_SUMMARY` に Markdown 形式で出力する。

### ブランチ戦略

- `main` — 保護ブランチ。常時プロダクションリリース可能な状態を維持する
- 機能追加・修正は `feature/*`、`fix/*`、`chore/*` ブランチで作業し、Pull Request 経由でマージする
