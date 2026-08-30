# justによる開発タスクランナー導入

## 目的

Zashikiの開発・検証・配布準備で使うコマンドを`just`にまとめ、利用可能な
作業を一覧から発見できるようにする。素のコマンドを単に短縮することが目的
ではなく、複数のツールやオプションを覚えずに、目的ベースのタスクを実行できる
開発者向けの入口を用意する。

完成したアプリの機能を呼び出すためのランチャーにはしない。Markdownプレビュー
など、アプリ利用者向けの操作は対象外とする。

## 背景・現状

- `Makefile`には`init`・`glad`・`clean`があるが、ビルドやテストの入口には
  なっていない
- 実際のビルド・テスト・Lintは、`zig build`、`xcodebuild`、`swiftlint`、
  `prettier`などを個別に呼び出している
- `.github/workflows/test.yml`と`release.yml`で、Xcode選択・Zigセットアップ・
  ビルド処理が重複している
- Zigのビルドシステムには、`run`、`test`、`run-valgrind`、`test-valgrind`、
  `dist`、`distcheck`のステップが既にある
- Xcodeはタスクランナーでインストール・バージョン管理するものではない。必要な
  Xcodeを選び、タスクから`xcodebuild`を呼び出す役割分担にする

## 方針

- タスク定義はリポジトリ直下の`justfile`に置く
- タスク名とdescriptionは、実行するコマンドではなく目的を表す
- Zigはビルドシステムとして残し、`just`は開発作業の入口として使う
- ツールのバージョン管理はmiseに寄せる。`just`自身をmiseで管理するか、
  Homebrewなどで導入するかは別途決める
- Xcodeの選択は、システム全体を変更する`xcode-select`ではなく、必要に応じて
  タスク内の`DEVELOPER_DIR`で扱えるか検討する
- ローカルとCIで同じタスクを使える構成を目指すが、リリースCIの全面見直しは
  別planで扱う

## タスク候補

### 基本タスク

| タスク             | 内容                                                  |
| ------------------ | ----------------------------------------------------- |
| `build`            | 通常のDebugビルド（`zig build`）                      |
| `build-core`       | macOSアプリを除いたビルド                             |
| `run`              | 開発用ビルドを実行してアプリを起動（`zig build run`） |
| `test`             | フルテスト（macOSアプリのXCTestを含む）               |
| `test-fast`        | PR向けにXCTestを省略したテストとSwiftコンパイル       |
| `test-filter NAME` | Zigテストを名前で絞り込む                             |
| `lint`             | Zig fmtチェック、SwiftLintのチェック                  |
| `format`           | ZigとSwiftのフォーマッタによる自動修正                |
| `clean`            | ビルド成果物を削除                                    |
| `logs`             | ZashikiのmacOSログを表示                              |

### 補助タスク

| タスク          | 内容                                                               |
| --------------- | ------------------------------------------------------------------ |
| `help`          | タスク一覧と使い分けを表示。`just`のデフォルト表示との関係を決める |
| `ci`            | ローカルでPR向けのチェック一式を実行                               |
| `dist`          | Zigの配布用tarball生成ステップを呼び出す                           |
| `distcheck`     | 配布物の検証ステップを呼び出す                                     |
| `xcode-version` | 使用中のXcodeバージョンを確認する。必要性を見て採否を決める        |

Markdownプレビュー起動のような完成済みアプリの利用コマンドは追加しない。

## Xcodeの扱い

- macOS用タスクでは、インストール済みXcodeの選択方法を決める
- `xcode-select`でシステム設定を変更する方法と、`DEVELOPER_DIR`をタスクの
  環境変数として渡す方法を比較する
- ローカルの「最新Xcodeを使う」運用と、CIのrunner上でのXcode選択を同じ
  タスクで扱えるか確認する
- `zig build`内部のXcode呼び出しにも環境変数が伝わるか検証する

## CIとの関係

まずローカル開発タスクを定義し、既存のCIコマンドと対応付ける。その後、
`test.yml`のPRチェックから`just`を呼ぶかを判断する。

リリースCIについては、タグ発行・フルテスト・アプリビルド・appcast生成・
GitHub Release作成の流れ自体を別途見直すため、本planでは実装しない。

## 実装ステップ

1. `just`の導入方法とサポートするバージョンを決める
2. 基本タスクを`justfile`に定義し、タスク一覧・descriptionを整える
3. Xcode選択とログ表示をタスク化して、ローカルで実行結果を確認する
4. `test`・`test-fast`・`lint`の終了コードと引数の受け渡しを検証する
5. 必要なタスクだけCIから呼び出す構成を検討する
6. `CLAUDE.md`のCommandsを、実装済みの`just`タスクを入口とする説明に更新する

## 検証

- `just`だけでタスク一覧と使い分けを確認できる
- `build`・`build-core`・`run`が意図したZigオプションで動く
- `test`・`test-fast`・`test-filter`がそれぞれ適切なテスト範囲になる
- `lint`はCIと同じチェックを実行し、失敗時に終了コードを返す
- `format`は既存のpre-commit hookと競合しない
- Xcodeタスクが選択したXcodeでSwiftコンパイルとXCTestを実行できる
- `clean`が現在のMakefileと同じ成果物を安全に掃除する
- `logs`が必要なログを表示し、通常の開発作業を邪魔しない

## 未決事項

- `just`の導入元（mise、Homebrew、CI用の公式インストール手順など）
- `justfile`に全タスクを書くか、複雑な処理を`scripts/`などのシェルスクリプトへ分離するか
- `clean`の実体をMakefileに残すか、`justfile`へ移すか
- `build-core`が実際に必要か、`test-fast`との役割をどう分けるか
- `ci`に含めるタスクと、macOSランナーのコストが高い処理の扱い
- Xcodeを「最新」に解決する方法と、CIでの再現性の確保

## 実装結果

- `just` は macOS の開発環境では Homebrew、CI では `brew install just` で導入する。
  `just` 自体のバージョン管理を mise に追加することは、既存の mise 設定がないため
  今回は行わない。
- リポジトリ直下の `justfile` に、build・test・lint・format・clean・logs・dist・
  `xcode-version` と、PR向けの `ci` を定義した。`just` を引数なしで実行すると、
  `help` と同じ一覧と使い分けを表示する。
- 既存の Makefile にあった `clean` と `glad` は `justfile` に移し、Makefile は削除した。
- README に `just` の導入方法、代表的なタスク、`DEVELOPER_DIR` の使い方を追加した。
- Markdown は lint/format の対象に含めない。Prettier は既存の手動コマンドとして
  残すが、開発タスクや CI からは呼び出さない。
- `DEVELOPER_DIR` を Xcode 選択の入口にし、タスクや CI がシステム全体の
  `xcode-select` を変更しないようにした。CI のテスト job は選択した Developer
  directory を `GITHUB_ENV` に渡し、`just xcode-version` と `just test-fast` が同じ
  Xcode を使う。
- `zig fmt --check .` は生成された `zig-pkg` 内の外部コードまで検査するため、
  `git ls-files` で追跡中の Zig ファイルだけを検査・整形するようにした。
- `test.yml` の PR チェックを `just test-fast` と `just lint` に移行した。リリース
  workflow の全面見直しは行っていない。

## 検証結果

- `just --list --unsorted`、`just`、`just --fmt --check`、各 recipe の dry-run が成功。
- `just test-filter inputLineTextBeforeCursor` が成功。
- `just build-core` が成功。
- `just test-fast` が成功。
- `just lint` が成功（Zig fmt、SwiftLint 176 ファイル）。
