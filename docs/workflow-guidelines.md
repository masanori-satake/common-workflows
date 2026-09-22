# 共通開発 & GitHub Actions ワークフロー運用ガイドライン (Workflow Guidelines)

本ドキュメントは、本エコシステム配下のすべてのプロジェクト（Chrome拡張機能、VS Code拡張機能、Obsidianプラグイン等）における開発標準、GitHub Actions ワークフローの標準構造、設計原則、および運用ルールを規定した標準ガイドラインです。
人間および AI エージェント（Jules / Claude Code / Amazon Kiro 等）が新しいプロジェクトを構築・メンテナンスする際、本ガイドラインに従ってください。

---

## 1. 目的と基本思想

プロジェクト数の増加に伴い、CI/CD ワークフローの定義方法や命名規則が統一されていないと、メンテナンスコストの増大やトラブルシューティングの遅延につながります。
本標準規格は、以下の価値を提供することを目的とします：

1. **一目でわかる可視性**: 実行画面を見ただけで「何が」「どういう目的で」実行され、「どこで」失敗したかが直感的に理解できる。
2. **高い再利用性 (Reusability)**: `common-workflows` リポジトリによる共通ワークフローの一括管理と、プロジェクト固有処理の明確な分離。
3. **安全・高品質な標準適用**: タイムアウト、最小限のパーミッション設定、セキュリティチェックなどを全ワークフローに標準適用する。

---

## 2. 開発基本原則 (Development Principles)

- **Spec-Driven Development (SDD) の徹底**
  - 実装前に必ず仕様書（`SPEC.md` や `AGENTS.md`）を策定・更新し、AIエージェントおよび人間開発者が同一の文脈で開発を進めます。
- **依存関係の最小化 (Zero/Minimal Dependencies)**
  - 保守性とセキュリティを高めるため、可能な限り Vanilla JS/TS 標準機能を活用し、外部ライブラリへの依存を最小限に抑えます。
- **厳格な型定義と静的解析**
  - TypeScript は Standard `strict` モードで運用します。
  - `npm run typecheck` および `npm run lint` が警告なしで通過することを PR マージの絶対条件とします。

---

## 3. Git & リポジトリ運用規約 (Repository Rules)

- **ブランチ戦略**
  - `main`: 常時プロダクションリリース可能な保護ブランチ。
  - 機能追加・修正は `feature/*`, `fix/*`, `chore/*` ブランチを作成し、Pull Request 経由でマージします。
- **コミットメッセージ規約 (Conventional Commits)**
  - `feat:` 新機能 / `fix:` バグ修正 / `docs:` ドキュメント / `style:` フォーマット / `refactor:` リファクタリング / `test:` テスト / `chore:` ビルド・設定
- **バージョニングルール (Semantic Versioning)**
  - `vX.Y.Z` 形式（例: `v1.0.0`）を厳格に遵守します。

---

## 4. ワークフローファイル構造と命名規約

個別のプロジェクトでは、用途が直感的にわかる英語のハイフン区切り (`kebab-case.yml`) で呼び出し用ワークフローを配置し、処理の基盤は `common-workflows` の Reusable Workflows を呼び出します。

| ファイル名 | 役割・用途 | 参照する共通ワークフロー |
| :--- | :--- | :--- |
| `.github/workflows/code-quality.yml` | コード品質の検証（Lint, TypeCheck, Test） | `common-workflows/.../base-ci.yml@v1` |
| `.github/workflows/release-package.yml` | タグ打刻・Release作成・成果物公開 | `common-workflows/.../base-release.yml@v1` |
| `.github/workflows/security-scan.yml` | セキュリティ・依存関係の脆弱性スキャン | 独立ジョブまたは共通スキャン |

---

## 5. 表記ルール（日本語・英語併記）

ワークフローの名称 (`name`) および各ステップの名称 (`- name:`) は、GitHub UI 上で直感的に理解できるように **日本語 (English)** 形式で併記します。

### 例:

```yaml
name: 'コード品質検証 (Code Quality)'

on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  quality-check:
    name: '共通品質チェック実行 (Execute Base Quality Checks)'
    uses: masanori-satake/common-workflows/.github/workflows/base-ci.yml@v1
```

---

## 6. 複雑な判定ロジックの分離とリッチサマリー ($GITHUB_STEP_SUMMARY)

YAML 内の `run: |` に長文のシェルスクリプトや JavaScript を直接埋め込むことは避けてください。

1. **分離の基準**: 10行を超えるロジック、条件分岐、JSONパースが含まれる処理は `scripts/` ディレクトリ配下の独立スクリプト（例: `scripts/validate-manifest.js`）に分離します。
2. **サマリー連携**: 各ジョブや主要スクリプトでは、実行結果を `$GITHUB_STEP_SUMMARY` 環境変数経由で GitHub Actions の Job Summary に Markdown 形式で可視化します。

### 出力フォーマット例:

```markdown
### 📋 マニフェスト・ロケール検証結果 (Manifest & Locales Validation)

| ファイル (File) | 状態 (Status) |
| :--- | :--- |
| `package.json` | ✅ Parsed |
| `manifest.json` | ✅ Parsed |

**統一バージョン (Unified Version):** `1.0.0`
✅ すべての検証項目が正常にクリアされました。
```

---

## 7. 必須セキュリティ＆パフォーマンス規則

すべてのワークフロー（共通ワークフローおよび個別プロジェクト側呼び出し定義）には、以下の項目を **必ず** 明記してください。

1. **タイムアウトの設定 (`timeout-minutes`)**:
   - 無限ループやハングアップによる無駄な実行時間の消費を防ぐため、Job 単位で必ず設定します。（例: `timeout-minutes: 10`）
2. **最小権限の原則 (`permissions`)**:
   - ワークフロー全体または Job 単位で必要な Token 権限のみを最小限付与します。（通常CIは `contents: read`、リリース時は `contents: write`）
3. **並行実行制御 (`concurrency`)**:
   - 同一 PR / ブランチへの連続 Push 時に古いビルドをキャンセルし、リソースを節約します。

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

## 8. プラットフォーム別考慮事項 (Platform Guidelines)

- **Chrome 拡張機能**: Manifest V3 に準拠し、不要なパーミッションを要求しない設計とします。
- **VS Code 拡張機能**: `package.json` の `engines` 記述やアクティベーションイベントを最小化します。
- **Obsidian プラグイン**: `manifest.json` と `versions.json` の整合性を保持し、公式の審査基準に従います。

---

## 9. 新規プロジェクトのセットアップ (Onboarding)

新規プロジェクトを作成する際は、`common-workflows` の `templates/<種別>` ディレクトリから以下をコピーして初期化します。

1. `.github/workflows/code-quality.yml` および `release-package.yml` の配置
2. `.editorconfig`, `.gitignore`, `tsconfig.json` の配置
3. `package.json` の `scripts`（`typecheck`, `lint`, `test`）の準備

---

## 10. AI エージェント（Jules / Claude Code / Kiro 等）への適用指示ガイド

他のリポジトリで本規約を AI エージェントに適用・構築させる場合は、以下のプロンプトテンプレートを渡してください。

### AI 向けインストラクションプロンプト例:

> 「`https://raw.githubusercontent.com/masanori-satake/common-workflows/main/docs/workflow-guidelines.md` を参照し、本リポジトリの GitHub Actions ワークフローを標準ガイドラインに完全準拠させてください。
>
> 1. 共通CI/CD基盤として `masanori-satake/common-workflows` の Reusable Workflows (`@v1`) を参照してください。
> 2. 個別ワークフローファイル名は `code-quality.yml`, `release-package.yml` などの kebab-case で作成してください。
> 3. すべてのワークフロー名・ステップ名に '日本語 (English)' の二言語併記ルールを適用してください。
> 4. 各 Job に `timeout-minutes`（例: 10分）、最小限の `permissions`、および `concurrency` を設定してください。
> 5. 複雑なインラインスクリプトは `scripts/` ディレクトリに外部ファイル化し、`$GITHUB_STEP_SUMMARY` に結果を出力させてください。」