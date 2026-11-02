# Gemini AI エージェント導入ガイド（Web 画面編） (Gemini AI Agent Setup Guide)

GitHub の Issue に作業内容を書くだけで、AI（Aider + Gemini API 無料枠）がコードを修正し、
Pull Request を作成する仕組みを、自分のリポジトリに導入するための手順書です。
**すべての操作をブラウザ（GitHub / Google AI Studio の Web 画面）で完結**できます。

> 画面上のボタン名は 2026 年時点の GitHub / Google AI Studio の英語 UI 表記です。
> UI 変更で名称が変わることがあります。

---

## 目次

1. [仕組みの概要](#1-仕組みの概要)
2. [事前準備: Gemini API キーの発行](#2-事前準備-gemini-api-キーの発行)
3. [リポジトリの設定（4 ステップ）](#3-リポジトリの設定4-ステップ)
4. [使い方](#4-使い方)
5. [動作確認](#5-動作確認)
6. [カスタマイズ](#6-カスタマイズ)
7. [注意事項](#7-注意事項)
8. [トラブルシューティング](#8-トラブルシューティング)

---

## 1. 仕組みの概要

```text
Issue に ai-task ラベル付与 / "/ai ..." とコメント
        │
        ▼
ai-coder-trigger.yml（あなたのリポジトリ）
        │  uses: …/gemini-ai-agent-template.yml@v1
        ▼
共通ワークフロー（common-workflows）
  1. Issue の内容から指示文と対象ファイルを抽出
  2. Aider + Gemini でコードを修正
     （429 レートリミット時は 30s → 60s → 120s 待って自動リトライ。1 日の上限に達した場合は待たずに中止）
  3. 別のジョブで依存関係をインストールし、Lint → テスト → ビルドで検証
     → 失敗したら検証ログを AI に渡して再修正（2・3 の往復は最大 3 回）
  4. 変更があれば PR を作成し（最後の検証が失敗なら Draft）、Issue にリンクをコメント
```

> 安全のため、API キーを使う AI の修正（2）、リポジトリのコードを実行する検証（3）、
> 書き込み権限を使う PR の作成（4）は、それぞれ別のジョブ（別のランナー）で行います。
> PR 上の `/ai-fix` と同じ構成です。

| 用意するもの | 用途 |
| :--- | :--- |
| Google アカウント | Gemini API キーの発行（無料枠はクレジットカード登録不要） |
| GitHub リポジトリの管理者権限 | Secrets・Actions 設定の変更 |

---

## 2. 事前準備: Gemini API キーの発行

1. ブラウザで [Google AI Studio の API キー画面](https://aistudio.google.com/apikey) を開き、Google アカウントでログインします。
2. 初回は利用規約への同意画面が表示されるので、内容を確認して同意します。
3. **「Create API key」** をクリックします。
4. Google Cloud プロジェクトの選択を求められた場合は、既存のプロジェクトを選ぶか、新規作成します。
5. 表示された API キー（`AIza` で始まる文字列）の **コピーボタン** をクリックしてコピーします。

> ⚠️ API キーはパスワードと同じです。チャット・Issue・コミットなどに貼り付けないでください。
> 漏えいした場合は、同じ画面でキーを削除して再発行してください。

> ℹ️ **無料枠のデータ取り扱い**: Gemini API の無料枠では、送信した内容（コードを含む）が
> Google のサービス改善に利用される場合があります。非公開コードを扱う場合は、
> [Gemini API 利用規約](https://ai.google.dev/gemini-api/terms) を確認したうえで利用してください。

> ℹ️ **無料枠の上限**: 1 分あたり・1 日あたりのリクエスト数に上限があります。
> 現在の上限は [Rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) で確認できます。

### 使用するモデルが自分のキーで使えるか確認する（推奨）

既定のモデルは `gemini-3.5-flash-lite`（無料枠対象の Flash-Lite モデル）です。Flash 系より能力は控えめですが、
無料枠の 1 日あたりのリクエスト数の上限が大きく（2026 年 11 月時点で Flash 系の 20 回に対し 500 回）、
1 回の作業で何度も API を呼ぶ AI エージェントでもレートリミットに達しにくいため、既定にしています。
モデルによっては新規ユーザーへの提供が制限されることがあるため（例: `gemini-2.5-flash` 系は過去の利用者に限定）、導入前に確認しておくと安心です。

1. [Google AI Studio](https://aistudio.google.com/) を開き、画面のモデル選択欄で **Gemini 3.5 Flash-Lite** を選びます。
2. 「こんにちは」など短い文を送信し、応答が返ることを確認します。
3. モデル選択欄に表示されない・エラーになる場合は、表示されているモデルの
   モデル ID（例: `gemini-3.1-flash-lite`）を控え、[カスタマイズ](#6-カスタマイズ) の `model_name` で指定します。

> ℹ️ 無料枠の上限は **Google Cloud プロジェクト単位** で、モデルごとに決まっています（API キーごとではありません）。
> 複数のリポジトリに同じキーを登録すると、上限を共有します。現在の上限と使用量は
> [AI Studio の Rate Limit 画面](https://aistudio.google.com/rate-limit) で確認できます。
> 難しい修正だけ能力の高いモデル（例: `gemini-3.8-flash`。1 日 20 回）を使いたい場合は、`model_name` で指定します。

---

## 3. リポジトリの設定（4 ステップ）

以下、`<owner>/<repo>` はあなたのリポジトリ（例: `masanori-satake/StructMap-Solo`）に読み替えてください。

### ステップ 1: シークレット `GEMINI_API_KEY` を登録する

1. `https://github.com/<owner>/<repo>` を開き、上部タブの **「Settings」** をクリックします。
2. 左メニュー「Security」欄の **「Secrets and variables」** → **「Actions」** をクリックします。
3. 「Secrets」タブで **「New repository secret」** をクリックします。
4. 次のとおり入力します。

   | 項目 | 入力値 |
   | :--- | :--- |
   | Name | `GEMINI_API_KEY`（大文字・完全一致） |
   | Secret | 手順 2 でコピーした API キー（前後に空白・改行を入れない） |

5. **「Add secret」** をクリックします。
6. 一覧に `GEMINI_API_KEY` が表示されれば完了です。
   登録後は値を表示できません。変更する場合は鉛筆アイコン（Update）から上書きします。

### ステップ 2: ラベル `ai-task` を作成する

1. 上部タブの **「Issues」** を開き、検索欄の右にある **「Labels」** をクリックします。
   （`https://github.com/<owner>/<repo>/labels` を直接開いても構いません）
2. 右上の **「New label」** をクリックします。
3. 次のとおり入力します。

   | 項目 | 入力値 |
   | :--- | :--- |
   | Label name | `ai-task`（完全一致で判定されます） |
   | Description | `Gemini AI エージェントに作業を依頼` |
   | Color | 任意（例: `#7057ff`） |

4. **「Create label」** をクリックします。

### ステップ 3: GitHub Actions に PR 作成を許可する

1. **「Settings」** → 左メニューの **「Actions」** → **「General」** をクリックします。
2. ページ上部の「Actions permissions」は、既存の CI が動いていれば **変更不要** です。
3. ページ下部の **「Workflow permissions」** までスクロールします。
   - 上のラジオボタン（「Read repository contents and packages permissions」/
     「Read and write permissions」）は **現在の選択のまま** で構いません。
     必要な権限は呼び出し側ワークフローで個別に付与しています。
   - **「Allow GitHub Actions to create and approve pull requests」にチェック** を入れます。
4. そのセクションの **「Save」** をクリックします。

> この設定が無効だと、AI が修正をブランチに push した後、PR 作成のところで 403 エラーになります。

### ステップ 4: 呼び出し側ワークフローを追加する

テンプレートディレクトリ（`templates/<種別>/`）をまるごとコピーして作成したリポジトリには、
`.github/workflows/ai-coder-trigger.yml` が既に含まれています。その場合は **このステップは不要** です。

既存リポジトリに追加する場合は、以下の手順で行います（`main` が保護されている前提で、PR 経由で追加します）。

1. 使用するテンプレートを開き、ファイル表示右上の **「Copy raw file」**（コピーアイコン）をクリックします。

   | プロジェクト種別 | テンプレート |
   | :--- | :--- |
   | VS Code 拡張機能 | [templates/vscode-extension/.github/workflows/ai-coder-trigger.yml](https://github.com/masanori-satake/common-workflows/blob/main/templates/vscode-extension/.github/workflows/ai-coder-trigger.yml) |
   | Chrome 拡張機能 | [templates/chrome-extension/.github/workflows/ai-coder-trigger.yml](https://github.com/masanori-satake/common-workflows/blob/main/templates/chrome-extension/.github/workflows/ai-coder-trigger.yml) |

2. あなたのリポジトリのトップページで **「Add file」** → **「Create new file」** をクリックします。
3. ファイル名欄に `.github/workflows/ai-coder-trigger.yml` と入力します（`/` を入力するとフォルダとして区切られます）。
4. 本文欄にコピーした内容を貼り付けます。
5. 右上の **「Commit changes...」** をクリックし、次のとおり入力します。

   | 項目 | 入力値 |
   | :--- | :--- |
   | Commit message | `chore: Gemini AI エージェント起動ワークフローを追加` |
   | 選択肢 | **「Create a new branch for this commit and start a pull request」** |
   | ブランチ名 | `chore/ai-coder-trigger` |

6. **「Propose changes」** → 次の画面で **「Create pull request」** をクリックします。
7. 既存の CI が通ることを確認し、**「Squash and merge」** でマージします。

> ⚠️ Issue / コメントをトリガーとするワークフローは、**既定ブランチ（main）にマージされるまで動きません**。
> PR を作っただけの状態では起動しないので、必ずマージしてください。

> ℹ️ `.github/` 配下のみの変更なので、AGENTS.md の規定によりバージョン更新は不要です。

### 設定完了チェックリスト

| 確認場所 | 期待される状態 |
| :--- | :--- |
| Settings → Secrets and variables → Actions | `GEMINI_API_KEY` が表示されている |
| Issues → Labels | `ai-task` が存在する |
| Settings → Actions → General | 「Allow GitHub Actions to create and approve pull requests」がオン |
| Code タブで `.github/workflows/` を開く | `main` に `ai-coder-trigger.yml` がある |

---

## 4. 使い方

### 方法 A: ラベルで依頼する（新しい作業向け）

1. **「Issues」** → **「New issue」** で Issue を作成します。
   - **タイトル** と **本文** がそのまま AI への指示になります。
2. 右サイドバーの **「Labels」** から `ai-task` を付与します。
   - Issue 作成時に付けても、作成後に付けても起動します。

### 方法 B: コメントで依頼する（追加の指示・やり直し向け）

既存の Issue に、`/ai` で始まるコメントを投稿します。`/ai` の直後は空白か改行にしてください
（`/aider` や `/aihelp` のように文字が続くコメントでは起動しません）。

```text
/ai エラーメッセージを日本語にしてください。
```

- コメントの指示に加え、Issue のタイトル・本文も背景情報として AI に渡されます。
- コメントで起動できるのは、リポジトリの **Owner / Member / Collaborator** だけです。
- Pull Request 上のコメントでは起動しません。

### 対象ファイルを指定する（推奨）

本文またはコメントに `Files:` 行を書くと、**そのファイルだけ** を AI に渡します。
AI が読む量が減るため、無料枠のトークン消費とレートリミットを大きく抑えられます。

```text
ツリー表示で空配列のノードが「[]」と表示されないので、表示されるようにしてください。

Files: src/core/renderers/TreeRenderer.ts, src/core/model/index.ts
```

- 複数ファイルはカンマ区切りで指定します。リポジトリルートからの相対パスで書きます。
- Git 管理されている既存ファイルのみ指定できます（新規ファイルは AI が必要に応じて作成します）。
- 日本語や空白を含むパス、`..` を含むパスは安全のため無視されます。
- 指定しない場合は、AI がリポジトリ全体の構造（リポジトリマップ）から対象を判断します。

### 方法 C: PR の CI の失敗を直してもらう（`/ai-fix`）

PR の CI（コード品質検証など）が失敗したとき、その PR に次のようにコメントします。
AI が失敗したステップのログを読んで原因を特定し、修正コミットを **PR ブランチに直接 push** します。

```text
/ai-fix
```

```text
/ai-fix テストの期待値ではなく実装側を直してください。
```

- 2 行目以降や `/ai-fix` の後ろに書いた文は、追加の指示として AI に渡されます。
- 人が作った PR にも、AI が作った PR にも使えます。フォークからの PR は対象外です。
- コメントで起動できるのは、リポジトリの **Owner / Member / Collaborator** だけです。
- 対象は PR の最新コミットで失敗している CI です。CI がまだ実行中なら、完了を待つよう案内します。
- AI の修正は、別のジョブで Lint → テスト → ビルドの順に検証します。検証が失敗したら、そのログを AI に渡して
  再修正します（AI と検証の往復は最大 3 回）。
- push 後、PR の CI（コード品質検証・セキュリティスキャンなど）を `workflow_dispatch` ですべて再実行します。
  再実行の結果は **「Actions」** タブ（PR ブランチの実行）で確認できます。
- ⚠️ GitHub の仕様により、`workflow_dispatch` で実行した CI は **PR の「Checks」欄に表示されず、必須ステータスチェックも満たしません**。
  PR の「Checks」欄に結果を出すには、PR を **Close → Reopen** してください。`code-quality.yml`・`security-scan.yml` などが
  `pull_request` イベントで実行されます。`workflow_dispatch` が無いワークフロー（`version-bump.yml`・`coverage.yml` など）も同じ方法で実行します。
  ただし、各ワークフローの `branches` / `paths` の条件に一致しない PR では、そのワークフローは実行されません
  （例: `projects/app/**` を変更していない PR では `version-bump.yml` は実行されない）。
- 安全のため、PR のコードを実行する検証と、API キーを使う AI の修正は別々のジョブで行い、どちらも書き込み権限を持ちません。
  push は、さらに別のジョブが作業結果を確認してから行います。そのため作業中は状況コメントを更新しません
  （「⚙️ 作業ジョブで処理中」のまま数分〜数十分続きます）。
- AI はテストや Lint ルールを弱めて通すことはしません。ネットワークエラーなどコード以外が原因の失敗では、
  変更せずに「変更はありませんでした」と報告します。
- `.github/workflows/` の誤りは修正できません（GitHub の制約で push できないため）。

### 方法 D: バージョンを更新してもらう（`/ai-bump`）

**バージョンチェックの失敗は AI には直させません。** 更新の種別（マイナー / パッチ）は人が判断するためです。
`/ai-fix` でバージョンチェックの失敗が見つかると、AI は修正せずに次の案内をコメントします。
AGENTS.md の基準で種別を決め、PR にコメントしてください。

| コメント | 更新内容 | 使う場面 |
| :--- | :--- | :--- |
| `/ai-bump minor` | X.Y.Z → X.(Y+1).0 | 新機能の追加、既存機能の拡張、仕様変更 |
| `/ai-bump patch` | X.Y.Z → X.Y.(Z+1) | 不具合修正、軽微な UI 調整、README などパッケージ同梱ドキュメントの更新 |

- 新しいバージョンは **ベースブランチ（main）のバージョン** を基準に決めます（何度実行しても二重に上がりません）。
- プロジェクトの `npm run update-version -- <X.Y.Z>` で関連ファイルを一括更新し、バージョンチェックが通ることを
  確認してから push します。AI は使いません。どの種別のプロジェクトでも、この呼び出し方は共通です。

  | プロジェクト種別 | update-version の実体（テンプレート） | 更新するファイルの例 | 検証 |
  | :--- | :--- | :--- | :--- |
  | VS Code 拡張機能 | `scripts/update-version.js` | package.json / package-lock.json / README.md / CHANGELOG.md | `check-version.js --check-bump` |
  | Chrome 拡張機能 | `scripts/update_version.py` | package.json / package-lock.json / `projects/app/manifest.json` / `projects/app/version.json` / README.md のバッジ | `check_version.py` |

  更新するファイルはプロジェクトごとにスクリプト内で設定します（例: PWA のキャッシュ名もある場合は追加）。
- CHANGELOG.md がある場合、説明は PR タイトルから作成します（`feat:` → 追加、`fix:` → 修正、それ以外 → 変更）。
  必要に応じて PR ブランチ上で書き直してください。
- バージョン更新の後もほかのチェックが失敗する場合は、改めて `/ai-fix` をコメントします。

### コマンドの一覧を見る（`/ai-help`）

Issue または PR に `/ai-help` とコメントすると、使えるコマンドと注意事項（状況表示の見方、無料枠の上限、
バージョン更新のルールなど）をボットがコメントで返します。

- Issue では Issue のコマンドを、PR では PR のコマンドを先に表示します。
- `/ai-` で始まる解釈できないコマンド（例: `/ai-fixx`、`/ai-bump major`）や、Issue での `/ai-fix`・`/ai-bump` にも、
  案内とヘルプを返します。解釈できないコマンドで AI の作業が始まることはありません。
- 呼び出し側の `ai-coder-trigger.yml` に `ai-help` ジョブが必要です（テンプレートの最新版に含まれています）。

### 良い指示の書き方

| ポイント | 例 |
| :--- | :--- |
| 何をどう変えるかを具体的に書く | 「`parseXml` が空要素で例外を投げるので、空オブジェクトを返すようにする」 |
| 完了条件を書く | 「既存テストがすべて通ること」 |
| 1 Issue 1 作業にする | 複数の修正は Issue を分ける |
| 対象ファイルを `Files:` で絞る | `Files: src/core/parsers/xml/XmlParser.ts` |

---

## 5. 動作確認

初回は、バージョン更新が不要なドキュメント（`docs/` 配下など）で試すのが安全です。

1. 次の内容で Issue を作成し、`ai-task` ラベルを付与します。

   ```text
   タイトル: ARCHITECTURE.md の冒頭を整える
   本文:
   docs/ARCHITECTURE.md の冒頭段落を、より簡潔な日本語に整えてください。

   Files: docs/ARCHITECTURE.md
   ```

2. **Issue 上で受付と進み具合を確認します。** 10〜30 秒ほどで次の表示が出ます。
   - 起動元（ラベル起動なら Issue 本文、コメント起動ならそのコメント）に 👀 リアクションが付きます。
   - 「🤖 Gemini AI エージェント」という **状況コメント** が 1 件投稿され、処理の段階に合わせて書き換わります。

     | 表示 | 意味 |
     | :--- | :--- |
     | 📥 受付しました | 受け付け済み |
     | ⚙️ 作業ジョブで処理中 | 指示内容の解析、AI による修正と検証（最大 3 回の再修正を含む）を行っています。同じ Issue で準備中の処理があれば、その完了を待ってから始めます。安全のため作業中は表示を更新しないので、**この表示のまま数分〜数十分続きます**（止まっているわけではありません。進み具合は実行ログで確認できます） |
     | 🔍 AI の作業が完了しました（修正 n 回・検証: …） | AI による修正の回数と、最後の検証（Lint → テスト → ビルド）の結果。完了後も経過欄に残ります |
     | 📤 PR を作成中 | ブランチへの push と PR 作成中 |
     | ✅ / ℹ️ / ❌ / ⏹️ | 完了（PR 作成）/ 完了（変更なし）/ 失敗 / 中断 |

   - 完了すると 👀 が 🚀（成功）または 😕（失敗・中断）に切り替わります。
   - 状況コメントの書き換えでは通知が届かないため、結果（PR 作成・変更なし・失敗）は別のコメントでも知らせます。
   - 状況コメントの「実行ログ」リンクから、**「Actions」** タブの実行画面を直接開けます。
   通常 3〜10 分程度で完了します（レートリミット時はリトライ待ちで延びます）。
3. 実行画面の **Summary** に以下が表示されます。
   - 🤖 AI への指示内容（対象ファイルの採否）
   - 🛠️ Aider 実行結果（回ごとの試行回数）と 🧪 検証結果
   - 作成された PR の URL
4. Issue に「🤖 Gemini AI エージェントが PR を作成しました」というコメントが付きます。
5. PR を開いて差分を確認します。
   - 最後の検証（Lint → テスト → ビルド）が失敗した場合は **Draft PR** として作成されます。
   - 再修正した場合は、修正の回ごとにコミットが分かれます。
   - AI とのやり取りの詳細は、実行画面下部 **「Artifacts」** の `aider-logs-*` をダウンロードすると確認できます（7 日間保存）。

### 作成された PR で CI を動かす

GitHub の仕様により、ワークフローが作成した PR では CI（Code Quality 等）が **自動起動しません**。
PR 画面の下部で **「Close pull request」** → **「Reopen pull request」** をクリックすると CI が起動します。

### 修正が不十分だった場合

- PR は閉じて、元の Issue に `/ai <追加の指示>` とコメントすると、新しい PR が作成されます。
- 人間が PR ブランチに直接コミットして仕上げても構いません。

---

## 6. カスタマイズ

`.github/workflows/ai-coder-trigger.yml` の `with:` で上書きできます。原則は既定値のままで構いません。

| 入力 | 既定値 | 説明 |
| :--- | :--- | :--- |
| `model_name` | `gemini-3.5-flash-lite` | 使用する Gemini モデル（無料枠の上限が大きい Flash-Lite を既定にしている） |
| `test_command` | `npm test` | 修正の検証で Lint とビルドの間に実行するテスト。空文字 `''` ではテストを実行しない。Lint・ビルドは、package.json があり `lint` / `build` スクリプトが定義されている場合にだけ実行する（`npm run --if-present`）。VS Code テンプレートは `xvfb-run --auto-servernum npm test` |
| `max_fix_rounds` | `3` | AI による修正と検証の最大往復回数（1〜3） |
| `target_branch` | リポジトリの既定ブランチ | 作業のベースブランチ |
| `max_retries` | `4` | 429 発生時の最大試行回数 |
| `initial_delay` | `30` | 初回リトライまでの待機秒数（以降 2 倍） |
| `allowed_associations` | `OWNER,MEMBER,COLLABORATOR` | コメント起動を許可する関係者（カンマ区切り・空白なし） |
| `timeout_minutes` | `30` | ジョブのタイムアウト（分） |

### AI に読ませないファイルを指定する（`.aiderignore`）

リポジトリルートに `.aiderignore` が無い場合、`node_modules/`・`dist/`・`out/`・ロックファイル・
`.env` などを除外する既定のファイルが実行時に自動生成されます（コミットはされません）。
独自に指定したい場合は、`.gitignore` と同じ書式で `.aiderignore` をリポジトリに追加してください。

---

## 7. 注意事項

- **必ず人間がレビューしてからマージしてください。** AI の変更は誤りを含むことがあります。
- **バージョン更新ルール**: VSIX / ZIP に含まれるファイル（`src/`、`README.md` など）を変更すると、
  AGENTS.md の規定によりバージョン更新が必要です。AI はこのルールを自動では適用しません。
  AI が作った PR の CI がバージョンチェックで失敗したら、種別を判断して PR に `/ai-bump patch` または
  `/ai-bump minor` とコメントしてください（[方法 D](#方法-d-バージョンを更新してもらうai-bump)）。

- **第三者の Issue にラベルを付ける前に本文を確認してください。** ラベルを付けた時点で、
  その本文を AI への指示として承認したことになります。
- **ワークフローファイルは変更されません。** `.github/workflows/` は AI の読込・コミット対象外です。
- AI はシェルコマンドの実行や URL の取得を行わない設定になっています。

---

## 8. トラブルシューティング

実行結果は **「Actions」** タブ → 該当の実行 → ジョブのログで確認できます。

| 症状 | 原因と対処 |
| :--- | :--- |
| Actions タブに実行が現れない | `ai-coder-trigger.yml` が main にマージされていない（[ステップ 4](#ステップ-4-呼び出し側ワークフローを追加する)） |
| 実行はあるがジョブが「Skipped」 | ラベル名が `ai-task` でない / コメントが `/ai`（PR では `/ai-fix`・`/ai-bump`）で始まっていない / 権限のないユーザーのコメント。ほかのジョブ（Issue 用と PR 用）のスキップは正常 |
| `GEMINI_API_KEY が未設定です` | [ステップ 1](#ステップ-1-シークレット-gemini_api_key-を登録する) の名前の誤り（大文字・完全一致） |
| `AuthenticationError` / `API key not valid` | API キーの誤り・削除済み。キーを再発行し、シークレットを Update で上書き |
| `NotFoundError` / `no longer available to new users` | `model_name` の誤り、またはそのモデルが新規ユーザーに提供されていない。[モデルの確認](#使用するモデルが自分のキーで使えるか確認する推奨) の手順で使えるモデルを選び、`model_name` で指定 |
| 「1 日あたりの上限に達したため、AI による修正を中止しました」とコメントされた | Gemini API 無料枠の 1 日あたりのリクエスト数の上限（全リポジトリで共有）に到達。再試行しても回復しないため、すぐに中止します。リセット（太平洋時間 0 時 = 日本時間 16〜17 時）後に `/ai`（PR では `/ai-fix`）で再実行 |
| PR 作成で 403 エラー | [ステップ 3](#ステップ-3-github-actions-に-pr-作成を許可する) のチェックが入っていない |
| PR が Draft で作成された | AI の最後の修正が検証（依存関係のインストール → Lint → テスト → ビルド）のいずれかで失敗。PR 本文と実行ログの「修正の検証」ジョブを確認 |
| 「変更はありませんでした」とコメントされた | 指示が曖昧、または対象ファイルが除外された。Summary の対象ファイル表と指示内容を見直す |
| PR で CI が動かない | GitHub の仕様。PR を Close → Reopen する |
| 失敗時に Issue へ ⚠️ コメントが付いた | コメント内の「実行ログ」リンクからエラー内容を確認 |
| 👀 も状況コメントも付かない | ジョブがスキップされている（上の「Skipped」の行を参照）。Actions タブで実行の有無を確認 |
| 状況コメントが「⚙️ 作業ジョブで処理中」のまま進まない | 作業中は表示を更新しない仕様（数分〜数十分かかる）。同じ Issue / PR で前の依頼の準備が終わっていない場合は、その完了も待つ。Actions タブで実行の進み具合を確認 |
| PR で「処理中に PR ブランチが更新されたため、push を中止しました」 | 同じ PR への依頼が並行して動き、先に終わった処理が push した。PR は準備だけを順番に行い、前の処理の完了は待たないため。前の結果を確認し、必要ならもう一度コメントする |
| `/ai-fix` / `/ai-bump` / `/ai-help` に反応しない | `ai-coder-trigger.yml` が古い（`ai-pr-fix` / `ai-help` ジョブが無い）。テンプレートの最新版に差し替える |
| Issue に `/ai-help` などとコメントしたら AI が作業を始めた | `ai-coder-trigger.yml` が古い（`/ai-` で始まるコメントを除外していない）。テンプレートの最新版に差し替える |
| 「フォークからの PR は対象外です」 | フォークの PR は安全のため対象外。PR の作成者に修正を依頼する |
| 「処理中に PR ブランチが更新されたため、push を中止しました」 | AI の作業中に誰かが PR に push した。もう一度コメントする |
| ファイル間のバージョンの不一致（`check_version.py` など）で CI が失敗し、`/ai-fix` では「変更はありませんでした」となる | AI はバージョンを書き換えないため、不一致は直しません（`/ai-bump` の案内に回るのは、バージョン更新忘れの検査（`Check Version Bump` 等）が失敗した場合です）。`/ai-bump patch` または `/ai-bump minor` をコメントすると、すべてのファイルのバージョンが新しい値に揃います |
| `/ai-bump` で「update-version スクリプトがありません」 | package.json の `scripts.update-version` と `scripts/update-version.js` の両方が無い。テンプレートのスクリプト（VS Code: `scripts/update-version.js`、Chrome: `scripts/update_version.py`）を導入し、`scripts.update-version` に登録する |
| push 後に CI が再実行されない（「再実行できませんでした」） | 対象ワークフローに `workflow_dispatch` が無い。追加するか、PR を Close → Reopen する |
| `/ai-fix` / `/ai-bump` の後、PR の「Checks」欄が古いまま・必須チェックが「Expected」のまま | GitHub の仕様。`workflow_dispatch` で再実行した CI は PR の「Checks」欄に表示されない（結果は Actions タブで確認できる）。PR を Close → Reopen すると、`pull_request` で起動する CI のうち `branches` / `paths` の条件に一致するものが実行され、「Checks」欄に表示される |

---

関連ドキュメント: [共通ワークフロー運用ガイドライン 15 章](./workflow-guidelines.md#15-gemini-ai-エージェント-gemini-ai-agent)
