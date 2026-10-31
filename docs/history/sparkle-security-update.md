# Sparkleの安全性修正を含む依存更新 (#304)

## 目的と範囲

Sparkle 2.9.0とXcodeの最低指定2.5.1を、公式安定版2.10.1へ整合させる。
Package.resolvedはXcodeの正規の依存解決で更新する。配布用ツールも同じ
解決済みリビジョンからビルドし、古いDerivedDataのチェックアウトを拾わない。
Planレビューは依頼に従い同じ実装フローに含める。

正式版feed `https://apps.kawaken.dev/zashiki/appcast.xml`、GitHub Releaseの
appcast履歴とZIP署名、手動更新チェック、自動チェック無効を維持する。
v0.12.0の正式版配布を基準にし、古いstable/preview分離は復活させない。
#177のDeveloper ID署名・notarization・自動更新有効化は対象外。
実リリース公開・既存asset変更をせず、needs-verificationも付けない。

## 公式情報と選定

- [2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1) は
  2026-10-25公開の最新安定版。2.10.0以降はmacOS 12以上が必要。
  Zashikiの最低OSはmacOS 15なので引き上げ不要。Package.swiftは
  swift-tools-version 5.5でバイナリXCFrameworkを提供する。
  Xcode 26系のCIと現在のXcodeでAPI・ソースツールのビルドを確認する。
  [公式README](https://github.com/sparkle-project/Sparkle/blob/2.10.1/README.markdown)
  のビルド要件は最新メジャーXcodeとその一つ前で、27/26が該当する。
- 2.9.6は最低限の代替案だが、2.10.1のappcast解析とインストール修正も
  取り込む。2.10.1で互換性に問題があれば選定を見直す。
- [公式security advisories](https://github.com/sparkle-project/Sparkle/security/advisories)
  の情報を採用する。CVE-2026-47121/47122は2.9.2で修正済み。
  前者は署名済み悪意あるdeltaによるsymlink経由の書込で、鍵漏洩などが前提。
  後者は更新インストール途中のローカルXPC接続による表示メタデータ偽装で、
  署名検証済みのインストール対象コードの改変ではない。
- CVE-2026-115568はdelta修正の不完全性で2.9.5で修正。
  GHSA-3x7w-j75x-ppq5（ダウンロードパスの検証と移動の競合）と
  GHSA-4v99-qgq9-6pxp（root updaterのキャッシュsymlink追跡）は2.9.6で修正。
  後二つの公式advisoryにはCVE番号がないため、推測で割り当てない。
- Zashikiの配布workflowは`--maximum-deltas 0`でZIPのみ生成し、自動更新は
  無効。通常のGUIはrootで起動しない。deltaとroot CLIの条件は通常の配布に
  当てはまらないが、手動更新もインストーラを使うため更新経路の修正は必要。
  脆弱性の実攻撃再現・到達不能の証明は行わない。

## 実装と検証計画

1. Xcode最低指定を2.10.1に更新し、XcodeでPackage.resolvedを再生成する。
2. release workflowのツールを解決済みSparkleのリビジョンに固定する。
3. `just test`（XCTest含む）、`just lint`、アプリビルドとPR CIを確認する。
4. 一時テスト鍵とテストZIPでgenerate_appcast・sign_updateの署名検証を確認する。
   改変ZIP・別公開鍵が拒否され、履歴と正式版項目が維持されることを確認する。
   配布秘密鍵・Keychainを使わず、秘密をログやリポジトリに残さない。
5. SPUUpdater・delegate・手動チェックのコンパイルと関連XCTestを確認する。
   実アプリでの更新適用、配布鍵による署名、Developer ID・notarizationは
   未確認事項としてPRへ明記する。
6. 結果を本Planへ追記しdocs/historyへ移動、PRのCI後に通常mergeのAutoMerge。
   マージ確認後にIssueへ記録しwipを外して明示的にcloseする。

## 実装中の確認事項

- release workflowは`-onlyUsePackageVersionsFromResolvedFile`で専用ディレクトリへ
  依存を解決し、SparkleのHEADとlockfileのrevision一致を検査してからツールを
  ビルドする。同オプションでの解決とrevision一致をローカルで確認した。
- Xcode 27.2でgenerate_appcast・sign_updateのReleaseビルドに成功。
  一時Ed25519 seedをファイルから標準入力へ渡し、Keychainや配布鍵を使わず検証した。
  正しいZIP署名、generate_appcastとsign_updateの署名一致、同じサイズの改変ZIPと
  別鍵の拒否、旧項目の保持、現行URL・version・length・最低OS、delta無しを確認。
  一時秘密鍵ファイルは検証後に削除した。
- ReleaseFast/nativeのZashiki.appビルド成功。同梱Sparkle 2.10.1、最低OS 12.0、
  アプリ最低OS 15.0、`SUEnableAutomaticChecks=false`を生成済みplistで確認。
- 2026-10-31の読み取り確認で、現在の公開feed
  `https://apps.kawaken.dev/zashiki/appcast.xml` はHTTP 404だった。
  既存のURL・配布基盤は本件で変更せず、オンライン更新チェック成功とは扱わない。
  実アプリでの更新適用、配布鍵署名、Developer ID・notarizationも未検証。
- GitHub Release v0.12.0のappcastは読み取り取得でき、正式版0.12.0と0.11.0の
  項目・ZIP URL・EdDSA署名属性が存在した。公開feedの404と区別する。

## 検証結果と完了手順

- `just test`: exit 0。shell integration 2件、Zigフルテスト、macOS XCTestを実行。
  XCTestは399件通過（更新状態・表示の既存テスト33件を含む）。
- `just lint`: exit 0。Swift 204ファイルで違反0、Zig整形チェックも成功。
- `zig build -Doptimize=ReleaseFast -Dxcframework-target=native`: exit 0。
- release workflowのYAML読込・抽出したbashの`bash -n`と`git diff --check`: 成功。
- Package.resolvedはXcodeの依存解決で生成し、Sparkle以外のpinは変更なし。
  解決済みrevisionは`ab7d71291238df6e0492143b120c9b696a35f603`。
- PR #314で`just test-fast`と`just lint`を最終headに対して確認してからAutoMergeする。
  通常のPRアプリartifact buildはneeds-verification無しなのでskipされるが、
  ローカルのReleaseFastビルドでアプリを検証済み。
- 実リリース・既存Release assets・Developer ID・notarization・自動更新設定は変更しない。
  マージ後、#304へ結果を記録しwipを外して明示的にcloseする。
