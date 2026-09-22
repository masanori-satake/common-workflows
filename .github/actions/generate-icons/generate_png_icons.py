#!/usr/bin/env python3
"""SVG から各サイズの PNG アイコンを生成する共通スクリプト.

common-workflows の generate-icons composite action から呼び出される。
各プロジェクトが個別に同等スクリプトを持たなくて済むよう、入力はすべて
コマンドライン引数（環境変数）でパラメータ化している。

引数（すべて任意。環境変数でも指定可）:
  --svg         入力 SVG パス            (env: ICON_SVG_PATH,    既定: projects/app/assets/icon.svg)
  --out         出力ディレクトリ          (env: ICON_OUTPUT_DIR,  既定: projects/app/icons)
  --prefix      出力ファイル名の接頭辞    (env: ICON_FILE_PREFIX, 既定: icon)
  --sizes       生成サイズ(カンマ区切り)  (env: ICON_SIZES,       既定: 16,32,48,128)
  --bg-color    背景色の置換先(任意)      (env: ICON_BG_COLOR,    既定: なし)
  --bg-source   置換元の色(bg-color時)    (env: ICON_BG_SOURCE,   既定: #386a20)

背景色の置換は、SVG 内の `--bg-source` の色を `--bg-color` に置き換える
（ブランド色違いのアイコンを生成する用途）。`--bg-color` 未指定時は置換しない。
"""

import argparse
import os
import sys


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SVG から PNG アイコンを生成する")
    parser.add_argument("--svg", default=os.environ.get("ICON_SVG_PATH", "projects/app/assets/icon.svg"))
    parser.add_argument("--out", default=os.environ.get("ICON_OUTPUT_DIR", "projects/app/icons"))
    parser.add_argument("--prefix", default=os.environ.get("ICON_FILE_PREFIX", "icon"))
    parser.add_argument("--sizes", default=os.environ.get("ICON_SIZES", "16,32,48,128"))
    parser.add_argument("--bg-color", default=os.environ.get("ICON_BG_COLOR", "") or None)
    parser.add_argument("--bg-source", default=os.environ.get("ICON_BG_SOURCE", "#386a20"))
    return parser.parse_args()


def generate_icons(svg_path: str, output_dir: str, prefix: str, sizes: list[int],
                   bg_color: str | None, bg_source: str) -> bool:
    if not os.path.exists(svg_path):
        print(f"Error: SVG が見つかりません: {svg_path}", file=sys.stderr)
        return False

    with open(svg_path, "r", encoding="utf-8") as f:
        svg_content = f.read()

    if bg_color:
        # ブランド色を差し替える（例: 緑 #386a20 → 指定色）
        svg_content = svg_content.replace(bg_source, bg_color)

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print(
            "Error: playwright が見つかりません。'pip install playwright' と "
            "'python -m playwright install chromium' を実行してください。",
            file=sys.stderr,
        )
        return False

    os.makedirs(output_dir, exist_ok=True)

    html = (
        "<!DOCTYPE html><html><head><style>"
        "html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; }"
        "svg { width: 100%; height: 100%; display: block; }"
        f"</style></head><body>{svg_content}</body></html>"
    )

    with sync_playwright() as p:
        try:
            browser = p.chromium.launch()
        except Exception as e:  # noqa: BLE001 - CI ログに原因を残す
            print(f"Error: Chromium の起動に失敗しました: {e}", file=sys.stderr)
            print("'python -m playwright install chromium' を事前に実行してください。", file=sys.stderr)
            return False

        with browser:
            page = browser.new_page(viewport={"width": 512, "height": 512})
            page.set_content(html)

            for size in sizes:
                out = os.path.join(output_dir, f"{prefix}{size}.png")
                page.set_viewport_size({"width": size, "height": size})
                page.wait_for_timeout(100)  # レンダリング待ち
                page.screenshot(path=out, omit_background=True)
                print(f"Generated {out}")

    return True


def main() -> int:
    args = parse_args()
    try:
        sizes = [int(s.strip()) for s in args.sizes.split(",") if s.strip()]
    except ValueError:
        print(f"Error: --sizes の指定が不正です: {args.sizes}", file=sys.stderr)
        return 1

    ok = generate_icons(
        svg_path=args.svg,
        output_dir=args.out,
        prefix=args.prefix,
        sizes=sizes,
        bg_color=args.bg_color,
        bg_source=args.bg_source,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
