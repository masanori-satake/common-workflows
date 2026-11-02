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

   - ただし、外部レジストリへの公開を伴うリリースワークフロー（例: VSCode 拡張機能の `release-package.yml`）では、公開途中のキャンセルによる部分公開を防ぐため `cancel-in-progress: false` とし、実行を直列化します。

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

---

## 11. 統一パラメータと共通ワークフロー (Unified Parameters & Reusable Workflows)

プロジェクトごとにばらついていたパラメータを `common-workflows` 内のデフォルト値へ**閉じ込め**、呼び出し側の `with:` を極力空にすることで、各プロジェクトのメンテナンスコストを最小化します。

### 11.1 統一パラメータ一覧 (Unified Parameters)

以下は Solo エコシステム全体の**固定値**です。値の変更が必要な場合は、原則として各プロジェクトではなく `common-workflows` の base ワークフロー側で一括更新します。

| 項目 (Item) | 統一値 (Unified Value) | 定義元 (Defined In) |
| :--- | :--- | :--- |
| Node.js バージョン | `lts/*`（常に最新 LTS を追従） | `base-ci` / `base-release` / `base-security` |
| Python バージョン | `3.12`（明示固定） | `base-ci` / `base-release` |
| 依存インストール | lockfile 自動判定（`package-lock.json` あり→`npm ci` / なし→`npm install`） | `base-ci` / `base-release` |
| Playwright | `requirements.txt` 経由 + `chromium --with-deps`（存在時のみ） | `base-ci` / `base-release` |
| Python チェック入口 | `scripts/ci_checks.py`（存在すれば実行する単一エントリ） | `base-ci` |
| Lint / Test | 全件実行（差分限定の最適化は行わない） | `base-ci` |
| npm audit | 実行（`--audit-level=high`） | `base-security` |
| OSV-Scanner | 実行（バージョンを一元管理） | `base-security` |
| リリース対象 | `releases/*.zip`（無ければ従来の zip 生成） | `base-release` |
| `project_name` | リポジトリ名を自動採用（`github.event.repository.name`） | `base-release` |
| Pages 公開ディレクトリ | `projects/web` | `base-deploy-pages` |
| 版バンプ判定 | `projects/app/manifest.json` を jq で比較 | `base-version-bump` |

> **`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` は共通化せず廃止します。** 恒久的なフラグ化は避け、`common-workflows` 側で actions のバージョンを新しく保つ運用で対応します。

### 11.2 CI ポリシーチェックの単一エントリ (`scripts/ci_checks.py`)

各プロジェクトが個別に持っていた Python ポリシースクリプト群（`check_root_files.py` / `verify_project_policies.py` / `check_version.py` / `verify_version_impact.py` / `audit_production_dependencies.py` 等）は、`scripts/ci_checks.py` という**単一エントリ**にまとめ、その中から順に呼び出します。`base-ci` はこのファイルが存在すれば自動実行するため、呼び出し側での指定は不要です。

### 11.3 呼び出し側テンプレート (Caller Templates)

統一パラメータが base 側に閉じ込められているため、各プロジェクトの呼び出しワークフローは以下のように**ほぼ `with:` 不要**になります。

```yaml
# .github/workflows/code-quality.yml
name: 'コード品質検証 (Code Quality)'
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    name: '共通品質チェック実行 (Execute Base CI)'
    uses: masanori-satake/common-workflows/.github/workflows/base-ci.yml@v1
    # with: は原則不要（統一パラメータが base 側に閉じ込められている）
```

```yaml
# .github/workflows/security-scan.yml
name: 'セキュリティスキャン (Security Scan)'
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  security:
    name: '共通セキュリティスキャン実行 (Execute Base Security)'
    uses: masanori-satake/common-workflows/.github/workflows/base-security.yml@v1
```

```yaml
# .github/workflows/release-package.yml
name: 'リリースパッケージ公開 (Release Package)'
on:
  push:
    tags: ['v*.*.*']
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  release:
    name: '共通リリース処理実行 (Execute Base Release)'
    uses: masanori-satake/common-workflows/.github/workflows/base-release.yml@v1
```

```yaml
# .github/workflows/deploy-pages.yml
name: 'Pagesデプロイ (Deploy Pages)'
on:
  push:
    branches: [main]
    paths: ['projects/web/**']
  workflow_dispatch:
jobs:
  deploy:
    name: '共通Pagesデプロイ実行 (Execute Base Deploy Pages)'
    uses: masanori-satake/common-workflows/.github/workflows/base-deploy-pages.yml@v1
```

```yaml
# .github/workflows/version-bump.yml
name: 'バージョン更新確認 (Version Bump Check)'
on:
  pull_request:
    branches: [main]
    paths: ['projects/app/**']   # パスフィルタは呼び出し側で指定する
jobs:
  version-bump:
    name: '共通バージョン確認実行 (Execute Base Version Bump)'
    uses: masanori-satake/common-workflows/.github/workflows/base-version-bump.yml@v1
```

### 11.4 例外的に `with:` を指定するケース (When to Override)

統一値で賄えない**明確な必然性**がある場合のみ、呼び出し側で上書きします。例:

- TypeScript を使わない Vanilla JS プロジェクトで型チェックを止めたい: `run_typecheck: false`
- `npm audit` が不要なプロジェクト: `run_npm_audit: false`
- OSV のスキャン対象を変更したい: `osv_scan_args: ...`

それ以外のパラメータ（Node/Python バージョン、インストールコマンド等）は**呼び出し側で上書きしない**のが原則です。

---

## 12. 共通スクリプトとテンプレート (Shared Scripts & Templates)

プロジェクト間で重複しがちな処理を、以下の2段階で「独自実装の削減」を図る。

### 12.1 共通 composite action: アイコン生成 (generate-icons)

SVG から PNG アイコンを生成する処理は、全プロジェクトでほぼ同一だったため
**共通 composite action** に集約した。各プロジェクトは `generate_png_icons.py`
を自前で持つ必要がなくなる。

- 場所: `masanori-satake/common-workflows/.github/actions/generate-icons@v1`
- 呼び出し: `base-release.yml` の `generate_icons: true` で自動的に使用される。
- 入力（すべて任意・既定あり）: `svg_path` / `output_dir` / `file_prefix` / `sizes` /
  `bg_color`（ブランド色差し替え）/ `python_version` / `playwright_version`
- action 内で Python・Playwright(chromium) のセットアップまで完結する。

```yaml
# 呼び出し側 release-package.yml の例
jobs:
  release:
    uses: masanori-satake/common-workflows/.github/workflows/base-release.yml@v1
    permissions:
      contents: write
    with:
      generate_icons: true
```

### 12.2 スクリプトのテンプレート (check_version / create_package / ci_checks)

`check_version.py` と `create_package.py` は各プロジェクトの実ファイル構成に
強く依存するため**共通化はしない**。代わりに `templates/chrome-extension/scripts/`
に「設定駆動で拡張しやすい雛形」と解説（`scripts/README.md`）を配置し、
新規プロジェクトがコピーして最小限の編集で使えるようにした。

- `ci_checks.py` — CI ポリシーチェックの単一エントリ（`base-ci.yml` が自動実行）
- `check_version.py` — `VERSION_SOURCES` にファイルを列挙するだけの整合性チェック
- `update_version.py` — `JSON_TARGETS`/`TEXT_TARGETS` を列挙するだけのバージョン一括更新。`npm run update-version -- <X.Y.Z>`
  から呼び、PR の `/ai-bump` も同じスクリプトを使う（VS Code 拡張機能の `update-version.js` と呼び出し方を揃える）
- `create_package.py` — `SOURCE_DIR`/`EXCLUDE_*`/`RENAME_MAP` を編集する ZIP 生成

これにより「共通化はできないが、ゼロから書き起こす必要もない」状態を作り、
プロジェクトごとの実装のユニーク性を最小化する。

---

## 13. カバレッジ計測と PR コメント (Coverage & PR Comment)

テストカバレッジをエコシステム全体で統一的に可視化し、将来的に一定水準まで
引き上げていくため、カバレッジ計測と PR への sticky コメント投稿を共通化する。

### 13.1 共通ワークフロー: base-coverage.yml

- 場所: `masanori-satake/common-workflows/.github/workflows/base-coverage.yml@v1`
- 動作:
  1. `npm run coverage`（存在すれば実行。無ければスキップ）
  2. `coverage/coverage-summary.json` を集計
  3. `pull_request` 時に PR へ sticky コメントを投稿（既存コメントは更新）
- inputs（すべて任意・既定あり）:
  - `node_version`（既定 `lts/*`）
  - `min_coverage`（既定 `0` = 強制しない。将来引き上げ時に `> 0` を指定すると
    行カバレッジが下限未満で CI を失敗させる）
  - `coverage_file`（既定 `coverage/coverage-summary.json`）
- 第三者 Action 非依存。集計は共通 composite action `coverage-comment` が担当し、
  `gh` で PR コメントを作成/更新する。

### 13.2 統一スクリプト規約: `npm run coverage`

各プロジェクトは `package.json` に `coverage` スクリプトを用意し、**json-summary**
レポーターで `coverage/coverage-summary.json` を出力する。jest / vitest いずれも
同一形式で出力できるため、共通ワークフローはランナー非依存で集計できる。

```jsonc
// jest プロジェクト
{ "scripts": { "coverage": "jest --coverage --coverageReporters=json-summary text" } }

// vitest プロジェクト
{ "scripts": { "coverage": "vitest run --coverage --coverage.reporter=json-summary --coverage.reporter=text" } }
```

カバレッジ非対応のプロジェクト（Playwright E2E 主体など）は `coverage` スクリプトを
定義しないことで、ワークフローが自動的にスキップする。

### 13.3 呼び出し側テンプレート

```yaml
# .github/workflows/coverage.yml
name: 'カバレッジ (Coverage)'
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
  pull-requests: write
jobs:
  coverage:
    name: '共通カバレッジ計測実行 (Execute Base Coverage)'
    uses: masanori-satake/common-workflows/.github/workflows/base-coverage.yml@v1
    # 将来カバレッジ下限を強制する場合のみ:
    # with:
    #   min_coverage: '80'
```

### 13.4 廃止した従来手法

カバレッジの README バッジ自動コミットや、カバレッジ HTML レポートの GitHub Pages
公開は行わない。PR コメントによる可視化に一本化する（バッジ自動コミットはブランチ
保護や履歴汚染の観点でも扱いにくいため）。

---

## 14. リリース ZIP 名の統一 (Unified Release ZIP Naming)

Release に添付する拡張機能パッケージ（ZIP）のファイル名を、エコシステム全体で
**`{リポジトリ名}-v{version}.zip`**（例: `OmniView-Solo-v1.1.6.zip`）に統一する。

従来は各プロジェクトの build スクリプトが `package.json` の `name`（小文字。例
`actionsboard-solo`）を使って命名しており、`actionsboard-solo-v1.1.4.zip` のように
バラついていた。これを解消するため、ZIP 生成と命名を base-release 側に集約する（方式A）。

### 14.1 使い方

`base-release.yml` に `package_source_dir` を指定すると、base-release が共通 action
`package-extension` を使って ZIP を統一命名で生成する。ZIP 名は
`{project_name}-v{version}.zip`（`project_name` の既定はリポジトリ名）。

```yaml
jobs:
  release:
    uses: masanori-satake/common-workflows/.github/workflows/base-release.yml@v1
    permissions:
      contents: write
    with:
      package_source_dir: 'projects/app'
      # manifest.chrome.json を同梱時に manifest.json へリネームする場合のみ:
      # manifest_rename: 'manifest.chrome.json:manifest.json'
      # SVG からアイコンを生成する場合:
      # generate_icons: true
```

- `package_source_dir` 指定時、各プロジェクトの `build` スクリプトは **ZIP を作らない**。
  素材（`projects/app`）を用意する（必要ならアイコン生成・バージョン検証を行う）だけでよい。
- 除外ルール（`node_modules` / `test-results` / `_metadata` / ドット始まり / `thumbs.db` 等、
  ただし `_locales` は保持）は共通 action 側に集約済み。
- `manifest_rename` で ZIP 内リネーム（例 `manifest.chrome.json → manifest.json`）に対応。

### 14.2 移行の指針

各プロジェクトは build スクリプトから ZIP 生成ロジックを取り除き、`package_source_dir` を
指定する形へ移行する。これにより ZIP 名がリポジトリ名ベースに統一され、`package.json` の
`name`（小文字慣例）に依存しなくなる。

---

## 15. Gemini AI エージェント (Gemini AI Agent)

GitHub の Issue / コメントを指示文として、Aider + Gemini API（Google AI Studio 無料枠）で
コードを修正し、変更があれば PR を作成する仕組みを共通化する。

### 15.1 構成

- 共通ワークフロー: `masanori-satake/common-workflows/.github/workflows/gemini-ai-agent-template.yml@v1`。
  15.5 の PR 修正と同じく、ジョブごとに実行境界を分ける

  | ジョブ | GitHub トークン | Gemini キー | リポジトリのコード実行 | 内容 |
  | :--- | :--- | :--- | :--- | :--- |
  | `acknowledge` | Issue 書込 | なし | しない | 受付通知（起動ガードもここで判定） |
  | `prepare` | 読み取りのみ | なし | しない | 指示文・対象ファイルの抽出、検証コマンドの決定（同一 Issue はここだけ直列化） |
  | `ai-1`〜`ai-3` | なし | あり | しない | Aider で修正（テストなし）。累積の patch を artifact で渡す |
  | `verify-1`〜`verify-3` | なし | なし | する | patch を適用し、`npm ci` と Lint → テスト → ビルドで検証。失敗時のログを次の回の AI に渡す |
  | `publish` | 書き込み | なし | しない | 作業結果を検証してブランチに push、PR 作成（最後の検証が失敗なら Draft）、Issue に報告 |

- Issue 固有の composite action: `.github/actions/gemini-ai-agent`（`stage: prepare / publish`）
  - `ensure_aiderignore.sh` — `.aiderignore` が無ければ既定の除外リストを生成（`ai` ステージから使う）
  - `extract_request.sh` — 指示文と `Files:` 指定を抽出し、`$GITHUB_ENV` へランダムデリミタで書き出す
  - `run_aider.sh` — 429 指数バックオフ再試行（30s → 60s → 120s、最大 4 回）。`ai` ステージから使う
  - `create_pr.sh` — 適用済みの作業結果をブランチ `chore/ai-issue-<番号>-<run_id>` に push し PR 作成
- AI による修正と検証は PR 修正の `.github/actions/gemini-ai-pr-fix`（`stage: ai / verify`）を共用し、
  作業結果の選択と検証は `gemini-ai-pr-publish` の `select_result.sh` / `apply_patch.sh` を共用する
- 状況表示 composite action: `.github/actions/gemini-ai-agent-status`（`status_comment.sh`）
  - `acknowledge` ジョブ（concurrency の順番待ちの外）が即座に 👀 と状況コメントを投稿し、「作業ジョブで処理中」にする
  - 作業系ジョブは状況コメントを書く権限を持たないため、作業中は更新しない。`publish` が
    作業完了（修正回数・検証結果）→ PR 作成中 → 完了（`finish`）を表示する
  - 完了時に 👀 を 🚀 / 😕 に切り替え。書き換えでは通知が飛ばないため、結果は新規コメントでも知らせる
  - 補助機能のため、API エラーが起きても本体の処理は失敗させない
- 呼び出し側テンプレート: `templates/<種別>/.github/workflows/ai-coder-trigger.yml`

### 15.2 使い方

- Issue に `ai-task` ラベルを付与する、または `/ai <指示>` で始まるコメントを投稿する。
- 本文に `Files: src/a.ts, src/b.ts` 行を書くと、そのファイルのみを AI に渡し、
  リポジトリマップも無効化してトークン消費を抑える。Git 追跡済みファイルのみ受け付ける。
- 最後の検証（Lint → `test_command` → ビルド）が失敗した場合は Draft PR になる。

### 15.3 事前準備

テンプレート利用者向けの Web 画面での詳細手順は [Gemini AI エージェント導入ガイド](./ai-agent-setup.md) を参照する。

1. リポジトリ Secrets に `GEMINI_API_KEY` を登録する。
2. Settings > Actions > General で「Allow GitHub Actions to create and approve pull requests」を有効化する。
3. 呼び出し側ジョブに `contents: write` / `issues: write` / `pull-requests: write` を付与する。

### 15.4 セキュリティと制約

- AI が変更したコード（テストを含む）と依存パッケージは、`GITHUB_ENV` / `GITHUB_PATH`（`BASH_ENV` 等）・
  `.git/config`・同じジョブのプロセスのメモリを通じて同じジョブの後続ステップに影響し得る。そのため
  `GITHUB_TOKEN` の書き込み権限と `GEMINI_API_KEY` は、コードを実行しない別ジョブ（`publish` / `ai-N`）にだけ渡す。
  コードを実行する `verify-N` はキーもトークンも持たず、npm キャッシュも使わない。
- コメント起動は `author_association` が `OWNER` / `MEMBER` / `COLLABORATOR` の場合のみ。
  PR 上のコメントとボットのイベントは無視する（無限ループ防止）。
- Issue 本文は `env:` 経由で受け渡し、`run:` に `${{ }}` で直接埋め込まない。
- `--yes-always` と組み合わせて危険なため、Aider のシェルコマンド提案と URL 自動取得は無効化している。
- `.aider*`（自動生成した `.aiderignore` を含む）と `.github/workflows/` はコミットしない
  （`GITHUB_TOKEN` ではワークフローファイルを push できない）。
- `GITHUB_TOKEN` で作成した PR では CI が自動起動しない（GitHub の仕様）。PR を Close → Reopen して起動する。
- 呼び出し側にワークフロー単位の `concurrency` を置かない（例外）。`/ai` 以外のコメントで起動しスキップされる
  実行が、待機中の正規の実行を置き換えてキャンセルしてしまうため。多重実行防止は共通ワークフロー側の
  `prepare` ジョブ（Issue 単位・`cancel-in-progress: false`・`queue: max`）で行う。`queue: max` により、
  同一 Issue への連続したリクエストもキャンセルされず順番に準備される。作業ブランチは実行ごとに別名のため、
  後続のジョブは直列化しない。
- コメント起動時はコメントの指示を先頭に置き、`max_prompt_chars` を超える場合は背景情報の Issue 本文側を切り詰める。

### 15.5 PR の CI 修正とバージョン更新（`/ai-fix` / `/ai-bump`）

- 共通ワークフロー: `gemini-ai-pr-fix-template.yml`。ジョブごとに実行境界を分ける

  | ジョブ | GitHub トークン | Gemini キー | PR のコード実行 | 内容 |
  | :--- | :--- | :--- | :--- | :--- |
  | `acknowledge` | issues / PR 書込 | なし | しない | 受付通知 |
  | `prepare` | 読み取りのみ | なし | しない | PR 情報・CI ログの収集、指示文の作成（このジョブだけを PR 単位で `queue: max` の直列化） |
  | `ai-1`〜`ai-3` | なし | あり | しない | Aider で修正（テストなし、リポジトリの `.env` / `.aider*` 設定は退避） |
  | `verify-1`〜`verify-3` | なし | なし | する | `npm ci` と Lint → テスト → ビルド |
  | `bump` | なし | なし | する | `update-version` によるバージョン更新 |
  | `publish` | 書き込み | なし | しない | 結果を検証し、patch を適用して push・報告 |

  - `ai-N` と `verify-N` を交互に行い、検証が失敗したらそのログを次の回の AI に渡す（最大 `max_fix_rounds` 回、上限 3）
  - ジョブ間は artifact（指示文・累積の patch・検証ログ）で受け渡す
  - 同一 PR への依頼で順番待ちするのは `prepare` だけで、前の処理の完了は待たない（Issue 用エージェントは
    ジョブ全体を Issue 単位で直列化する点が異なる）。並行した場合、後から終わった `publish` は head の照合で
    push を中止する。処理全体の直列化はしない
  - コマンドの境界（`/ai-fixx`・`/ai-bump major` 等を除外）は `.github/actions/gemini-ai-command/command_lib.sh`
    の 1 か所で定義し、`acknowledge` の最初のステップ・`resolve_request.sh`・`post_help.sh` が共通で使う。
    ワークフローの `if`（`startsWith`）は粗い絞り込みにとどめる
- 作業系 composite action: `.github/actions/gemini-ai-pr-fix`（`stage: prepare / ai / verify / bump`）
  - `resolve_request.sh` — コマンド解析と PR の検証（Open・同一リポジトリ・チェックアウト後の更新なし）
  - `collect_ci_failures.sh` — head コミットで失敗した CI（ワークフローごとの最新実行）のログ末尾を集め、
    ログに出てくる追跡済みファイルを対象ファイルにして指示文を組み立てる
  - `build_round_prompt.sh` — 2 回目以降は前回の検証ログと、前回までに変更したファイルを指示文・対象ファイルに加える
  - `run_verify.sh` — 依存関係のインストール（`npm ci` 等）と検証コマンドを実行し、結果（passed / failed）とログ末尾を
    出力（インストールの失敗も検証の失敗として扱い、ジョブの失敗にはしない）
  - `bump_version.sh` — ベースブランチのバージョンを基準に `npm run update-version -- <X.Y.Z>` を実行し、
    CHANGELOG のプレースホルダーを PR タイトルから作った説明に置き換えて検証（`check-version.js --check-bump`、
    無ければ `check_version.py`）。update-version の実体は VS Code テンプレートの `scripts/update-version.js`、
    Chrome テンプレートの `scripts/update_version.py`。プロジェクト種別が違っても呼び出し方は共通にする
- 公開用 composite action: `.github/actions/gemini-ai-pr-publish`
  - `select_result.sh` — 変更を作った最後の回の累積 patch とその回の検証結果（`/ai-bump` は bump の patch）を選ぶ
  - `apply_patch.sh` — 作業系ジョブの出力を検証し、patch を `git -c core.hooksPath=/dev/null am` で適用。
    `.github/workflows/` の変更を含む patch は拒否
  - `post_guidance.sh`（`gemini-ai-pr-fix` 内）— バージョンチェックの失敗・失敗なしの場合に案内をコメント
  - `push_and_report.sh`（`gemini-ai-pr-fix` 内）— PR が Open で head（SHA・ブランチ・リポジトリ）が不変であることを
    API で確認して push し、完了済みの全ワークフローを `workflow_dispatch` で再実行して PR にコメント。
    `workflow_dispatch` の実行は PR の「Checks」欄に表示されず、必須ステータスチェックも満たさない（GitHub の仕様）。
    PR のチェックとして結果を出すには PR を Close → Reopen する（GITHUB_TOKEN 以外の資格情報での push は、
    必須チェックを導入するまで見送り）
- 呼び出し側は `ai-coder-trigger.yml` の `ai-pr-fix` ジョブ（`actions: write` が必要）
- 運用ルール:
  - 人が作った PR も対象とする（フォークの PR は対象外）
  - バージョンチェックの失敗は AI に直させない。人が AGENTS.md の基準で種別を判断し `/ai-bump patch|minor` で依頼する
  - 修正の検証は CI と同じ順（Lint → テスト → ビルド）で行い、テスト・Lint ルールを弱めて通すことは禁止
  - lockfile が無いリポジトリでは `npm install --no-package-lock` を使い、`package-lock.json` を作らない
- セキュリティ:
  - PR のコード（依存パッケージの npm ci ライフサイクルスクリプト・テスト・update-version）は、`GITHUB_ENV` /
    `GITHUB_PATH`（`BASH_ENV` 等）・`.git/config`（`core.fsmonitor` 等）・同じジョブのプロセスのメモリ
    （ホストランナーは sudo 可）を通じて同じジョブの後続ステップに影響し得る。そのため GitHub の書き込みトークンと
    Gemini API キーは、PR のコードを実行しない別ジョブ（別ランナー）にだけ渡す
  - Aider は git ルートの `.aider.conf.yml` / `.env` / `.aider.model.settings.yml` / `.aider.model.metadata.json` を
    自動で読み込む（`.env` は `--env-file` を指定しても読み込まれる）。PR に置くだけで API の送信先等を変えられるため、
    `run_aider.sh` は実行中これらを退避し、空の `--config` / `--env-file` を指定する（Issue 用エージェントも同様）
  - PR のコードを実行するジョブ（`verify` / `bump`）では npm キャッシュを使わない。`issue_comment` で起動した
    ワークフローのキャッシュは既定ブランチのスコープに保存され、リリース等の他のワークフローからも復元されるため、
    細工された依存パッケージが混入し得る
  - 公開ジョブは作業系ジョブの出力（修正回数・検証結果・バージョン等）と patch を検証してから使う。
    その代わり、作業中は状況コメントを更新できない（受付ジョブが「作業ジョブで処理中」と表示する）
  - Issue 用エージェント（`gemini-ai-agent-template.yml`）も同じジョブ分離を適用している（15.1）。
    `ai` / `verify` ステージと、作業結果の選択・検証（`select_result.sh` / `apply_patch.sh`）を共用する

### 15.6 ヘルプコマンド（`/ai-help`）

- 共通ワークフロー: `gemini-ai-help-template.yml`（`issues` / `pull-requests: write`。リポジトリのコードはチェックアウトも実行もしない）
- 共通 composite action: `.github/actions/gemini-ai-help`（`post_help.sh` がヘルプ本文を組み立ててコメント）
- 呼び出し側は `ai-coder-trigger.yml` の `ai-help` ジョブ。`/ai-` で始まるコメントすべてで起動し、
  `post_help.sh` が共通の定義（`gemini-ai-command/command_lib.sh`）で判定する
  - PR での有効な `/ai-fix`・`/ai-bump patch|minor`: 修正ワークフローが処理するため何もしない
  - `/ai-help`: ヘルプを表示（Issue / PR に応じて表示順を変える）
  - Issue での `/ai-fix`・`/ai-bump`: PR でのみ使えることを案内
  - PR での種別なし・不正な `/ai-bump`: `patch` / `minor` の指定を案内
  - そのほかの `/ai-xxx`（`/ai-fixx` 等）: 解釈できなかったことを伝えてヘルプを表示（コマンド名は安全な文字だけ・30 文字までに切り詰めて表示）
- Issue 用エージェントは `/ai-` で始まるコメントでは起動しない（`/ai` と `/ai-xxx` の衝突防止。呼び出し側と共通ワークフローの両方で除外）
- Issue 用エージェントのコメント起動は、`/ai` の直後が空白・改行・終端の場合に限る（`/aider`・`/aihelp` 等は対象外）。
  呼び出し側の `startsWith` は粗い絞り込みのままとし、共通ワークフローの `acknowledge` ジョブの条件で判定する
- コマンドや運用ルールを追加・変更したら、`post_help.sh` のヘルプ本文と導入ガイドも更新する
