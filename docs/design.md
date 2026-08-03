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

## 本家XAPK

本家XAPKは利用者が配布元から手動で取得し、Downloadへ保存する。選択画面の`c`はAPKCombo、`p`はAPKPureの取得画面を開き、取得元ごとの案内を表示する。配布元が要求するログイン、規約同意、検証などをツールが自動化・回避しない。

ダウンロード後にTermuxへ戻ると、選択前後のDownload内`.xapk`一覧を比較して、今回追加されたファイルを自動選択する。新規ファイルを検出できなかった場合は、更新日時順の一覧から手動で選ぶ。選択画面では`manifest.json`から読み取った版番号を併記し、Download以外のローカル保存場所も指定できる。

生成前にXAPKの`manifest.json`から本家パッケージ名と版番号を検査する。元のパッケージが`jp.co.ponos.battlecats`でない場合は処理を中止する。
