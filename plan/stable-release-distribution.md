# 正式版配布と公開 appcast の連携

## 目的

正式版だけを GitHub Releases から配布し、Sparkle の署名付き `appcast.xml` と
配布物のメタデータを Release asset として管理する。サイト側は Release asset を
取得して公開 feed を提供するが、Zashiki の release workflow はサイトの
リポジトリを操作しない。

## 方針

- 配信対象は stable の正式版だけとする
- preview、beta、RC、nightly、`tip` の配信は行わない
- GitHub Pages は使わず、ZIP は GitHub Release から配信する
- Release に `Zashiki-<tag>-macos.zip`、`appcast.xml`、`release-manifest.json` を添付する
- `appcast.xml` の enclosure は対応する GitHub Release の ZIP URL を参照する
- EdDSA 秘密鍵は Zashiki リポジトリの Actions secret だけで扱い、サイト側へ渡さない
- 過去の正式版項目を appcast に保持する
- 自動更新チェックは有効化しない。`SUEnableAutomaticChecks=false` を維持する
- Developer ID 署名と公証は別作業とする

## appcast の参照先

新しい公開 feed の初期内容が公開され、手動更新チェックで取得できることを
確認した後、アプリの参照先を次へ切り替える。

`https://apps.kawaken.dev/zashiki/appcast.xml`

既存アプリの移行期間中も、GitHub Release に添付した `appcast.xml` は削除しない。
これにより、切り替え前のアプリは従来の Release URL から更新を取得できる。

## release-manifest.json 契約

`schema_version` は JSON number、それ以外の日時・バージョン・URL・ハッシュは
JSON string とする。`archive.size` はバイト数を表す JSON number とする。

| フィールド | 型 | 内容 |
| --- | --- | --- |
| `schema_version` | number | 契約バージョン。初版は `1` |
| `version` | string | 表示用の `CFBundleShortVersionString`。例: `0.12.0` |
| `build_version` | string | `CFBundleVersion` と同じ値。Sparkle が比較する単調増加ビルド番号 |
| `tag` | string | Git tag。例: `v0.12.0` |
| `published_at` | string | GitHub Release の RFC 3339 UTC 公開日時 |
| `minimum_macos_version` | string | ビルド済みアプリの `LSMinimumSystemVersion` |
| `release_notes_url` | string | GitHub Release の URL |
| `archive.name` | string | ZIP asset のファイル名 |
| `archive.url` | string | ZIP asset の GitHub Release download URL |
| `archive.size` | number | ZIP asset のバイト数 |
| `archive.sha256` | string | ZIP asset の SHA-256。小文字 16 進 64 文字 |
| `appcast.name` | string | `appcast.xml` |
| `appcast.sha256` | string | Release に添付する appcast の SHA-256。小文字 16 進 64 文字 |

生成例:

```json
{
  "schema_version": 1,
  "version": "0.12.0",
  "build_version": "12000",
  "tag": "v0.12.0",
  "published_at": "2026-10-24T03:15:00Z",
  "minimum_macos_version": "15.0",
  "release_notes_url": "https://github.com/kawaken/zashiki/releases/tag/v0.12.0",
  "archive": {
    "name": "Zashiki-v0.12.0-macos.zip",
    "url": "https://github.com/kawaken/zashiki/releases/download/v0.12.0/Zashiki-v0.12.0-macos.zip",
    "size": 15000000,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  },
  "appcast": {
    "name": "appcast.xml",
    "sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  }
}
```

`build_version` は stable version から `major * 1_000_000 + minor * 1_000 + patch`
で算出する。現在の正式版が `1` を使っているため、新しい正式版は必ず `1` より
大きくなり、既存アプリからの更新判定も壊さない。各コンポーネントは 0 から 999
までを想定する。

## Release workflow

1. `version` 入力を `X.Y.Z` の正式版だけに制限する
2. `zig build test` と Release build を実行する
3. アプリの version、build version、最低 macOS バージョンを built app から取得する
4. ZIP を作成し、SHA-256 とサイズを計算する
5. 前回の stable appcast を取得する。HTTP 404 だけを初回未存在と扱い、通信失敗・認証エラー・サーバーエラーは失敗させる
6. Sparkle `generate_appcast` で過去項目を保持しながら新しい正式版を追加し、EdDSA 署名を付ける
7. appcast の既存項目が消えていないこと、ZIP URL・サイズ・version が一致することを検証する
8. GitHub Release に ZIP と appcast を作成する
9. Release の `published_at` を取得して manifest を生成し、同じ Release に添付する
10. manifest の型、URL、サイズ、ハッシュ、appcast と ZIP の整合性を検証する

## 移行と検証

- 初期 feed の公開後、公開 URL を使った手動更新チェックを行ってからアプリの
  feed URL を切り替える
- 既存 Release の `appcast.xml` は残す
- 自動更新チェックが無効のままであることを Info.plist と起動時設定で確認する
- 公開 feed の運用とサイトリポジトリの CI は別途管理し、Zashiki 側から操作しない

## 完了後

実装上の判断と検証結果をこの文書に追記し、実装完了時に `docs/history/` へ移す。
