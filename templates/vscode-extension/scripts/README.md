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
| `check-readme-anchors.js` | README.md の `##` / `###` 見出しへの ASCII ID（`<a id="...">`）付け忘れ、ページ内リンク先の不一致、ID の重複を検査 | `package.json` の `lint` から `npm run check-readme-anchors` で呼ぶ（`base-ci-vscode.yml` の Lint ステップで実行される） |
| `run-pre-commit-check.sh` | pre-commit フック用エントリ（`check-version.js --check-bump` と `check-readme-anchors.js` を呼ぶ） | `.pre-commit-config.yaml` の local hook から呼ぶ |

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

### check-readme-anchors.js
両 VSCode リポジトリで完全一致の実装であり、編集不要です。

VS Code の拡張機能詳細ページでは、絵文字や日本語を含む見出しから自動生成される ID や
`<a name="...">` ではページ内ジャンプが機能しない場合があります。そのため README.md では
見出しの直前に ASCII の `<a id="..."></a>` を置き、目次などのリンクはその ID を参照する
規約とし、本スクリプトで検査します。`scripts.lint` を実装に合わせて書き換える際は、
末尾の `&& npm run check-readme-anchors` を残してください。

```markdown
<a id="en-key-features"></a>
### 💡 Key Features
```

### run-pre-commit-check.sh / .pre-commit-config.yaml
両 VSCode リポジトリで完全一致の実装であり、編集不要です。
