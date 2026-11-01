# scripts/ テンプレート解説

このディレクトリは VSCode 拡張機能プロジェクトの立ち上がりを助けるための
**版管理スクリプトのテンプレート集** です。新規プロジェクトは `templates/vscode-extension`
をコピーし、以下のスクリプトを自プロジェクトに配置して使います。

共通ワークフロー（`common-workflows` の `base-ci-vscode.yml@v1`）は `check-version.js` を
CI 上で実行します。また pre-commit フックがローカルで同じスクリプトを呼び出します。
プロジェクト固有の編集は各スクリプト内の「★ プロジェクトごとに編集する箇所 ★」に
閉じ込めてください。

## 各スクリプトの役割

| スクリプト | 役割 | 共通ワークフローとの連携 |
| :--- | :--- | :--- |
| `check-version.js` | 複数ファイルの版整合性検査 ＋ VSIX 関連性フィルタ付き版バンプ検査 | `base-ci-vscode.yml` が `node scripts/check-version.js --check-bump` を実行 |
| `update-version.js` | package.json / package-lock.json / README.md / CHANGELOG.md の版を一括更新し、最後に `check-version.js` で検証 | ローカル `npm run update-version` から呼ぶ（ワークフロー未使用） |
| `run-pre-commit-check.sh` | pre-commit フック用エントリ（`check-version.js --check-bump` を呼ぶ） | `.pre-commit-config.yaml` の local hook から呼ぶ |

## 編集箇所

### check-version.js
両 VSCode リポジトリでバイト完全一致の実装であり、VSCode 標準レイアウト
（ルート `package.json` / `package-lock.json` / `CHANGELOG.md` / `README.md`）に
依存します。原則として編集不要です。

`isVsixRelevant()` の `ignoredPrefixes` / `ignoredFiles` は、VSIX パッケージ外の
ファイル（`.vscode/` / `.github/` / `docs/` / `scripts/` 等）を版バンプ要求の
対象から除外するフィルタです。プロジェクト固有のパッケージ外ファイルを追加する
場合はこのリストに追記してください。

### update-version.js
**★ プロジェクトごとに編集する箇所 ★**

README.md 内の VSIX ファイル名正規表現をプロジェクト固有の値に置き換える必要が
あります。既定値はプレースホルダ `<package-name>` となっており、そのままでは
README 内の VSIX ファイル名を更新できません。

```js
// 編集前（テンプレート）:
readme = readme.replace(new RegExp(`<package-name>-${oldVersion.replace(/\./g, '\\.')}\\.vsix`, 'g'), `<package-name>-${cleanVersion}.vsix`);

// 編集後（例: meetdock-solo の場合）:
readme = readme.replace(new RegExp(`meetdock-solo-${oldVersion.replace(/\./g, '\\.')}\\.vsix`, 'g'), `meetdock-solo-${cleanVersion}.vsix`);
```

`<package-name>` は package.json の `"name"` フィールド等、VSIX ファイル名の
プレフィックスに置き換えてください。

### run-pre-commit-check.sh / .pre-commit-config.yaml
両 VSCode リポジトリで完全一致の実装であり、編集不要です。
