# 技術スタック

## ランタイム・言語

- **Node.js**: `lts/*`（デフォルト。`node_version` インプットで上書き可能）
- **TypeScript**: strict モード（`"strict": true`）、ターゲット ES2022、ESNext モジュール
- **パッケージマネージャー**: npm（インストールは `npm ci` を使用）

## TypeScript 設定（テンプレート基準）

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "noEmit": true,
    "isolatedModules": true
  }
}
```

## 依存関係の方針

外部ライブラリへの依存を最小限に抑える。可能な限り Vanilla JS/TS の標準機能を活用する。依存関係の増加はセキュリティリスクとメンテナンスコストの増大につながる。

## CI/CD プラットフォーム

GitHub Actions — 再利用可能ワークフロー（`workflow_call`）。3つの基盤ワークフローを提供：

| ファイル | 役割 |
| :--- | :--- |
| `base-ci.yml` | 型チェック・Lint・テスト・ビルド |
| `base-release.yml` | バージョン抽出・ZIP パッケージング・GitHub Release 作成 |
| `base-security.yml` | `npm audit --audit-level=high` による脆弱性スキャン |

## npm スクリプト（全プロジェクト共通）

| スクリプト | 内容 |
| :--- | :--- |
| `typecheck` | `tsc --noEmit` |
| `lint` | 静的解析（任意のリンター） |
| `test` | テスト実行 |
| `build` | プロダクションビルド |

CI では `--if-present` フラグ付きで呼び出すため、未定義のスクリプトがあってもエラーにならない。

## エディタ設定

- インデント: スペース 2 つ
- 改行コード: LF
- 文字コード: UTF-8
- 行末スペース除去・ファイル末尾改行を挿入

## バージョニング

セマンティックバージョニング `vX.Y.Z` を厳守。リリース時のバージョンは `manifest.json`（優先）または `package.json` から自動抽出する。
