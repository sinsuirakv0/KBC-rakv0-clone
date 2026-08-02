# 検証結果

## 環境

- 端末: Pixel 8
- Android ABI: `arm64-v8a`
- Termux: 0.118.3
- 入力: JP版v15.5.1、versionCode 1505010、`arm64-v8a` XAPK
- APKEditor: 1.4.9

## 確認済み

- `install.sh`による依存関係導入
- APKEditorのSHA-256検証
- `kbc-clone doctor`
- 既存クローンの台帳登録
- 対話メニュー表示
- XAPKの統合、Manifest変更、再構築
- 指定PNGによる通常・アダプティブアイコン前景の差替え
- 同一XAPKの展開済みキャッシュ再利用
- ハードリンク作業領域からのAPK再構築
- 作業後に元キャッシュのSHA-256が変化しないこと
- 更新用VERSIONの取得と比較
- 更新tar.gzのパス・必須ファイル・VERSION検証
- 更新一時ディレクトリの安全な削除
- v2/v3署名
- 旧試作版からの署名鍵移行
- 同じパッケージ・同じ署名による上書きインストール
- 明示Activityによるクローン起動

公開版で再生成したAPKは、既にインストール済みの試作版と次の証明書SHA-256が一致した。

```text
6F5B145D919FD6105FA66DE38A55B21F5DCA627271D9DC43BB2EDAAF08B1F032
```

同一入力、同一設定、同一署名鍵で生成したAPKのSHA-256も一致した。

```text
8F46AE9FCD4D9317CDADD708C6ACCA5252953D85BC6F27243A78CF6E6515534A
```

v0.2では指定PNGを`icon.png`と`icon_foreground.png`へ反映し、APKEditor 1.4.9で再構築できることを確認した。差替え後の両リソースと入力PNGのSHA-256が一致した。

開発PC上のv15.5.1 XAPKでは、統合・展開を含む初回テンプレート準備が17秒、同じXAPKのキャッシュ読込みと作業領域作成が1秒だった。APK再構築と署名の時間は別途必要になる。

## Androidの制約

Termuxから`pm list packages`、`pm path`を実行すると、Android 15では次のBinder呼出エラーになる。

```text
cmd: Failure calling service package: Failed transaction
```

このため、v0.1では正確なインストール一覧を取得せず、ツール台帳と明示Activity、Android標準管理画面を使用する。
