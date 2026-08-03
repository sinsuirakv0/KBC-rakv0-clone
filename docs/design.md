# KBC cloneにゃんこ 設計メモ

## 入力

アプリ名の入力には、Termux端末の直接入力を使わない。`lib/app_name_dialog.py`が端末内の`127.0.0.1`で一時的な入力ページを起動し、`termux-open-url`で既定ブラウザを開く。ブラウザの通常の`input type=text`なら、Androidに設定済みの日本語キーボードをそのまま使用できる。

ページはランダムトークン付きのURLでのみ応答し、入力値は一時ディレクトリの結果ファイルへ一度だけ保存する。結果をTermuxへ渡した直後に一時ディレクトリを削除する。外部サーバーへアプリ名を送信しない。

## パッケージ名とBCSFE

新規クローンのパッケージ名は`jp.co.ponos.battlecats.kbc.<識別子>`に固定する。識別子は`kbc_validate_package_suffix`で検証するため、生成される名前はAndroidのパッケージ名形式を満たす。

BCSFEのroot storage読み込みは名前の接頭辞を判定せず、`/data/data/<パッケージ名>/files/SAVE_DATA`が存在するアプリを列挙する。従って、クローンを一度起動して`SAVE_DATA`を作成すれば、このツールの生成名は検出対象になる。旧形式の登録済みクローンは更新互換性のため維持する。

参照実装:

- `https://github.com/fieryhenry/BCSFE-Python/blob/main/src/bcsfe/core/io/root_handler.py`
- `https://github.com/fieryhenry/BCSFE-Python/blob/main/src/bcsfe/core/io/adb_handler.py`

## 本家最新版XAPK

`d`選択はAPKComboのダウンロード画面をブラウザで開く。配布ページがブラウザ上の検証を要求する場合があるため、ツールはその検証を迂回しない。ユーザーが正規の画面でXAPKの取得を完了した後、Download配下へ新しく追加された`.xapk`を検出して選択する。

生成前にXAPKの`manifest.json`から本家パッケージ名と版番号を検査する。元のパッケージが`jp.co.ponos.battlecats`でない場合は処理を中止する。
