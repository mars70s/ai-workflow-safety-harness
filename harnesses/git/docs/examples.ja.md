# Git Safety Harness — Examples

[English](examples.md) | [日本語](examples.ja.md)

[Getting Started](getting-started.ja.md)で説明した6つの設定を、よくある作業パターンに当てはめた例です。値はすべて合成的な例なので、実際のリポジトリに合わせて置き換えてください。

## Example 1 — 1ファイルだけ変更

### 目的

`README.md`だけを変更し、次のcommit候補にもそのファイルだけをステージする場合です。

### 設定

| 設定 | 値 |
| --- | --- |
| `ExpectedRootPath` | `C:\work\example-project` |
| `AllowedFiles` | `README.md` |
| `AllowedStagedFiles` | `README.md` |
| `ExpectedBranch` | `main` |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |

### 現在の状態

`README.md`だけが変更され、`README.md`だけがステージされています。

### Harnessの判断

PASS。Repository Root、Write Set、Stage Set、Branch、Push URL、Secret Scanがすべて受け入れられれば、正常に完了します。

### なぜそうなるか

Write SetとStage Setの両方に、観測されたパスが含まれているためです。`README.md`以外が変更またはステージされるとSTOPになります。

## Example 2 — 2ファイルの文書更新

### 目的

文書本体と公開用HTMLを一緒に更新する場合です。

### 設定

| 設定 | 値 |
| --- | --- |
| `ExpectedRootPath` | `C:\work\example-project` |
| `AllowedFiles` | `docs/article.md`、`public/article.html` |
| `AllowedStagedFiles` | `docs/article.md`、`public/article.html` |
| `ExpectedBranch` | `main` |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |

### 現在の状態

2つのファイルだけが変更され、2つともステージされています。

### Harnessの判断

PASS。2つの変更と2つのstage済みパスが、それぞれの許可リストに一致すれば受け入れられます。

### なぜそうなるか

Write SetとStage Setの両方で、予定した2ファイルだけを許可しているためです。

## Example 3 — 変更は2ファイル、stageは1ファイル

### 目的

2つのファイルを変更しても、次のcommit候補にするのは1つだけにする場合です。

### 設定

| 設定 | 値 |
| --- | --- |
| `AllowedFiles` | `docs/article.md`、`public/article.html` |
| `AllowedStagedFiles` | `docs/article.md` |
| `ExpectedBranch` | `main` |

`ExpectedRootPath`、`Remote`、`ExpectedPushUrl`も対象リポジトリに合わせて設定します。

### 現在の状態

両方のファイルが変更され、`docs/article.md`だけがステージされています。

### Harnessの判断

PASS。`public/article.html`は変更されていますが、ステージされていないためStage Setには入りません。

### なぜそうなるか

`AllowedFiles`は変更を許可する範囲、`AllowedStagedFiles`はステージを許可する範囲です。2つの範囲を分けることで、変更の確認とcommit候補の確認を別々に行えます。

## Example 4 — コードとテストを一緒に変更

### 目的

実装ファイルと、そのテストファイルを同じcommit候補にする場合です。

### 設定

| 設定 | 値 |
| --- | --- |
| `AllowedFiles` | `src/example.ps1`、`tests/example.Tests.ps1` |
| `AllowedStagedFiles` | `src/example.ps1`、`tests/example.Tests.ps1` |
| `ExpectedBranch` | `main` |

`ExpectedRootPath`、`Remote`、`ExpectedPushUrl`も対象リポジトリに合わせて設定します。

### 現在の状態

2つのファイルが変更され、2つともステージされています。

### Harnessの判断

PASS。許可されたコードとテストだけがWrite SetとStage Setに含まれていれば、受け入れられます。

### なぜそうなるか

Harnessは、ファイルの組み合わせが意味的に正しいかまでは判断しません。ここで確認できるのは、あらかじめ決めたパスの範囲とGit状態の一致です。

## Example 5 — ブランチ違いでSTOP

### 目的

正しいリポジトリにいるが、作業ブランチが違う場合を確認する例です。

### 設定

| 設定 | 値 |
| --- | --- |
| `ExpectedBranch` | `main` |
| 現在のブランチ | `feature/test` |

### Harnessの判断

STOP。symbolic branchは解決できますが、`ExpectedBranch`と一致しません。

### なぜそうなるか

別branchでの作業を、main向けの作業として後続操作へ進めないためです。detached HEADの場合も、期待するsymbolic branchを確認できないためSTOPになります。

## Example 6 — push URL違いでSTOP

### 目的

remote名は正しいが、そこに設定されたpush URLが別のリポジトリを指している場合です。

### 設定

| 項目 | 値 |
| --- | --- |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |
| 実際のpush URL | `git@github.com:example/other-project.git` |

### Harnessの判断

STOP。指定したremoteのpush URLが、期待値と完全一致しません。

### なぜそうなるか

Harnessはpushを実行しませんが、後続操作の前に設定されたpush先を確認します。複数のpush URLがある場合も、1つだけという条件に違反するためSTOPです。

## Example 7 — 予定外ファイルでSTOP

### 目的

AIの作業で、許可していないファイルまで変更された場合です。

### 設定

| 設定 | 値 |
| --- | --- |
| `AllowedFiles` | `docs/article.md`、`public/article.html` |
| 観測された追加の変更 | `README.md` |

### Harnessの判断

STOP。`README.md`が`AllowedFiles`に含まれていません。

### なぜそうなるか

Write Setには、追跡済みだが未ステージの変更、ステージ済みの変更、Gitでignoreされていない未追跡パスが含まれます。ステージされていない予定外ファイルも、Write Setで検出されます。

## Example 8 — stage前レビュー

### 目的

変更内容を確認してからstageする運用です。

### 設定

| 設定 | 値 |
| --- | --- |
| `AllowedFiles` | `docs/article.md`、`public/article.html` |
| `AllowedStagedFiles` | `docs/article.md` |

### 現在の状態

2つのファイルは変更されていますが、まだどちらもステージされていません。

### Harnessの判断

PASS。Stage Setが空であれば、許可されたStage Setから外れるパスはありません。後でステージする場合は、`docs/article.md`だけが許可されたcommit候補です。

### なぜそうなるか

`AllowedStagedFiles`は、少なくとも1つのファイルをステージしなければならないという指定ではありません。現在ステージされているパスが、許可された集合に含まれるかを確認します。空のStage Setを別の形式で表現する場合は、使用するPowerShell callerでのparameter bindingを事前に確認してください。
