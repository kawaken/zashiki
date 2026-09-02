# Worktree Statusのホバーツールチップ

## 目的

Issue #129の対応として、狭いWorktree Statusサイドパネルのアイコン中心の表示を維持しながら、ホバー時に各状態の意味と詳細を確認できるようにする。cleanupボタンが無効な場合も、無効化理由をtooltipで説明する。

## 実装方針

- GwWorktreeに状態ごとのtooltip文言を集約し、rawなgwの値（未知の値を含む）を人間が読める表現へ変換する。
- Git状態、agentのprovider/lifecycle/activity、upstreamとの差分、PR番号/タイトル/state、cleanup判定/reason、ロック状態を対応するアイコンまたは表示へ設定する。
- cleanupはrecommended/review/keep/未知の値をすべてアイコン表示し、各状態の理由をtooltipに含める。
- cleanupボタンは、削除推奨件数が0件の場合に「削除推奨なし」と「確認が必要だが自動削除対象なし」を件数に応じて案内する。破壊的操作の確認ダイアログとgw cleanの挙動は変更しない。
- 表示内容の変換はSwiftUIの外からテストできる純粋なcomputed propertyとして実装する。

## 検証

- GwSchemaTestsに各tooltipの文言と未知値・エラー状態のケースを追加する。
- just test-fastまたは対象macOSテストでWorktree Status関連テストを実行する。
- just lintとgit diff --checkを実行する。
- 実機でのホバー表示はCIでは確認できないため、PRに未検証事項として記録する。

## 実装結果

- tooltip文言をGwWorktreeのcomputed propertyへ集約し、branch/HEAD、Git状態、upstream差分、agent、PR、ロック、cleanupの詳細を表示するようにした。
- status_errorは警告アイコンとエラー内容で表示し、agent providerがない場合や未知の値でも状態を確認できる汎用アイコンを表示するようにした。
- cleanupのkeepと未知のrecommendationにもアイコンを追加し、判定理由をtooltipに含めた。
- cleanupボタンのtooltipを件数に応じて切り替え、「削除推奨なし」と「確認が必要だが自動削除対象なし」を区別した。
- tooltip整形の正常系・未知値・Git状態エラーをGwSchemaTestsで検証した。

## 検証結果

- xcodebuild build: 成功
- just test-fast: 成功
- just lint: 成功（Swift 182ファイル、違反0）
- 実機でのマウスホバー表示と、無効化されたcleanupボタン上でのtooltip表示は未確認。
