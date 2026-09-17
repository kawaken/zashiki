# MarkdownプレビューでFrontMatterをテーブル表示する

対応Issue: #211

## 現状の問題

Markdownプレビュー(`macos/Sources/Features/Markdown Preview/`)は、ファイルを
読み込んだ生の文字列(`MarkdownPreviewModel.content`)をそのまま
`Textual`パッケージの`StructuredText(markdown:)`に渡している(
`MarkdownPreviewPane.swift`)。

`Textual`はFoundationの`AttributedString(markdown:)`でパースしており、YAML
FrontMatter(`---`で囲まれたメタデータ)の概念を持たない。そのため先頭と
閉じの`---`はCommonMarkのthematic break(または前後関係次第でsetext見出し
区切り)として解釈され、間の`key: value`行は普通の段落として表示されて
しまう。つまり無視されるのではなく、崩れた見た目で表示される。

## 方針

FrontMatterのパースと除去はZashiki側で行い、Textual(外部SwiftPM依存)には
手を入れない。`MarkdownPreviewPane`が`StructuredText`に渡す前に、生の
Markdown文字列からFrontMatter部分を抜き出し、キー・バリューのテーブルとして
別のSwiftUI Viewで表示する。残りの本文だけを従来どおり`StructuredText`に渡す。

### FrontMatterのパース仕様(スコープを絞る)

Issueの要望は「FrontMatterだったらキーと値のテーブル表示にしたい」であり、
汎用YAMLパーサーの実装は求められていない。以下のシンプルな仕様に絞る。

- ファイル先頭の1行目が`---`単独行の場合のみFrontMatter候補として扱う。
- それ以降、次に現れる`---`単独行までをFrontMatterブロックとする。
- 閉じの`---`が見つからない場合はFrontMatterとして扱わず、元の文字列を
  そのまま`StructuredText`に渡す(現状と同じ挙動にフォールバック)。
- ブロック内は`key: value`の形式の行だけを1エントリとして拾う。
  - 値の前後の空白はtrimする。
  - 値が`"..."`または`'...'`で囲まれている場合は外側のクォートだけを外す。
  - ネストしたマップ、配列(`- foo`)、複数行文字列などはサポートしない。
    該当行は無視する(クラッシュや例外にはしない)。
- 拾えたエントリが1つもない場合はFrontMatterセクション自体を表示しない
  (空のテーブルを出さない)。
- FrontMatterブロックの後に続く残りの文字列を本文として返す。

この仕様は独立した純粋関数として実装し、Viewから切り離してユニットテスト
できるようにする。

### 実装ファイル

- 新規: `macos/Sources/Features/Markdown Preview/MarkdownFrontMatter.swift`
  - `MarkdownFrontMatter.parse(_ text: String) -> (frontMatter: [(key: String, value: String)], body: String)`
    相当の純粋関数(または同等のstruct)。
- 新規: `macos/Sources/Features/Markdown Preview/FrontMatterTableView.swift`
  - key/valueを2列で並べるSwiftUIの`Grid`ベースのView。
- 変更: `MarkdownPreviewPane.swift`
  - `content`内で`model.content`を`MarkdownFrontMatter.parse`にかけ、
    FrontMatterがあれば`FrontMatterTableView`を`StructuredText`の上に表示し、
    `StructuredText`にはパース後の本文だけを渡す。
- 新規: Swiftのユニットテストに`MarkdownFrontMatter`のパースケースを追加
  (正常系、閉じタグなし、空FrontMatter、クォート値、ネスト行の無視)。

### スコープ外

- 汎用YAML(ネスト、配列、複数行文字列、アンカー等)への対応。
- `...`によるYAMLドキュメント終端記法への対応。
- FrontMatterの編集機能。

## 完了条件

- FrontMatter付きMarkdownファイルをプレビューすると、キー・バリューの
  テーブルがヘッダとして表示され、本文はこれまでどおりレンダリングされる。
- FrontMatterがない、または閉じタグがない不完全な`---`ブロックを含む
  ファイルは、現状と同じ表示(崩れた見た目も含め現状維持)のままになる。
- `MarkdownFrontMatter`のパースロジックにユニットテストがある。
