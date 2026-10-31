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
