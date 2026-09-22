# GitHub Actions ワークフロー設計・運用ガイドライン (Workflow Guidelines)

本ドキュメントは、本プロジェクト（DeskDeck-Solo）における GitHub Actions ワークフローの標準構造、設計原則、および他のプロジェクトへ展開する際の模範運用ルールを規定した標準ガイドラインです。
人間および AI エージェント（Jules / Copilot 等）が新しいプロジェクトにワークフローを構築・メンテナンスする際、本ガイドラインに従ってください。

---

## 1. 目的と基本思想

プロジェクト数の増加に伴い、CI/CD ワークフローの定義方法や命名規則が統一されていないと、メンテナンスコストの増大やトラブルシューティングの遅延につながります。
本標準規格は、以下の価値を提供することを目的とします：

1. **一目でわかる可視性**: 実行画面を見ただけで「何が」「どういう目的で」実行され、「どこで」失敗したかが直感的に理解できる。
2. **高い再利用性 (Reusability)**: プロジェクト固有の処理と汎用的な処理を分離し、共通アクションや外部スクリプトに切り出すことで、他リポジトリへ横展開しやすくする。
3. **安全・高品質な標準適用**: タイムアウト、最小限のパーミッション設定、セキュリティチェックなどを全ワークフローに標準適用する。

---

## 2. ワークフローファイル命名規約

ワークフローの YAML ファイル名は、用途が直感的にわかる英語のハイフン区切り (`kebab-case.yml`) とします。

| ファイル名                                  | 役割・用途                                                                         |
| ------------------------------------------- | ---------------------------------------------------------------------------------- |
| `.github/workflows/code-quality.yml`        | コード品質の検証（リンター、フォーマッタ、型チェック、単体テスト、整合性チェック） |
| `.github/workflows/security-scan.yml`       | セキュリティ・依存関係の脆弱性スキャン                                             |
| `.github/workflows/deploy-landing-page.yml` | Webサイト・LP（GitHub Pages等）への自動デプロイ                                    |
| `.github/workflows/release-package.yml`     | タグ打刻・リリース成果物 (ZIP/Binary) の自動パッケージングと公開                   |

---

## 3. 表記ルール（日本語・英語併記）

ワークフローの名称 (`name`) および各ステップの名称 (`- name:`) は、GitHub UI 上で直感的に理解できるように **日本語 (English)** 形式で併記します。

### 例:

```yaml
name: 'コード品質検証 (Code Quality)'

jobs:
  validate:
    name: 'コード品質・テスト検証 (Validate Code & Tests)'
    steps:
      - name: 'リポジトリのチェックアウト (Checkout Repository)'
        uses: actions/checkout@v4

      - name: 'Node.js環境と依存関係のセットアップ (Setup Node.js & Dependencies)'
        uses: ./.github/actions/setup-node-deps
```

---

## 4. 共通 Composite Action 化規約

複数ジョブや他プロジェクトで共通して用いられる初期化スクリプトや環境構築は、`.github/actions/<action-name>/action.yml` に Composite Action として定義します。

### 推奨構造: `.github/actions/setup-node-deps/action.yml`

- Node.js のセットアップ (`actions/setup-node`) と package-lock.json に応じた高速キャッシュ付きインストール (`npm ci`) をカプセル化します。
- ワークフロー呼び出し側では 1 ステップで呼び出せるようにします。

---

## 5. 複雑な判定ロジックのスクリプト分離方針

YAML 内の `run: |` に長文のシェルスクリプトや JavaScript を直接埋め込むことは避けてください。

1. **分離の基準**:
   - 10行を超えるロジック
   - 条件分岐や JSON パース、正規表現判定が含まれる処理
2. **配置場所**:
   - `scripts/` ディレクトリ配下に独立した Node.js スクリプト（例: `scripts/validate-manifest-locales.js`）として作成します。
3. **サマリー連携**:
   - スクリプト内で `$GITHUB_STEP_SUMMARY` 環境変数を参照し、Markdown 形式で表やチェックマーク付きのサマリーを出力する機能を実装します。

---

## 6. リッチサマリー ($GITHUB_STEP_SUMMARY) の標準出力フォーマット

各ジョブおよび主要スクリプトでは、実行結果を GitHub Actions の Top ページ (Job Summary) に可視化してください。

### 出力フォーマット例:

```markdown
### 📋 マニフェスト・ロケール検証結果 (Manifest & Locales Validation)

| ファイル (File)                          | 状態 (Status) |
| ---------------------------------------- | ------------- |
| `package.json`                           | ✅ Parsed     |
| `projects/app/manifest.json`             | ✅ Parsed     |
| `projects/app/_locales/ja/messages.json` | ✅ Valid JSON |

**統一バージョン (Unified Version):** `0.1.2`
✅ すべての検証項目が正常にクリアされました。
```

---

## 7. 必須セキュリティ＆パフォーマンス規則

すべてのワークフローファイルには、以下の項目を **必ず** 明記してください。

1. **タイムアウトの設定 (`timeout-minutes`)**:
   - 無限ループやネットワークハングによる無駄な GitHub Actions 実行時間の消費を防ぐため、Job 単位で必ず設定します。（例: `timeout-minutes: 10`）
2. **最小権限の原則 (`permissions`)**:
   - ワークフロー全体または Job 単位で必要な Token 権限のみを最小限付与します。（例: リリース作成時は `contents: write`、通常 CI は `contents: read`）
3. **並行実行制御 (`concurrency`)**:
   - 同一 PR / ブランチへの連続 Push 時に古いビルドをキャンセルの上、リソース節約を図る `concurrency` グループを設定します。

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

## 8. AI エージェント（Jules 等）への適用指示ガイド

他のリポジトリで本規約を AI エージェントに適用・構築させる場合は、以下のプロンプトテンプレートを渡してください。

### AI 向けインストラクションプロンプト例:

> 「`docs/workflow-guidelines.md` を参照し、本リポジトリの GitHub Actions ワークフローを標準ガイドラインに完全準拠させてください。
>
> 1. ワークフローファイル名は `code-quality.yml`, `deploy-landing-page.yml`, `security-scan.yml`, `release-package.yml` に統一してください。
> 2. すべてのワークフロー名・ステップ名に '日本語 (English)' の二言語併記ルールを適用してください。
> 3. 各 Job に `timeout-minutes` と最小限の `permissions` を設定してください。
> 4. インラインの複雑なスクリプトは `scripts/` ディレクトリに外部ファイル化し、`$GITHUB_STEP_SUMMARY` に結果を出力させてください。
> 5. 共通の Node.js セットアップは `.github/actions/setup-node-deps` を作成して共通化してください。」