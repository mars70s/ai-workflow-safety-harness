# Git Safety Harness

[English](README.md) | [日本語](README.ja.md)

選択したGitワークフローの境界を検査する、ソフトなfail-closed型Safety Harnessのリファレンス実装です。現在のステータスは**PRE-PUBLICATION REFERENCE IMPLEMENTATION**です。

HarnessはLayer 2のワークフロー制御です。sandboxでも独立したsecurity boundaryでもなく、本番環境での安全性を保証するものでもありません。別のLayer 3制御がアクセスを制約しない限り、raw Git、shell、API、filesystemなどの直接アクセスでバイパスされる可能性があります。

関連文書: [Getting Started](docs/getting-started.ja.md) | [Validation Record](docs/validation.ja.md) | [Design](docs/design.md) | [Limitations](docs/limitations.md) | [MIT License](../../LICENSE)

Repository Rootを確定した後、ポリシー確認に使うGit操作は、解決済みのルートを指定した`git -C <resolved-root> ...`で実行します。ルートが未確定である最初のルート検出だけは、この規則の例外（bootstrap exception）です。Write Setは、実装どおり、追跡済みだが未ステージの変更、ステージ済みの変更、Gitでignoreされていない未追跡パスから導出されます。許可リストとの比較では大文字と小文字を区別します。

## 確認する7つの通過条件（gate）

現在のテストでは、次の通過条件を直接検査します。

1. Repository Root: リポジトリ外での実行、ルート解決の失敗、別の有効なリポジトリとの不一致を確認します。
2. Write Set: 対象外の未追跡ファイル、renameで現れる旧パスと新パス、パスの大文字・小文字だけが異なる場合の処理を確認します。
3. Stage Set: Write Setとは独立して到達できる、ステージ済みファイルの失敗を確認します。
4. Branch: detached HEADと、期待したブランチとの不一致を確認します。
5. Push URL: 複数のpush URL、1つだけ設定された不一致push URL、正常系での正確な単一一致を確認します。
6. Secret Scan: Gitleaksが見つからない場合、見つかっても実行できない場合、実際にGitleaksがsecretを検出した場合、Gitleaksの検査が成功する場合を確認します。
7. fail-closedでSTOPする動作を確認します。

正常系テストでは、次の3つを直接検査します。変更のない正常なワークフロー、最初は未ステージの許可済み変更で改行コードの警告が発生する条件（M2）、および空でない許可済みのstaged diffを実際のGitleaksが正常に検査する場合です。これは限定的な検証範囲であり、Git、PowerShell、Gitleaks、またはすべての境界事例を網羅的にテストするものではありません。

## 検証に使用した環境

- Git 2.54.0.windows.1
- PowerShell 7.6.5
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

fail-closed suiteは、PowerShell 7とWindows PowerShell 5.1でそれぞれ14ケースに合格しています: **28/28 PASS**。正常系テストも、各シェルで3ケース、実際のGitleaks 8.30.1を使用して合格しています: **6/6 PASS**。Success Case 2では、Harnessに関係する未ステージ変更の警告を確認した後、staged diffが空になる場合があります。Success Case 3では、空でないstaged diffを明示的に検査します。これは検証環境とテスト結果であり、すべての環境での互換性を保証するものではありません。

## 呼び出し契約

Harnessスクリプトで使用する重要なパラメーターは次のとおりです。

- `-ExpectedRootPath`: 期待するリポジトリのルート。
- `-AllowedFiles`: 許可するWrite Set（完全一致。大文字と小文字を区別）。
- `-AllowedStagedFiles`: 許可するStage Set（完全一致。大文字と小文字を区別）。
- `-ExpectedBranch`: 期待するsymbolic branch。
- `-ExpectedPushUrl`: 期待するpush URL（完全一致）。
- `-Remote`: 検査対象のremote。省略時は`origin`。

Gitleaksは外部依存です。Harnessは`Get-Command gitleaks -CommandType Application`で`gitleaks`というApplicationを発見し、staged scanを呼び出します。Harnessスクリプトのパスは、呼び出し側で独立に解決してください。対象リポジトリのルートは、これとは別のパラメーターおよび状態です。検証済みの呼び出し境界は、PowerShellのオブジェクトを作成し、`[string[]]`の`AllowedFiles`を含むparameter hashtableを作り、splattingでHarnessを呼び出し、呼び出しの失敗とchild exit codeをfail-closedで伝えるPowerShell wrapperまたはcallerです。

```powershell
$ErrorActionPreference = 'Stop'
$HarnessPath = '<path-to-harness>\harnesses\git\src\git-safety-harness.ps1'
[string[]]$AllowedFiles = @('docs/article.md', 'public/article.html')
[string[]]$AllowedStagedFiles = @('docs/article.md', 'public/article.html')
$HarnessParams = @{
  ExpectedRootPath = (Get-Location).Path
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

このwrapper/splatting形式は、複数ファイルを扱う検証済みの呼び出し方法です。明示的なerror boundaryにより、wrapperの呼び出しまたはbindingの失敗、child exit codeがmissing/nullの場合、Harnessがnon-zeroを返した場合は、いずれもexit 1になります。successful Harness executionの後だけexit 0になります。外部からの直接`-File` invocationは、`AllowedFiles`に複数の値を渡す検証済みの一般的な方法ではありません。shellからPowerShellへのarray bindingは異なり得るため、`@('a', 'b')`をnative external command-line array syntaxとして渡してはいけません。single-value parameterでbindingを理解している場合に限り、direct `-File` callを使えます。dot-sourcingと任意のin-process invocationは、完全に検証済みの呼び出し方法とは主張しません。

## Secret Scanの範囲

現在の実装は、確認済みのRepository Rootに対して`gitleaks git --staged --redact`相当を呼び出します。そのためSecret Scanは、Gitleaksが検査するstaged Git diffを対象とします。リポジトリ内の全ファイル、許可された未ステージまたは未追跡のファイル、repository historyに存在するだけのcommitted content（まだpushされていないcommitを含む）がscanされることを意味しません。完全なsecret detectionでもありません。

Gitleaksの動作は、適用されるscanner configurationやignore mechanism、Gitleaksが対応するrepository-local configurationの影響を受けます。HarnessはGitleaksの設定やignore ruleの正しさを独立には検証しません。

終了コードの扱いは保守的です。zeroの場合だけscanをsuccessfulとして受け入れ、non-zero、null、execution failureの場合はSTOPとなります。numeric exit codeだけでsecret findingとscanner/runtime errorを常に区別できるとは主張しません。

## Push contract（pushの契約）

Harnessは、指定したremoteに設定されたpush URLを検証します。後続の`git push`は実行せず、Gitの周辺設定がdefaultを供給する場合に、任意の後続pushがどのremoteやrefを使うかも独立には保証しません。後続のauthorized pushでは、意図したremoteとrefまたはbranchを明示してください。

## テスト証拠とprovenance

現在の検証では、正常系テスト中にsynthetic remote refs unchanged、global scopeのGit configuration unchanged、process-local PATH restoration、real Gitleaks execution、expected STOP/success pathsを測定しています。正常系検証で使用した、別途検証済みのGitleaks実行ファイルは8.30.1です。テストではsynthetic local remotesを使用しています。これらはbroad network monitoringではありません。Harnessのcode自体は後続のdeploymentやpush actionを実行しません。

現在ローカルで復元し検証した作業ソースを、v0.1のbaselineとして採用しました。それ以前の正確なファイルの系譜は主張しません。repositoryの実装には、先行する説明articleのcode exampleを超えるbounded correctionsとcompatibility hardeningが意図的に含まれます。

## 制限事項

Harnessはsafetyを保証せず、sandboxとして動作せず、independent security boundaryでもありません。詳細は[design.md](docs/design.md)と[limitations.md](docs/limitations.md)を参照してください。主な制限事項は、allowed file内部のsemantic mistake、correct remoteとwrong contentの組み合わせ、raw Git/shell bypass、不完全でstaged-onlyのsecret detection、選択したGit checkから見えないfilesystem change、`assume-unchanged`、`skip-worktree`、誤った状態に対するhuman approval、Git外のdeploy/API/external action、TOCTOU、path edge case、submodule、symlink、junction、environment influence、tool/version difference、configuration-dependent behaviorです。
