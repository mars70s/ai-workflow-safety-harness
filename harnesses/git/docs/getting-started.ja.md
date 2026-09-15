# Git Safety Harness — Getting Started

[English](getting-started.md) | [日本語](getting-started.ja.md)

このガイドでは、Git Safety Harnessを初めて使うための基本的な手順を示します。Safety Harnessは、AI支援の作業で「予定外の状態のまま、次の操作へ進んでしまう」ことを防ぐための確認役です。fail-closedとは、必要な条件を確認できない場合に、処理を続けずSTOPする考え方です。Layer 2は、実行前に現在の状態が事前に決めた条件と一致しているかを確認する層です。sandboxでも独立したsecurity boundaryでもありません。

## 1. このHarnessで何を確認するのか

たとえばAIに、次のように依頼したとします。

「mainブランチで、`docs/article.md`と`public/article.html`の2ファイルだけを修正したい。確認が終わったら、別途認可して`origin`へpushする。」

Git Safety Harnessは、後続操作へ進む前に、次の確認項目を確認します。

- 本当に対象のリポジトリにいるか
- 予定外のファイルが変更されていないか
- ステージ済みのファイルが予定どおりか
- ブランチが正しいか
- push先が想定どおりか
- ステージ済みの変更についてGitleaksの検査が通るか

条件が一致しなければSTOPします。

何が正しい状態かを決めるのはHarnessではなく、人間です。Harnessは、人間が事前に決めた条件と、現在のGit状態が一致しているかを確認します。

### 確認項目と設定値の対応

6つの設定と確認項目は、1対1に対応するわけではありません。Secret Scanのように、ユーザーが許可リストを渡すのではなく、Harnessの処理として自動的に実行される確認もあります。

| Harnessが確認すること | 関係する設定 | 自動実行 |
| --- | --- | --- |
| Repository Rootが期待したルートか | `ExpectedRootPath` | はい |
| Write Setが許可された範囲内か | `AllowedFiles` | はい |
| Stage Setが許可された範囲内か | `AllowedStagedFiles` | はい |
| ブランチが期待したsymbolic branchか | `ExpectedBranch` | はい |
| 指定したremoteのpush URLが期待どおりか | `Remote` + `ExpectedPushUrl` | はい |
| ステージ済み変更に対するSecret Scan | ユーザー設定なし。GitleaksをHarnessが自動実行 | はい |

## 2. 前提条件

次のツールを利用できる状態にしてください。

- Git
- PowerShell
- Gitleaks

検証に使用したバージョンは次のとおりです。

- Git 2.54.0.windows.1
- PowerShell 7.6.5
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

これらは検証で使用したバージョンであり、すべての環境での互換性を保証するものではありません。ここに記載したversion以外での互換性は未検証です。別versionで利用する場合は、本番作業へ組み込む前に、このrepositoryに含まれるtest suiteをその環境で実行して結果を確認してください。Harness自体がGit、PowerShell、Gitleaksのversionを確認するわけではありません。

## 3. Harnessの場所

Gitの実装は次のパスにあります。

`harnesses/git/src/git-safety-harness.ps1`

このスクリプトのパスは対象リポジトリのルートとは独立に解決してください。現在の作業ディレクトリがスクリプトの場所であるとは仮定しないでください。

## 4. 最初に決める6つの設定

次の6つは、Harnessに「どの状態を正しいとみなすか」を伝える設定です。値は作業対象と、今回の変更方針に合わせて人間が決めます。

| 設定 | 簡単な意味 | 人間が決めること | Harnessが確認すること | なぜ必要か | 例 | この条件でSTOPする例 |
| --- | --- | --- | --- | --- | --- | --- |
| `ExpectedRootPath` | 今回作業するリポジトリの場所 | 対象にするリポジトリを決める | 現在の作業ディレクトリから検出したRepository Rootと完全一致するか | 別のリポジトリでの誤実行を防ぐため | `C:\work\example-project` | 実際のルートが`C:\work\other-project` |
| `AllowedFiles` | 変更が存在してよいファイル | 今回変更を許可するファイルを決める | 現在のWrite Setの全パスが許可リストに含まれるか | 予定外の変更を検出するため | `docs/article.md`、`public/article.html` | 許可外の`README.md`も変更されている |
| `AllowedStagedFiles` | 次のcommit候補としてステージされていてよいファイル | 今回ステージを許可するファイルを決める | Stage Setの全パスが許可リストに含まれるか | 次のcommit候補の範囲を制限するため | `docs/article.md`、`public/article.html` | 許可していないファイルがステージされている |
| `ExpectedBranch` | 今回作業するブランチ | 作業先のブランチを決める | symbolic branchが完全一致するか | 誤ったブランチで続行しないため | `main` | `feature/test`、またはdetached HEAD |
| `Remote` | push URLを確認するremoteの名前 | 確認対象のremote名を決める。URLではない | 指定したremoteを使ってpush URLを取得する | 確認対象を取り違えないため | `origin` | 存在しないremoteや、意図しないremoteを指定する |
| `ExpectedPushUrl` | remoteに設定されているはずの正しいpush先URL | 期待するpush URLを決める | 指定remoteに、期待URLが1つだけ設定されているか | 意図しない送り先への操作を防ぐため | `git@github.com:example/example-project.git` | URLが違う、複数ある、確認できない |

`ExpectedRootPath`は、別のリポジトリで誤って実行する事故を防ぐために使います。`AllowedFiles`は、AIに2ファイルだけ変更させる予定なのに、`README.md`まで変更されていた場合を検出します。

`AllowedFiles`と`AllowedStagedFiles`は意図的に別の設定です。変更してよいファイルと、次のcommit候補としてステージしてよいファイルが同じとは限らないためです。

`Remote`はremoteの名前であり、URLではありません。たとえば`Remote`に`origin`を指定すると、Harnessは`origin`に設定されたpush URLを調べます。Harnessはpushを実行しません。

## 5. 設定例 — 2ファイルだけ変更する場合

**以下の値はすべて例です。実際のリポジトリに合わせて置き換えてください。**

AIへの依頼:

「mainブランチで、`docs/article.md`と`public/article.html`の2ファイルだけを更新したい。確認が終わったら、別途認可してoriginへpushする。」

| 設定 | 例 |
| --- | --- |
| `ExpectedRootPath` | `C:\work\example-project` |
| `AllowedFiles` | `docs/article.md`、`public/article.html` |
| `AllowedStagedFiles` | `docs/article.md`、`public/article.html` |
| `ExpectedBranch` | `main` |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |

この例でHarnessが行う確認は、次の順序です。

1. 現在の作業ディレクトリからRepository Rootを確認します。
2. 変更されているファイルを確認します。
3. ステージされているファイルを確認します。
4. 現在のブランチを確認します。
5. `origin`のpush URLを確認します。
6. ステージ済み変更をGitleaksで確認します。
7. すべて受け入れられた場合だけPASSを返します。

## 6. Write SetとStage Setの違い

Write Setは、現在の作業ツリーでHarnessが「変更がある」と認識するファイルの集合です。追跡済みだが未ステージの変更、ステージ済みの変更、Gitでignoreされていない未追跡パスが含まれます。今回触ってよいファイル以外が、いつの間にか変更されていないかを確認するための範囲です。

Stage Setは、その中でも次のcommit候補としてステージされているファイルの集合です。変更してよいファイルと、今commit候補にしてよいファイルを別々に確認します。

例:

`AllowedFiles`:

- `article.md`
- `figure.svg`

`AllowedStagedFiles`:

- `article.md`

このポリシーでは、次のようになります。

- `article.md`が変更され、ステージされている → OK
- `figure.svg`が変更されているが、ステージされていない → OK
- `figure.svg`がステージされている → STOP
- `README.md`が変更されている → STOP

## 7. wrapperを実行する

複数の許可するパスを扱う場合は、PowerShellのcallerまたはwrapperを使います。wrapperは次のことを行います。

1. Harnessの場所を指定する
2. 許可するファイルを配列にする
3. 6つの設定をhashtableにまとめる
4. Harnessを呼び出す
5. 呼び出し自体に失敗した場合もSTOP扱いにする
6. Harnessが0以外を返した場合もSTOPする
7. 成功した場合だけ0を返す

検証済みの一般的な複数ファイルinterfaceは、PowerShell object、parameter hashtable、splattingの組み合わせです。外部からの直接`-File` invocationは、複数値の`AllowedFiles`について検証済みのinterfaceではありません。

### 避ける例 — 複数値を外部`-File`呼び出しへ直接渡す

`pwsh -File <path-to-harness> -AllowedFiles @('a', 'b')`

これは検証済みの一般的な複数値インターフェースではありません。shellからPowerShellへ配列を渡す際のbindingは、意図したとおりにならない場合があります。

### 使う例

下のコードのように、PowerShell object、parameter hashtable、splattingを使う既存のwrapperを使用してください。これが複数ファイルを扱う検証済みの呼び出し方法です。

```powershell
$ErrorActionPreference = 'Stop'
$HarnessPath = '<path-to-harness>\harnesses\git\src\git-safety-harness.ps1'
[string[]]$AllowedFiles = @('docs/article.md', 'public/article.html')
[string[]]$AllowedStagedFiles = @('docs/article.md', 'public/article.html')
$HarnessParams = @{
  ExpectedRootPath = '<target-repository-root>'
  AllowedFiles = $AllowedFiles
  AllowedStagedFiles = $AllowedStagedFiles
  ExpectedBranch = 'main'
  ExpectedPushUrl = '<exact-push-url>'
  Remote = 'origin'
}
$HarnessExitCode = $null
$global:LASTEXITCODE = $null
try {
  & $HarnessPath @HarnessParams
  $HarnessExitCode = $LASTEXITCODE
}
catch {
  Write-Error $_ -ErrorAction Continue
  exit 1
}
if ($null -eq $HarnessExitCode -or $HarnessExitCode -ne 0) {
  exit 1
}
exit 0
```

このwrapperは、呼び出しの失敗、parameter bindingの失敗、child exit codeがmissingまたはnullの場合、Harnessがnon-zeroを返した場合にexit 1を返します。successful Harness executionの後だけexit 0を返します。

Gitleaksが`gitleaks`というApplicationとして見つかることを確認します。

```powershell
Get-Command gitleaks -CommandType Application
```

## 8. PASSした場合

**PASSは「作業内容が正しい」という意味ではありません。**

PASSは、人間が事前に設定した条件と、現在観測できるGit状態が一致したことを意味します。

PASSしても、次のことは証明されません。

- article内容の正しさ
- codeの意味的な正しさ
- human policy自体が正しいこと
- 後続のpushが安全に実行されること

## 9. STOPした場合

**STOPは「自動で直して続行する」という意味ではありません。**

1つ以上の必要な条件を受け入れられなかった、という意味です。出力されたSTOP markerと現在のGit状態を確認し、原因を特定してください。自動で修復して続行しないでください。必要なら人間がポリシーや作業状態を見直します。

## 10. Gitleaksが確認する範囲

Gitleaksは、ステージ済みの変更にsecretらしい情報が含まれていないかを確認する外部ツールです。このHarnessの呼び出しでは、Gitleaksはステージ済みのdiffだけを確認します。

次の内容は、単に存在するだけではこのscanの対象になりません。

- 未ステージのファイル
- 未追跡ファイル
- repository history全体
- commit済みまたは未pushの内容

ただし、未追跡ファイルがstage済みdiffに含まれる状態など、Gitのstage状態によって検査対象になる場合があります。Gitleaksの設定やignore ruleも結果に影響します。完全なsecret検出を保証するものではありません。

## 11. pushは別の操作

Harnessはpush URLの設定を確認しますが、pushは実行しません。PASSしてもpushが自動的に認可されるわけではありません。後続のpushを別途認可する場合は、意図したremoteとrefまたはbranchを明示してください。

```powershell
git push <remote> <ref-or-branch>
```

## 12. よくあるSTOP

- `README.md`も変更されている → `AllowedFiles`にないためSTOP
- ブランチが`feature/test` → `ExpectedBranch`と違うためSTOP
- detached HEAD → symbolic branchを確認できないためSTOP
- `origin`が別のリポジトリを指している → `ExpectedPushUrl`と違うためSTOP
- push URLが複数ある → 1つだけという条件に違反するためSTOP
- Gitleaksがインストールされていない、または発見できない → STOP
- Gitleaksを実行できない → STOP
- Gitleaksがnon-zeroを返す → STOP

## 13. このHarnessで防げないこと

このHarnessは「決めた手順から外れていないかを確認する仕組み」です。しかし、人間やAIがHarnessを使わずに直接Gitやshellを操作できる環境では、その直接操作そのものを禁止することはできません。

Layer 3には、たとえばserver-sideのrepository制御、protected branchやrequired checks、独立したCI-sideのsecret scan、OSやcontainer、アカウントの権限制御などが考えられます。どの制御を使うかは実行環境によって異なり、このrepositoryでは実装・検証していません。より強い独立した制限は、Layer 3のExternal Independent Enforcementに属します。このrepositoryが実装するのはLayer 2だけです。

## 14. さらに例を見る

設定を変えた場合の具体例は、[Examples](examples.ja.md)を参照してください。
