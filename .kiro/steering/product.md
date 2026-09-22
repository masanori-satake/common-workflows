# プロダクト概要

`common-workflows` は masanori-satake が管理する、GitHub Actions の再利用可能ワークフロー共通リポジトリです。TypeScript ベースのブラウザ・エディタ拡張機能エコシステム（Chrome 拡張機能、VS Code 拡張機能、Obsidian プラグイン）全体の CI/CD 基盤を一元管理します。

## 目的

- 各プロジェクトリポジトリから呼び出される再利用可能ワークフロー（`workflow_call`）を提供する
- エコシステム全体に一貫した品質ゲート・セキュリティスキャン・リリースパッケージングを適用する
- 新規プロジェクトがテンプレートをコピーするだけで標準準拠の CI/CD を即座に利用できるようにする

## 利用方法

個別プロジェクトのリポジトリから以下の形式で呼び出します：

```yaml
uses: masanori-satake/common-workflows/.github/workflows/base-ci.yml@v1
```

対応プロジェクト種別：Chrome 拡張機能（Manifest V3）、VS Code 拡張機能、Obsidian プラグイン

## 命名・言語規約

ワークフローの `name:` フィールドおよび各ステップの `- name:` ラベルは、GitHub UI 上で直感的に理解できるよう **`'日本語 (English)'`** の二言語併記形式を使用します。この規約は本リポジトリの基盤ワークフローおよび各プロジェクトの呼び出しワークフロー双方に適用します。
