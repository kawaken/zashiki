# 不要になったMANPATH設定の整理

## 背景

Zashikiではmanページの生成・同梱を削除済みであり、`pandoc`や`share/man`を
アプリケーションへ提供していない。一方、macOSの子プロセス起動時には
`src/termio/Exec.zig`がアプリケーションリソース相対の`MANPATH`を環境変数へ追加して
いる。このパスには現在manページが存在しないため、古いmanページ配布の名残になっている。

## 目的

存在しないZashiki内蔵manページを指す`MANPATH`設定を削除し、manページ削除後の実際の
配布内容と子プロセス環境を一致させる。

## 方針

- macOSの子プロセス環境を構築する`MANPATH`追加処理を削除する
- 既存のユーザー環境変数`MANPATH`を変更・削除しない
- `XDG_DATA_DIRS`など、manページ以外の目的で使われている環境変数設定は変更しない
- manページの再生成や新しいドキュメント機能は追加しない

## 実施内容

1. `src/termio/Exec.zig`から、アプリケーション相対の`MANPATH`を構築して環境へ追加する
   ブロックを削除する
2. MANPATHを前提にしているコメントやテストが他にないか確認し、あれば現状に合わせて
   整理する
3. `docs/history/remove-manpage-generation.md`の記録と矛盾しないことを確認する

## 検証

- macOS向けの対象テストまたは`zig build test -Demit-macos-app=false`が通る
- Zashikiから起動した子プロセスが、ユーザー設定済みの`MANPATH`を保持する
- Zashiki固有の存在しないmanディレクトリが`MANPATH`へ追加されない
- `XDG_DATA_DIRS`など既存のリソース検索用環境変数に意図しない変更がない

## 完了後

PRがmainへマージされたら、このplanファイルを削除する。今回の変更理由は既存の
`docs/history/remove-manpage-generation.md`で説明できるため、追加のhistory文書は原則
作成しない。
