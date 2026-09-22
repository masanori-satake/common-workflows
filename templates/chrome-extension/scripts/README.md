# scripts/ テンプレート解説

このディレクトリは Chrome 拡張機能プロジェクトの立ち上がりを助けるための
**スクリプトのテンプレート集** です。新規プロジェクトは `templates/chrome-extension`
をコピーし、以下のスクリプトを自プロジェクトの構成に合わせて最小限だけ編集して使います。

共通ワークフロー（`common-workflows` の `base-*.yml@v1`）は、これらのスクリプトの
うち **命名規約に沿うもの** を自動的に利用します。プロジェクト固有のロジックは
各スクリプト内の「★ プロジェクトごとに編集する箇所 ★」に閉じ込めてください。

## 各スクリプトの役割

| スクリプト | 役割 | 共通ワークフローとの連携 |
| :--- | :--- | :--- |
| `ci_checks.py` | CI ポリシーチェックの**単一エントリ** | `base-ci.yml` が存在すれば自動実行 |
| `check_version.py` | 複数ファイルのバージョン整合性検査 | `ci_checks.py` から呼ぶ |
| `create_package.py` | `projects/app` を ZIP 化し `releases/` に出力 | `npm run build` から呼び、`base-release.yml` が `releases/*.zip` を添付 |

> アイコン生成（SVG→PNG）は**プロジェクト側スクリプト不要**です。`base-release.yml`
> の `generate_icons: true` で共通の composite action（`generate-icons`）が実行します。

## 拡張の指針

### ci_checks.py
`CHECKS` のリストに `(ラベル, コマンド配列)` を足すだけで検査を追加できます。
ルート整合性チェックやポリシーガードなど、プロジェクト固有の検査をここへ集約すると、
呼び出し側ワークフローに `with:` を書かずに済みます。

### check_version.py
`VERSION_SOURCES` にバージョン表記を持つファイルを列挙します。
- JSON の `"version"` → `json_version()`
- README バッジ等のテキスト → `regex_version(r"...")`
- `required=True` を付けたソースが1つでもあれば、それが基準になります。

### create_package.py
`SOURCE_DIR` / `VERSION_FILE` / `EXCLUDE_*` / `RENAME_MAP` を編集します。
`manifest.chrome.json → manifest.json` のようなリネームは `RENAME_MAP` で行います。

## npm scripts との対応（package.json）

```jsonc
{
  "scripts": {
    // ブラウザ不要のユニットテスト等
    "test": "node scripts/test_utils.js && python3 scripts/check_version.py",
    // build は releases/*.zip を生成する。アイコンを共通 action で作る場合は
    // ここに generate_png_icons.py を入れない（base-release の generate_icons を使う）。
    "build": "python3 scripts/check_version.py && python3 scripts/create_package.py"
  }
}
```

## 依存関係

- これらのスクリプトは Python 3.12 標準ライブラリのみで動作します（外部依存なし）。
- アイコン生成に Playwright が必要ですが、それは共通 action 側が導入するため、
  プロジェクトの `requirements.txt` には原則不要です。
