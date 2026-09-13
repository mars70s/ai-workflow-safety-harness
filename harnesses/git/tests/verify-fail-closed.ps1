[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $RepositoryRoot 'src\git-safety-harness.ps1'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "git-safety-harness-test-$Timestamp"
$RepoPath = Join-Path $TestRoot 'repo'
$FakeBinPath = Join-Path $TestRoot 'fake-bin'
$RemotePath = Join-Path $TestRoot 'remote.git'
$WrapperPath = Join-Path $TestRoot 'wrappers'
$EvidencePath = Join-Path $TestRoot 'evidence'
$ShellLabel = if ($PSEdition -eq 'Core') { 'PS7' } else { 'PS5.1' }
$ShellExecutable = if ($PSEdition -eq 'Core') {
    Join-Path $PSHOME 'pwsh.exe'
}
else {
    Join-Path $PSHOME 'powershell.exe'
}

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArgs
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    $Output = @()
    $ExitCode = $null
    try {
        $ErrorActionPreference = 'Continue'
        $Output = @(& git @GitArgs 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    if ($ExitCode -ne 0) {
        $Diagnostic = @(
            $Output |
                ForEach-Object { $_.ToString() } |
                Where-Object { $_ -and $_.Trim() }
        ) -join [Environment]::NewLine
        if ($Diagnostic) {
            throw "Test setup git command failed: git $($GitArgs -join ' ')`n$Diagnostic"
        }
        throw "Test setup git command failed: git $($GitArgs -join ' ')"
    }
    return $Output
}

function Write-TestFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $Path = Join-Path $RepoPath $RelativePath
    $Parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function ConvertTo-PowerShellLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return "'$(($Value -replace "'", "''"))'"
}

function New-HarnessWrapper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Case,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedFiles,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedStagedFiles,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPushUrl
    )

    $WrapperFile = Join-Path $WrapperPath ("{0}.ps1" -f $Case.ToLowerInvariant().Replace('_', '-'))
    $Lines = @(
        "`$HarnessPath = $(ConvertTo-PowerShellLiteral -Value $SourcePath)"
        '$HarnessParams = @{'
        "    ExpectedRootPath = $(ConvertTo-PowerShellLiteral -Value $ExpectedRoot)"
        '    AllowedFiles = @('
    )
    foreach ($AllowedFile in $AllowedFiles) {
        $Lines += "        $(ConvertTo-PowerShellLiteral -Value $AllowedFile)"
    }
    $Lines += @(
        '    )'
        '    AllowedStagedFiles = @('
    )
    foreach ($AllowedStagedFile in $AllowedStagedFiles) {
        $Lines += "        $(ConvertTo-PowerShellLiteral -Value $AllowedStagedFile)"
    }
    $Lines += @(
        '    )'
        "    ExpectedBranch = 'main'"
        "    ExpectedPushUrl = $(ConvertTo-PowerShellLiteral -Value $ExpectedPushUrl)"
        "    Remote = 'origin'"
        '}'
    )
    if ($Case -eq 'CASE_5') {
        $Lines += @(
            '$GitleaksTestCommand = Get-Command gitleaks -CommandType Application -ErrorAction SilentlyContinue'
            'if ($GitleaksTestCommand) {'
            '    Write-Output "GITLEAKS_TEST_SOURCE=$($GitleaksTestCommand.Source)"'
            '}'
        )
    }
    $Lines += @(
        '& $HarnessPath @HarnessParams'
        'exit $LASTEXITCODE'
    )
    Set-Content -LiteralPath $WrapperFile -Value $Lines -Encoding UTF8
    return $WrapperFile
}

function Reset-Scenario {
    foreach ($Path in @($RepoPath, $RemotePath)) {
        if (Test-Path -LiteralPath $Path) {
            Get-ChildItem -LiteralPath $Path -Force |
                Remove-Item -Recurse -Force -ErrorAction Stop
        }
        else {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }

    Invoke-TestGit -GitArgs @('init', $RepoPath) | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'config', '--local', 'user.name', 'Harness Test') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'config', '--local', 'user.email', 'harness-test@example.invalid') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'branch', '-M', 'main') | Out-Null
    Invoke-TestGit -GitArgs @('init', '--bare', $RemotePath) | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'remote', 'add', 'origin', $RemotePath) | Out-Null

    $RemoteUrl = (Invoke-TestGit -GitArgs @('-C', $RepoPath, 'remote', 'get-url', '--push', 'origin') | Select-Object -First 1).ToString().Trim()
    return $RemoteUrl
}

function Commit-TestBaseline {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    Invoke-TestGit -GitArgs (@('-C', $RepoPath, 'add') + $Paths) | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'commit', '-m', 'test: establish baseline') | Out-Null
}

function ConvertTo-ProcessArgument {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-HarnessProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Case,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedFiles,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedStagedFiles,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPushUrl,

        [string]$PathOverride
    )

    $WrapperFile = New-HarnessWrapper `
        -Case $Case `
        -ExpectedRoot $ExpectedRoot `
        -AllowedFiles $AllowedFiles `
        -AllowedStagedFiles $AllowedStagedFiles `
        -ExpectedPushUrl $ExpectedPushUrl

    $ArgumentTokens = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $WrapperFile
    )

    $Psi = New-Object System.Diagnostics.ProcessStartInfo
    $Psi.FileName = $ShellExecutable
    $Psi.Arguments = ($ArgumentTokens | ForEach-Object { ConvertTo-ProcessArgument -Value $_ }) -join ' '
    $Psi.WorkingDirectory = $WorkingDirectory
    $Psi.UseShellExecute = $false
    $Psi.CreateNoWindow = $true
    $Psi.RedirectStandardOutput = $true
    $Psi.RedirectStandardError = $true
    if ($PathOverride) {
        $Psi.EnvironmentVariables['Path'] = $PathOverride
    }
    try {
        $Psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $Psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        # Keep the platform default if unavailable.
    }

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $Psi
    [void]$Process.Start()
    $Stdout = $Process.StandardOutput.ReadToEnd()
    $Stderr = $Process.StandardError.ReadToEnd()
    $Process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $Process.ExitCode
        Stdout = $Stdout
        Stderr = $Stderr
        Combined = "$Stdout`n$Stderr"
        Command = "$($Psi.FileName) $($Psi.Arguments)"
        WorkingDirectory = $WorkingDirectory
        WrapperFile = $WrapperFile
    }
}

function Assert-CaseResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Case,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedMarker,

        [string]$RequiredMarker,

        [string]$AdditionalEvidence
    )

    $HasForbiddenPass = $Result.Combined -match 'PASS: Secret Scan OK'
    $HasExpectedMarker = $Result.Combined -match [regex]::Escape($ExpectedMarker)
    $HasRequiredMarker = $true
    if ($RequiredMarker) {
        $HasRequiredMarker = $Result.Combined -match [regex]::Escape($RequiredMarker)
    }
    $Pass = $Result.ExitCode -eq 1 -and $HasExpectedMarker -and $HasRequiredMarker -and -not $HasForbiddenPass

    $RequiredMarkerForLog = if ($RequiredMarker) { $RequiredMarker } else { 'NONE' }
    $ResultText = @(
        "SHELL: $ShellLabel / $($PSVersionTable.PSVersion.ToString())"
        "CASE: $Case"
        "CHILD_COMMAND: $($Result.Command)"
        "WORKING_DIRECTORY: $($Result.WorkingDirectory)"
        "CHILD_EXIT_CODE: $($Result.ExitCode)"
        'EXPECTED_EXIT_CODE: non-zero'
        'STDOUT_BEGIN'
    ) -join "`r`n"
    $ResultText += "`r`n$($Result.Stdout)"
    if (-not $ResultText.EndsWith("`n")) { $ResultText += "`r`n" }
    $ResultText += @(
        'STDOUT_END'
        'STDERR_BEGIN'
    ) -join "`r`n"
    $ResultText += "`r`n$($Result.Stderr)"
    if (-not $ResultText.EndsWith("`n")) { $ResultText += "`r`n" }
    $ResultText += @(
        'STDERR_END'
        'COMBINED_OUTPUT_BEGIN'
    ) -join "`r`n"
    $ResultText += "`r`n$($Result.Combined)"
    if (-not $ResultText.EndsWith("`n")) { $ResultText += "`r`n" }
    $ResultText += @(
        'COMBINED_OUTPUT_END'
        "EXPECTED_MARKER: $ExpectedMarker"
        "REQUIRED_MARKER: $RequiredMarkerForLog"
        'FORBIDDEN_MARKER: PASS: Secret Scan OK'
        "HAS_EXPECTED_MARKER: $([bool]$HasExpectedMarker)"
        "HAS_REQUIRED_MARKER: $([bool]$HasRequiredMarker)"
        "HAS_FORBIDDEN_PASS: $([bool]$HasForbiddenPass)"
        "RUNNER_PASS_EXPRESSION: $([bool]$Pass)"
        "TEST_RESULT: $(if ($Pass) { 'PASS' } else { 'FAIL' })"
    ) -join "`r`n"
    if ($AdditionalEvidence) {
        $ResultText += "`r`nADDITIONAL_EVIDENCE_BEGIN`r`n$AdditionalEvidence`r`nADDITIONAL_EVIDENCE_END"
    }
    $CaseFile = Join-Path $EvidencePath ("case-{0}.txt" -f $Case.Substring($Case.Length - 1, 1).PadLeft(2, '0'))
    [System.IO.File]::WriteAllText($CaseFile, $ResultText, [System.Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        Case = $Case
        Shell = $PSVersionTable.PSVersion.ToString()
        ExitCode = $Result.ExitCode
        ForbiddenPass = $HasForbiddenPass
        Verdict = if ($Pass) { 'PASS' } else { 'FAIL' }
    }
}

$Passed = $false
try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $RepoPath, $FakeBinPath, $WrapperPath, $EvidencePath -Force | Out-Null

    $Results = @()

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Write-TestFile -RelativePath 'public/article.html' -Content '<p>Test article</p>'
    Commit-TestBaseline -Paths @('docs/article.md', 'public/article.html')
    Write-TestFile -RelativePath 'config/new-secret.env' -Content 'DUMMY_TEST_VALUE=not-a-credential'
    $Results += Assert-CaseResult -Case 'CASE_1' -Result (Invoke-HarnessProcess `
        -Case 'CASE_1' `
        -WorkingDirectory (Join-Path $RepoPath 'docs') `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md', 'public/article.html') `
        -AllowedStagedFiles @('docs/article.md', 'public/article.html') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_WRITE_SET' `
        -RequiredMarker 'config/new-secret.env'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'config/app.json' -Content '{"mode":"test"}'
    Commit-TestBaseline -Paths @('config/app.json')
    New-Item -ItemType Directory -Path (Join-Path $RepoPath 'docs') -Force | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'mv', 'config/app.json', 'docs/article.md') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'add', '-A') | Out-Null
    $RenamePaths = @(Invoke-TestGit -GitArgs @('-C', $RepoPath, 'diff', '--cached', '--no-renames', '--name-only'))
    $RenameVisible = ($RenamePaths -contains 'config/app.json') -and ($RenamePaths -contains 'docs/article.md')
    $Results += Assert-CaseResult -Case 'CASE_2' -Result (Invoke-HarnessProcess `
        -Case 'CASE_2' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_WRITE_SET' `
        -RequiredMarker 'config/app.json' `
        -AdditionalEvidence ("git diff --cached --no-renames --name-only`r`n" + ($RenamePaths -join "`r`n"))
    if (-not $RenameVisible) {
        $Results[-1].Verdict = 'FAIL'
    }

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $OriginalPath = $env:Path
    $GitDirectory = Split-Path -Parent (Get-Command git -CommandType Application -ErrorAction Stop).Source
    $Results += Assert-CaseResult -Case 'CASE_3' -Result (Invoke-HarnessProcess `
        -Case 'CASE_3' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl `
        -PathOverride $GitDirectory) `
        -ExpectedMarker 'GSH_STOP_GITLEAKS_UNAVAILABLE'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $InvalidRoot = Join-Path $TestRoot 'does-not-exist'
    $Results += Assert-CaseResult -Case 'CASE_4' -Result (Invoke-HarnessProcess `
        -Case 'CASE_4' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $InvalidRoot `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_ROOT_RESOLUTION'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $DummyGitleaksPath = Join-Path $FakeBinPath 'gitleaks.exe'
    [System.IO.File]::WriteAllBytes($DummyGitleaksPath, [byte[]]@())
    $Results += Assert-CaseResult -Case 'CASE_5' -Result (Invoke-HarnessProcess `
        -Case 'CASE_5' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl `
        -PathOverride "$FakeBinPath;$OriginalPath") `
        -ExpectedMarker 'GSH_STOP_GITLEAKS_EXECUTION' `
        -RequiredMarker "GITLEAKS_TEST_SOURCE=$DummyGitleaksPath"

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'checkout', '--detach', 'HEAD') | Out-Null
    $Results += Assert-CaseResult -Case 'CASE_6' -Result (Invoke-HarnessProcess `
        -Case 'CASE_6' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_GIT'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $AdditionalPushUrl = Join-Path $TestRoot 'alternate.git'
    Invoke-TestGit -GitArgs @(
        '-C',
        $RepoPath,
        'remote',
        'set-url',
        '--add',
        '--push',
        'origin',
        $AdditionalPushUrl
    ) | Out-Null
    $Results += Assert-CaseResult -Case 'CASE_7' -Result (Invoke-HarnessProcess `
        -Case 'CASE_7' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_PUSH_URL'

    $NonRepositoryPath = Join-Path $TestRoot 'not-a-repository'
    New-Item -ItemType Directory -Path $NonRepositoryPath -Force | Out-Null
    $Results += Assert-CaseResult -Case 'CASE_8' -Result (Invoke-HarnessProcess `
        -Case 'CASE_8' `
        -WorkingDirectory $NonRepositoryPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_ROOT'

    $Results | Format-Table -AutoSize
    $FalsePass = @($Results | Where-Object { $_.ForbiddenPass -eq $true }).Count -gt 0
    $Passed = (@($Results | Where-Object { $_.Verdict -ne 'PASS' }).Count -eq 0) -and -not $FalsePass
    if ($Passed) {
        Write-Output 'FALSE_PASS_OBSERVED=NO'
        Write-Output 'FINAL_RESULT=PASS'
        exit 0
    }

    Write-Output 'FALSE_PASS_OBSERVED=YES_OR_UNEXPECTED_RESULT'
    Write-Error 'FINAL_RESULT=FAIL'
    exit 1
}
finally {
    # Retain test-owned evidence and temporary repository for review.
}
