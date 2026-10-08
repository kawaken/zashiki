# AboutダイアログからBuild表示を削除

## Issue

- #256

## 調査結果

- `AboutView`は`CFBundleVersion`をBuildとして取得し、Version/Commitと並べて表示している。
- Issueの要望はこのBuild表示をなくすこと。

## 方針

- About画面からBuild値の取得とBuild行だけを削除する。
- Version、Commit、その他のAbout画面の内容は維持する。

## 確認

- `just lint`
- `just test-fast`
- 差分を確認し、About画面のBuild行以外に影響がないことを確認する。

## 実装結果

- `AboutView`からBuild値の読み込みとBuild行を削除した。
- VersionとCommitの行は維持した。

## 検証結果

- `just lint`: 成功（Swift 192ファイル、違反なし）。
- `git diff --check`: 成功。
- `just test-fast`: Xcodeアプリビルド成功。その後Zig側コマンドが終了せず停止したため、コマンド全体の完走は未確認。
