# AutoUpdateのfeed URL・署名鍵切り替え

## 背景

Zashikiのアプリ名・Bundle ID・アイコンは既にリブランド済み（`dev.kawaken.zashiki`）で、
GitHub Releaseでの配布も`release.yml`で最小構成が動いている。しかしAutoUpdate機能
（Sparkle）は本家Ghosttyの設定がそのまま残っている:

- `macos/Sources/Features/Update/UpdateDelegate.swift`の`feedURLString`が
  `tip.files.ghostty.org` / `release.files.ghostty.org`という**本家Ghosttyのサーバー**
  を向いたまま
- `macos/Zashiki-Info.plist`の`SUPublicEDKey`も**本家の公開鍵**のまま

このままではSparkleのappcastが取得できても本家Ghosttyの署名検証しか通らず、Zashiki
独自ビルドのAutoUpdateとしては機能しない。`release.yml`のコメントにも「Sparkle自動更新
の追加は別タスク」と明記されており、これまで意図的に先送りされたまま未着手だった箇所。

今回のゴールは、**AutoUpdateを実際にエンドユーザーへ有効化するところまではやらず**、
後で`SUEnableAutomaticChecks`をtrueにすればすぐ機能する状態まで配線を整備すること。
理由: Apple Developer登録・notarizationが済んでいない状態でSparkleの自動DL・自動
インストールを有効化すると、ダウンロードされたバイナリがGatekeeperに引っかかり自動更新
が正常に完了しない可能性が高いため。

## 決定事項

1. **appcast.xmlのホスト先**: GitHub Releaseの固定URL
   `https://github.com/kawaken/zashiki/releases/latest/download/appcast.xml`を使う。
   バージョンが上がってもURLは変わらない（GitHub純正の`latest/download/{filename}`
   リダイレクト機能）。GitHub Pagesや独自ドメインは使わない
2. **tip/stableチャンネル機構**: `auto-update-channel`設定・`feedURLString`のswitch文は
   **コードとしてそのまま維持**。今回はstable用のappcast.xmlのみ生成・公開する。tipを
   選択しても「アップデートが見つかりません」になるだけで実害はなく、将来nightly build
   を整備すればそのまま使える
3. **機能の有効化タイミング**: `SUEnableAutomaticChecks`は`false`のまま維持（変更しない）。
   Apple Developer登録・notarizationが完了してから改めて`true`にする（別タスク）

## 実装ステップ

### 1. Sparkle EdDSA鍵ペアの新規生成
- SparkleのSPM checkoutに同梱の`generate_keys`ツールを使用
  （`~/Library/Developer/Xcode/DerivedData/.../SourcePackages/checkouts/Sparkle/bin/generate_keys`、
  または`zig build`後に取得できるパス）
- 生成された**公開鍵**で`macos/Zashiki-Info.plist`の`SUPublicEDKey`を書き換える
- 生成された**秘密鍵**はmacOS Keychainに保存される。CIでappcast署名に使うため、ユーザー
  自身の手でKeychainからエクスポートし、GitHub Actions Secretsに登録する必要がある
  （**エージェント側では自動化不可、手動作業が必要な旨をREADMEかLOCAL_PATCH.mdに手順
  として書く**）

### 2. `feedURLString`の書き換え
`macos/Sources/Features/Update/UpdateDelegate.swift`:
- `stable`: `https://github.com/kawaken/zashiki/releases/latest/download/appcast.xml`
- `tip`: 現状は提供しない。コメントで「tip用appcastは未提供、選択時は404で更新なし扱いに
  なる」旨を明記する

### 3. `release.yml`にappcast生成ステップを追加
- Sparkleの`generate_appcast`ツールでビルド済みzip（`Zashiki-*-macos.zip`）から署名付き
  appcast.xmlを生成
- 秘密鍵はGitHub Actions Secrets経由で`generate_appcast`に渡す
- `softprops/action-gh-release`の`files:`にappcast.xmlも追加してリリースに添付
- **実装時に詰める点**: Sparkleのappcastは本来「過去バージョン一覧」を累積したXMLが正しい
  形。単発のCI実行だけでは過去分を再構築できないため、(a)毎回過去の全リリースzipを取得
  してappcastをフル再生成する方式、(b)前回リリースのappcast.xmlをダウンロードして新エント
  リを追記する方式、のどちらにするかはSparkle公式ドキュメントを見ながら実装時に決める

### 4. ドキュメント更新
- `release.yml`の既存コメント（「Sparkle自動更新の追加は別タスク」）を、「配線は整備済み・
  有効化はDeveloper登録後」という現状に合わせて更新
- 秘密鍵のSecrets登録など、人間の手作業が必要な手順を`LOCAL_PATCH.md`等に追記

## 今回やらないこと（Out of scope）

- Apple Developer Program登録・Developer ID署名・notarization
- `SUEnableAutomaticChecks`を`true`にすること（機能の実際の有効化）
- tip/nightly buildワークフローの新設
- `auto-update-channel`設定のコード簡略化・削除

## 検証方法

- `generate_keys` / `generate_appcast`をローカルで試し、appcast.xmlが期待通り生成される
  か確認
- `zig build -Demit-macos-app`でZashiki.appをビルドし、`Zashiki-Info.plist`の
  `SUPublicEDKey`が新しい鍵に更新されていることを確認
- `feedURLString`変更後、`zig build test`（Swift側は該当なければXcodeビルドの成功で代替）
  でコンパイルが通ることを確認
- `release.yml`の構文はGitHub Actionsの`workflow_dispatch`テスト実行、または`actionlint`
  があればそれで確認
- `SUEnableAutomaticChecks`が`false`のままであることを最終確認（誤って有効化していないか）
