# リリースworkflowの単一導線化

- **Issue**: [#184](https://github.com/kawaken/zashiki/issues/184)

## 背景

タグ作成用の`tag-release.yml`と、テスト・build・公開用の`release.yml`が
分かれていた。`GITHUB_TOKEN`でpushしたタグから別workflowを起動できない
制約に対応するための構成だったが、`release.yml`を手動でmain refから
実行でき、入力したversionだけをRC名にできるため、実際のbuild commitと
Release名がずれる余地があった。実際に`v0.3.1-rc.2`で、タグ版のfull test
失敗後にmain版がRC名で公開された。

## 方針

`release.yml`を唯一の手動入口にして、タグをリリース対象の正とする。

- `version`から正式版タグ（`vX.Y.Z`）を生成する
- RCチェック時は、同じバージョンの既存RCタグを調べ、最大番号の次（`rc.1`、`rc.2`…）を生成する
- 生成したタグがリモートに存在する場合はそのタグのcommitをcheckoutする
- 生成したタグがリモートに存在しない場合はmainのHEADにローカルタグを作成する
- full testとbuildが成功した後だけPATで新規タグをpushする
- 既存タグの場合はタグpushせず、同じcommitから公開する
- Release名、zip名、appcast URL、prerelease判定は決定済みのタグから生成する
- `CHANGELOG.md`もタグをcheckoutした状態から抽出する

テスト前に新規タグをリモートへpushしないことで、テスト失敗時に未検証の
タグを残さない。指定されたタグ名が存在しない場合は、入力された名前を
mainへ付ける仕様とするため、形式検証はworkflow内で行う。

## 実装内容

- `tag-release.yml`を削除
- `release.yml`からタグpushトリガーを削除
- `release.yml`に既存タグ利用・新規タグ作成の分岐を追加
- 新規タグpushに既存の`GH_PAT_PR_CREATE` secretを使用
- リリース成果物の全ての名前・URLを`RELEASE_TAG`へ統一

## 検証

- YAML構文検証
- `git diff --check`
- 既存タグ経路はローカルでタグcommitのcheckoutとversion値を確認
- 新規タグ経路はリモートへpushせず、ローカルタグでbuild設定がタグを
  検出できることを確認
