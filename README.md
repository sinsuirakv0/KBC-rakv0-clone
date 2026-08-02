# KBC cloneにゃんこ

Termux上で、にゃんこ大戦争のXAPKから別パッケージのクローンAPKを作成・管理するツールです。

## 主な機能

- 番号を選ぶだけの対話メニュー
- 4段階の作成・更新案内
- 入力ミス後もメニューへ戻れるエラー処理
- 端末のABI確認
- XAPKの自動検索
- 同じXAPKの展開結果を再利用する高速キャッシュ
- クローンの複数作成
- アプリ名・アイコン・パッケージ識別子の指定
- 本家とクローンの起動・アプリ情報・アンインストール
- 同じ署名鍵とパッケージ名によるクローン更新
- 作成したクローンのローカル台帳
- コマンドライン操作

APK、XAPK、ゲームデータはこのリポジトリに含みません。

## 必要なもの

- GitHub版またはF-Droid版のTermux
- Android 7.0以降
- 2 GB以上の空き容量を推奨
- 使用端末のABIに合う、正規に入手したXAPK

Pixel 8などの64bit専用端末では`arm64-v8a`版が必要です。

## インストール

```bash
pkg update
pkg install git
git clone https://github.com/sinsuirakv0/KBC-rakv0-clone.git
cd KBC-rakv0-clone
bash install.sh
```

セットアップ後は、どのディレクトリからでも起動できます。

```bash
kbc-clone
```

初回のみAndroidの設定で、Termuxに「不明なアプリのインストール」を許可してください。

## 基本操作

起動後に番号を選択します。

```text
1. 新しいクローンを作る
2. 作ったクローンを更新する
3. アプリを開く・削除する
4. 作ったクローンの一覧
5. ツールが動くか確認する
6. このツールを更新する
0. 終了
```

XAPKを`Download`フォルダへ置くと、更新日時が新しい順に自動表示されます。画面では次の順番で案内します。

```text
1. 元になるXAPKを選ぶ
2. アプリ名と識別IDを決める
3. アイコンを選ぶ
4. 内容を確認して作成する
```

識別IDとアイコンは初期値のままでも作成できます。

新規作成時のパッケージ名は、次の固定部分に任意の識別子を連結します。

```text
jp.co.ponos.battlecats.kbc.<識別子>
```

識別子には、小文字英字で始まる英小文字・数字・`_`・`.`を使用できます。アイコンは正方形のPNGを推奨します。指定したアイコンはツール内へ保存され、次回更新でも自動的に再利用されます。

## コマンド操作

```bash
kbc-clone create \
  --xapk /sdcard/Download/battlecats-arm64-v8a.xapk \
  --package-suffix sub1 \
  --app-name "自分のにゃんこ" \
  --icon /sdcard/Download/my-icon.png \
  --install
```

登録済みクローンの更新:

```bash
kbc-clone update jp.co.ponos.battlecats.kbc.sub1 \
  --xapk /sdcard/Download/battlecats-new.xapk \
  --install
```

更新時に表示名やアイコンを変更することもできます。公式アイコンへ戻す場合は`--original-icon`を指定します。

その他:

```bash
kbc-clone list
kbc-clone doctor
kbc-clone --help
```

## 署名鍵

クローンを上書き更新するには、初回作成時と同じ署名鍵が必要です。署名鍵は次へ保存されます。

```text
~/.local/share/kbc-clone/keystore/
```

このフォルダを削除すると、既存クローンを更新できなくなります。安全な場所へバックアップしてください。署名鍵やパスワードをGitHubへアップロードしないでください。

旧試作版の`~/kbc-clone/keystore/`が存在し、新しい保存先にまだ鍵がない場合、`install.sh`が署名鍵を自動移行します。

指定したアイコンは`~/.local/share/kbc-clone/icons/`へ保存されます。元のPNGを`Download`から削除しても、登録済みクローンの更新には影響しません。

## 処理時間

新しいXAPKを初めて使用するときは、split APKの統合とリソース展開が必要です。これはAPKの容量が大きいため時間がかかります。

展開結果は`~/.cache/kbc-clone/templates/`へ保存されます。同じXAPKから別のクローンを作る場合や、作成をやり直す場合はこの処理を省略します。新しい版のXAPKを使うと、古い展開キャッシュは自動的に削除されます。

動作が不安定な場合は、このキャッシュを削除して再作成できます。署名鍵、アイコン、クローン台帳は削除されません。

```bash
rm -rf ~/.cache/kbc-clone/templates
```

## ツールの更新

メニューの`6. このツールを更新する`を選ぶと、GitHub上の最新版を確認します。更新がある場合は確認後に取得・検証・インストールし、新しいバージョンで自動的に再起動します。

更新しても次のデータは維持されます。

- クローン更新用の署名鍵
- 指定したアプリアイコン
- 作成済みクローンの台帳
- XAPKの展開キャッシュ

コマンドから確認・更新する場合:

```bash
kbc-clone self-update --check
kbc-clone self-update
```

更新元は`sinsuirakv0/KBC-rakv0-clone`の`main`ブランチです。リポジトリがGitHubへ公開されるまでは自動更新を利用できません。

## Android側の制約

通常権限のTermuxからは、Androidにインストールされた全アプリの一覧と正確なバージョンを取得できません。初版はツールの台帳を使い、Android標準画面を通じて起動、更新、アプリ情報、アンインストールを行います。

将来は任意導入の小さなAndroid連携アプリを用意し、正確なインストール状態を表示できるようにする予定です。

## 注意

- 自分が利用権限を持つアプリと端末だけを対象にしてください。
- 元APKや生成APKの再配布を目的としたツールではありません。
- 再署名により、Play Integrity、課金、Firebaseなど一部機能が動作しない場合があります。
- 本ツールはPONOS株式会社およびAPK配布サイトの公式ツールではありません。

詳しい構成は[docs/architecture.md](docs/architecture.md)を参照してください。
