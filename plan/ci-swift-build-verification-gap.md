# CIでSwiftコードのビルド検証が抜けている問題

## 発見の経緯

PR #30（`scripts/zashiki-md-preview`削除、`AppDelegate.swift`のdocコメント変更を
含む）のCIを確認していて気づいた。「Swiftファイルの変更でも`zig build test`
ジョブは走るはずだが、実際にSwiftコードを検証しているのか？」という疑問から
`build.zig`を調査した。

## 現状

`.github/workflows/test.yml`のPR/push時CIは以下のコマンドを実行する:

```shell-session
zig build test -Demit-macos-app=false -Demit-xcframework=false
```

`build.zig`には以下の条件がある（該当箇所は`GhosttyXCFramework`と
`ZashikiXcodebuild`の初期化ブロック全体を囲むガード）:

```zig
if (!config.emit_lib_vt and config.target.result.os.tag.isDarwin() and
    (config.emit_xcframework or config.emit_macos_app))
{
    // xcframeworkのビルド、およびZashikiXcodebuild
    // （macOSアプリ＝Swiftコードのビルド全体）は
    // このブロックの中でしか初期化されない
    ...
}
```

`emit_xcframework=false`かつ`emit_macos_app=false`の両方を指定すると、この
`if`全体が成立せず、**macOSアプリ（Swiftコード）のビルドステップ自体が
一切作られない**。テストが除外されているだけでなく、コンパイルの試行すら
行われていない。

## 経緯（意図せぬ副作用と思われる）

直前のコミット `006754a0c`（2026-08-13、「ci: PR/pushのCIからxcodebuild test
を除外しリリース時に寄せる」）で`-Demit-xcframework=false`が追加された。
このコミットの意図は「遅くて（約1分40秒）実効性も疑わしい`xcodebuild test`
ステップだけを除外する」ことだったが、実際には`emit_xcframework`という
フラグ経由でmacOSアプリのビルドステップ全体（テストだけでなくコンパイルも）
が消える、という副作用があった。コミットメッセージにはこの副作用への言及が
なく、意図してビルドごと除外したわけではなさそうに見える。

## 影響

- Swiftコードを変更するPR/pushは、CIで**ビルドが通るかどうかすら検証されない**
- `swiftlint`（Lintジョブ）は静的解析のみで、実際のコンパイル可否は保証しない
- 実際にSwiftコードがビルドされる・テストされるのは`release.yml`
  （タグpush時のみ）だけ

## 対応方針（未着手）

`xcodebuild test`（遅い・複数destinationマッチでフレーキーという実効性の
問題）は引き続き除外しつつ、**ビルドの成否だけを検証する軽量なステップ**を
PR/push時CIに復活させたい。`ZashikiXcodebuild`（`src/build/
ZashikiXcodebuild.zig`）の`install()`/`xctest`ステップの配線を確認し、
「ビルドはする・testは走らせない」という組み合わせが既存のフラグで表現
できるか、それとも新しいオプションが要るかを調査する必要がある。

実機でのフルビルド確認（Xcode必須）が要る調査なので、GUI/Xcodeにアクセス
できる環境で着手すること。
