# アーキテクチャ

## 目的

TermuxだけでクローンAPKを作成し、同一の署名鍵を維持しながら複数クローンと更新履歴を管理する。

## 構成

```text
bin/kbc-clone
  ├─ lib/core.sh       共通設定、表示、入力検証
  ├─ lib/registry.sh   クローン台帳
  ├─ lib/android.sh    Android標準画面との連携
  ├─ lib/builder.sh    XAPK統合、変更、再構築、署名
  ├─ lib/updater.sh    GitHubからの自己更新
  ├─ lib/commands.sh   非対話CLI
  └─ lib/ui.sh         対話メニュー
```

`install.sh`は依存パッケージとAPKEditorを導入し、`$PREFIX/opt/kbc-clone`へ実行コードを配置する。

## データフロー

```text
XAPK
  → manifest.json検証
  → SHA-256で展開キャッシュを検索
  → 初回のみsplit APK統合
  → 初回のみManifest/resources展開
  → 読み取り専用テンプレートを高速複製
  → package・permission・authorities・label・icon変更
  → APK再構築
  → 16 KiB対応zipalign
  → 端末固有鍵でv2/v3署名
  → Android標準インストーラー
  → クローン台帳更新
```

## 永続データ

| パス | 内容 |
|---|---|
| `~/.local/share/kbc-clone/keystore/` | 更新に必要な署名鍵 |
| `~/.local/share/kbc-clone/icons/` | 更新時に再利用する指定アイコン |
| `~/.local/state/kbc-clone/clones.tsv` | クローン台帳 |
| `~/.cache/kbc-clone/templates/` | 最新XAPKの展開済みテンプレート |
| `~/.cache/kbc-clone/work/` | ビルド中間ファイル |
| `/sdcard/Download/KBC-clone-nyanko/` | 生成APK |

台帳には、パッケージ名、表示名、versionCode、versionName、ABI、入力XAPKのSHA-256、更新日時、保存済みアイコンのパスを保存する。公式サーバーや外部サービスへ台帳を送信しない。

## クローン識別子

新規クローンのパッケージ名は`jp.co.ponos.battlecats.kbc.`を固定プレフィックスとし、利用者が入力した識別子を連結する。識別子は小文字英字で始まる英小文字・数字・`_`・`.`だけを許可する。CLIと対話UIはどちらも完全なパッケージ名を入力させない。

旧試作版の`jp.co.ponos.battlecats.kbcclone`は台帳登録と更新のみ許可し、新規作成規則とは分離する。

## アイコン

入力はPNGだけを受け付け、PNGシグネチャを検証する。展開したリソース内の通常アイコンとアダプティブアイコン前景を同じPNGへ差し替える。正方形で、外周に余白を含むPNGを推奨する。

ビルド成功後にPNGを`~/.local/share/kbc-clone/icons/`へ複製し、台帳へそのパスを保存する。更新時は保存済みPNGを自動利用する。公式アイコンを選んだ場合は保存パスを空にし、新XAPK側のアイコンをそのまま使う。

## 高速キャッシュ

端末内のXAPKは作業領域へ複製せず、元ファイルを直接読み込む。入力XAPKのSHA-256ごとに統合・展開結果をキャッシュし、同一入力では再利用する。

作業用ディレクトリは、同一ファイルシステムならハードリンクで即座に作る。Manifestとアイコンは置換時にリンクを切り、読み取り専用の元テンプレートを変更しない。ハードリンクが利用できない環境では通常コピーへ自動的に切り替える。

キャッシュは最新のXAPK 1件だけを保持する。署名鍵、指定アイコン、台帳とは分離しているため、キャッシュ全体を削除しても既存クローンの更新能力には影響しない。

## 対話UI

初見利用者向けの対話UIは、作成と更新を4段階に分割する。専門用語には説明と安全な初期値を付け、一覧選択の誤入力では終了せず再入力を受け付ける。処理中の致命的エラーは操作単位のサブシェルに閉じ込め、メインメニューへ戻す。

## 自己更新

`lib/updater.sh`はGitHubの`main`ブランチにある`VERSION`を取得し、現在版より新しい場合だけソースアーカイブを取得する。アーカイブについて次を検証してから`install.sh --update`を実行する。

- VERSIONが認識可能な形式であること
- gzipおよびtarとして読めること
- 絶対パスや`..`を含まないこと
- 必須の起動・セットアップファイルが存在すること
- 個別取得したVERSIONとアーカイブ内VERSIONが一致すること

更新モードの`install.sh`は導入済み依存パッケージを再利用し、署名鍵、指定アイコン、台帳、展開キャッシュを変更しない。対話UIから更新した場合は、上書き完了後に新しい実行ファイルへ自動再起動する。

## 更新

クローン更新では次の値を維持する。

- クローンのパッケージ名
- クローンの表示名
- クローンの指定アイコン
- 端末内の署名鍵

新XAPKのversionCodeが既存値以上なら、Androidの上書きインストールとして扱える。署名鍵を失った場合は上書きできない。

旧試作版から更新する場合は、初回セットアップ時に`~/kbc-clone/keystore/`から新しい保存先へ署名鍵を移行する。新しい保存先に鍵が存在する場合は上書きしない。

## 確定事項

- APKEditor 1.4.9でXAPKのsplit統合、XML展開、APK再構築ができる。
- DEXをrawのまま保持することで、smaliの再構築を避けられる。
- Pixel 8では`arm64-v8a`版の生成、署名、インストール、起動に成功した。
- 通常権限のTermuxから`pm list packages`と`pm path`を実行すると、Android 15でPackageManagerのBinder呼出が拒否される。
- `termux-open`とAndroid標準画面を使ったインストール管理は可能である。
- ランチャーIntentのpackage指定はPackage Visibilityにより解決できない場合があるが、既知の`MyActivity`を明示すると本家とクローンを起動できる。

## 推定事項

- 他のAndroidバージョンでも、端末ABIに一致するXAPKなら同じ処理で生成できる可能性が高い。
- 将来のManifest変更や新しいProvider追加により、書換え対象が増える可能性がある。

## 公開境界

リポジトリへ含めるもの:

- Termux用スクリプト
- CIテスト
- 設計資料

含めないもの:

- APK、XAPK、ゲームデータ
- 署名鍵、署名パスワード
- ネイティブコード解析資料
- APKComboの一時ダウンロードURL
