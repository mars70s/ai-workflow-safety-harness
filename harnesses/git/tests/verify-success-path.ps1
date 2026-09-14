[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitleaksPath
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $ProjectRoot 'src\git-safety-harness.ps1'
$FailClosedTestPath = Join-Path $ProjectRoot 'tests\verify-fail-closed.ps1'
$RequestedGitleaksPath = $GitleaksPath
$GitleaksDirectory = $null
$GitleaksPath = $null
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunId = [guid]::NewGuid().ToString('N')
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "git-safety-harness-success-$Timestamp-$RunId"
$RepoPath = Join-Path $TestRoot 'repo'
$RemotePath = Join-Path $TestRoot 'remote.git'
$WrapperPath = Join-Path $TestRoot 'wrappers'
$EvidencePath = Join-Path $TestRoot 'evidence'
$OriginalPath = $env:Path
$ShellVersion = $PSVersionTable.PSVersion.ToString()
$SourceHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash
$FailClosedHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $FailClosedTestPath).Hash
$M2WarningReproduced = $false

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

function Invoke-TestGitWithDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArgs
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    $DiagnosticPath = [System.IO.Path]::GetTempFileName()
    $Stdout = @()
    $Stderr = @()
    $ExitCode = $null
    try {
        $ErrorActionPreference = 'Continue'
        $Stdout = @(& git @GitArgs 2> $DiagnosticPath)
        $ExitCode = $LASTEXITCODE
        if (Test-Path -LiteralPath $DiagnosticPath -PathType Leaf) {
            $Stderr = @(Get-Content -LiteralPath $DiagnosticPath)
        }
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if (Test-Path -LiteralPath $DiagnosticPath -PathType Leaf) {
            Remove-Item -LiteralPath $DiagnosticPath -Force -ErrorAction SilentlyContinue
        }
    }

    [pscustomobject]@{
        Stdout = @($Stdout | ForEach-Object { $_.ToString() })
        Stderr = @($Stderr | ForEach-Object { $_.ToString() })
        ExitCode = $ExitCode
    }
}

function Get-SyntheticRemoteRefs {
    return @(
        Invoke-TestGit -GitArgs @(
            '-C',
            $RemotePath,
            'for-each-ref',
            '--format=%(refname) %(objectname)'
        ) |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ } |
            Sort-Object
    )
}

function Get-GlobalGitConfigSnapshot {
    $Result = Invoke-TestGitWithDiagnostics -GitArgs @('config', '--global', '--list', '--show-origin')
    if ($Result.ExitCode -eq 0) {
        return @(
            $Result.Stdout |
                ForEach-Object { $_.ToString() } |
                Sort-Object
        )
    }

    $MissingConfig = $Result.ExitCode -in @(1, 128) -and
        @($Result.Stdout | Where-Object { $_ -and $_.Trim() }).Count -eq 0 -and
        @($Result.Stderr | Where-Object { $_ -match '(?i)(unable to read config file|no such file or directory|cannot open)' }).Count -gt 0
    if ($MissingConfig) {
        return @()
    }

    throw 'Global Git configuration snapshot failed.'
}

function Compare-StringArrays {
    param(
        [string[]]$Left,
        [string[]]$Right
    )

    $LeftText = if ($null -eq $Left -or $Left.Count -eq 0) { '' } else { [System.String]::Join("`n", $Left) }
    $RightText = if ($null -eq $Right -or $Right.Count -eq 0) { '' } else { [System.String]::Join("`n", $Right) }
    return $LeftText -ceq $RightText
}

function Get-VerifiedGitleaksSource {
    $PreviousPath = $env:Path
    try {
        if ($RequestedGitleaksPath) {
            if (-not (Test-Path -LiteralPath $RequestedGitleaksPath -PathType Leaf)) {
                throw "GITLEAKS_DEPENDENCY_UNAVAILABLE: supplied path does not exist: $RequestedGitleaksPath"
            }

            $CanonicalRequestedPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RequestedGitleaksPath -ErrorAction Stop).Path)
            $RequestedDirectory = Split-Path -Parent $CanonicalRequestedPath
            $env:Path = "$RequestedDirectory;$PreviousPath"
            $Command = Get-Command gitleaks -CommandType Application -ErrorAction Stop
            $ResolvedCommandPath = [System.IO.Path]::GetFullPath($Command.Source)
            if ($ResolvedCommandPath -cne $CanonicalRequestedPath) {
                throw "GITLEAKS_PATH_MISMATCH: expected $CanonicalRequestedPath but resolved $ResolvedCommandPath"
            }

            return [pscustomobject]@{
                Path = $CanonicalRequestedPath
                Directory = $RequestedDirectory
            }
        }

        try {
            $Command = Get-Command gitleaks -CommandType Application -ErrorAction Stop
        }
        catch {
            throw "GITLEAKS_DEPENDENCY_UNAVAILABLE: gitleaks was not found through Application command discovery."
        }

        if (-not $Command.Source) {
            throw 'GITLEAKS_DEPENDENCY_UNAVAILABLE: Application command discovery returned no executable path.'
        }

        $ResolvedCommandPath = [System.IO.Path]::GetFullPath($Command.Source)
        return [pscustomobject]@{
            Path = $ResolvedCommandPath
            Directory = (Split-Path -Parent $ResolvedCommandPath)
        }
    }
    finally {
        $env:Path = $PreviousPath
    }
}

function ConvertTo-PowerShellLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return "'$(($Value -replace "'", "''"))'"
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
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'config', '--local', 'core.autocrlf', 'true') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'branch', '-M', 'main') | Out-Null
    Invoke-TestGit -GitArgs @('init', '--bare', $RemotePath) | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'remote', 'add', 'origin', $RemotePath) | Out-Null

    $PushUrls = @(
        Invoke-TestGit -GitArgs @(
            '-C',
            $RepoPath,
            'remote',
            'get-url',
            '--push',
            '--all',
            'origin'
        ) |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ }
    )
    if ($PushUrls.Count -ne 1) {
        throw "Synthetic remote did not produce exactly one push URL: $($PushUrls.Count)"
    }
    return $PushUrls[0]
}

function Commit-TestBaseline {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    Invoke-TestGit -GitArgs (@('-C', $RepoPath, 'add') + $Paths) | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'commit', '-m', 'test: establish success baseline') | Out-Null
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
        [string]$ExpectedPushUrl,

        [string]$HarnessPathOverride,

        [switch]$PreInvocationSuccess
    )

    $WrapperFile = Join-Path $WrapperPath ("{0}.ps1" -f $Case.ToLowerInvariant().Replace('_', '-'))
    $HarnessLiteral = if ($HarnessPathOverride) {
        ConvertTo-PowerShellLiteral -Value $HarnessPathOverride
    }
    else {
        ConvertTo-PowerShellLiteral -Value $SourcePath
    }
    $Lines = @(
        "`$ErrorActionPreference = 'Stop'"
        "`$HarnessPath = $HarnessLiteral"
        "`$ExpectedGitleaksPath = $(ConvertTo-PowerShellLiteral -Value $GitleaksPath)"
        '$GitleaksCommand = Get-Command gitleaks -CommandType Application -ErrorAction SilentlyContinue'
        'if (-not $GitleaksCommand -or $GitleaksCommand.Source -cne $ExpectedGitleaksPath) {'
        '    Write-Error "GITLEAKS_TEST_SOURCE_MISMATCH: $($GitleaksCommand.Source)"'
        '    exit 90'
        '}'
        'Write-Output "GITLEAKS_TEST_SOURCE=$($GitleaksCommand.Source)"'
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
    if ($PreInvocationSuccess) {
        $Lines += '& git --version | Out-Null'
    }
    $Lines += @(
        '$HarnessExitCode = $null'
        '$global:LASTEXITCODE = $null'
        'try {'
        '    & $HarnessPath @HarnessParams'
        '    $HarnessExitCode = $LASTEXITCODE'
        '}'
        'catch {'
        '    Write-Output "WRAPPER_INVOCATION_FAILURE_CAUGHT=YES"'
        '    Write-Error $_ -ErrorAction Continue'
        '    exit 1'
        '}'
        'if ($null -eq $HarnessExitCode -or $HarnessExitCode -ne 0) {'
        '    exit 1'
        '}'
        'exit 0'
    )
    Set-Content -LiteralPath $WrapperFile -Value $Lines -Encoding UTF8
    return $WrapperFile
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
        [string]$ExpectedPushUrl
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
    $Psi.EnvironmentVariables['Path'] = "$GitleaksDirectory;$OriginalPath"
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

function Assert-SuccessResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Case,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result,

        [string]$AdditionalEvidence,

        [switch]$RequireNoGitWarningData
    )

    $PassMarkers = @(
        'PASS: Repository Root OK'
        'PASS: Branch OK'
        'PASS: Push URL OK'
        'PASS: Write Set OK'
        'PASS: Stage Set OK'
        'PASS: Secret Scan OK'
    )
    $HasPassMarkers = @($PassMarkers | Where-Object { $Result.Combined -notmatch [regex]::Escape($_) }).Count -eq 0
    $HasStopMarker = $Result.Combined -match 'STOP:'
    $HasExpectedGitleaksSource = $Result.Combined -match [regex]::Escape("GITLEAKS_SOURCE=$GitleaksPath")
    $HasTestGitleaksSource = $Result.Combined -match [regex]::Escape("GITLEAKS_TEST_SOURCE=$GitleaksPath")
    $HasGitWarningAsPolicyData = $Result.Combined -match 'LF will be replaced by CRLF'
    $Pass = $Result.ExitCode -eq 0 -and $HasPassMarkers -and -not $HasStopMarker -and $HasExpectedGitleaksSource -and $HasTestGitleaksSource -and (-not $RequireNoGitWarningData -or -not $HasGitWarningAsPolicyData)

    $ResultText = @(
        "SHELL: $ShellVersion"
        "CASE: $Case"
        "CHILD_COMMAND: $($Result.Command)"
        "WORKING_DIRECTORY: $($Result.WorkingDirectory)"
        "CHILD_EXIT_CODE: $($Result.ExitCode)"
        'EXPECTED_EXIT_CODE: 0'
        'EXPECTED_GITLEAKS_PATH:'
        $GitleaksPath
        'STDOUT_BEGIN'
        $Result.Stdout.TrimEnd()
        'STDOUT_END'
        'STDERR_BEGIN'
        $Result.Stderr.TrimEnd()
        'STDERR_END'
        "HAS_PASS_MARKERS: $HasPassMarkers"
        "HAS_STOP_MARKER: $HasStopMarker"
        "HAS_HARNESS_GITLEAKS_SOURCE: $HasExpectedGitleaksSource"
        "HAS_TEST_GITLEAKS_SOURCE: $HasTestGitleaksSource"
        "REQUIRE_NO_GIT_WARNING_DATA: $([bool]$RequireNoGitWarningData)"
        "HAS_GIT_WARNING_AS_POLICY_DATA: $([bool]$HasGitWarningAsPolicyData)"
        "TEST_RESULT: $(if ($Pass) { 'PASS' } else { 'FAIL' })"
    ) -join "`r`n"
    if ($AdditionalEvidence) {
        $ResultText += "`r`nADDITIONAL_EVIDENCE_BEGIN`r`n$AdditionalEvidence`r`nADDITIONAL_EVIDENCE_END"
    }
    $CaseFile = Join-Path $EvidencePath ("{0}.txt" -f $Case.ToLowerInvariant().Replace('_', '-'))
    [System.IO.File]::WriteAllText($CaseFile, $ResultText, [System.Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        Case = $Case
        Shell = $ShellVersion
        ExitCode = $Result.ExitCode
        GitleaksSource = $GitleaksPath
        Verdict = if ($Pass) { 'PASS' } else { 'FAIL' }
    }
}

$Passed = $false
try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $RepoPath, $WrapperPath, $EvidencePath -Force | Out-Null

    $GitleaksInfo = Get-VerifiedGitleaksSource
    $GitleaksPath = $GitleaksInfo.Path
    $GitleaksDirectory = $GitleaksInfo.Directory
    $VerifiedGitleaksSource = $GitleaksInfo.Path
    Write-Output "SHELL_VERSION=$ShellVersion"
    Write-Output "GITLEAKS_RESOLVED_PATH=$VerifiedGitleaksSource"
    Write-Output "TEST_ROOT=$TestRoot"
    $GlobalGitConfigBefore = Get-GlobalGitConfigSnapshot
    $SyntheticRemoteRefsUnchanged = $true

    $ShellExecutable = if ($PSEdition -eq 'Core') {
        Join-Path $PSHOME 'pwsh.exe'
    }
    else {
        Join-Path $PSHOME 'powershell.exe'
    }

    $Results = @()

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Synthetic success article'
    Write-TestFile -RelativePath 'public/article.html' -Content '<p>Synthetic success article</p>'
    Commit-TestBaseline -Paths @('docs/article.md', 'public/article.html')
    $Case1RemoteRefsBefore = @(Get-SyntheticRemoteRefs)
    $Case1Result = Invoke-HarnessProcess `
        -Case 'SUCCESS_CASE_1' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md', 'public/article.html') `
        -AllowedStagedFiles @('docs/article.md', 'public/article.html') `
        -ExpectedPushUrl $RemoteUrl
    $Case1RemoteRefsAfter = @(Get-SyntheticRemoteRefs)
    $Case1RemoteRefsUnchanged = Compare-StringArrays $Case1RemoteRefsBefore $Case1RemoteRefsAfter
    $SyntheticRemoteRefsUnchanged = $SyntheticRemoteRefsUnchanged -and $Case1RemoteRefsUnchanged
    $Results += Assert-SuccessResult -Case 'SUCCESS_CASE_1' -Result $Case1Result `
        -AdditionalEvidence (
            "SYNTHETIC_REMOTE_REFS_BEFORE_COUNT=$($Case1RemoteRefsBefore.Count)`r`n" +
            "SYNTHETIC_REMOTE_REFS_AFTER_COUNT=$($Case1RemoteRefsAfter.Count)`r`n" +
            "SYNTHETIC_REMOTE_REFS_UNCHANGED=$Case1RemoteRefsUnchanged"
        )

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Synthetic success baseline'
    Commit-TestBaseline -Paths @('docs/article.md')
    [System.IO.File]::WriteAllText(
        (Join-Path $RepoPath 'docs/article.md'),
        "# Synthetic allowed success change`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    $M2GitProbe = Invoke-TestGitWithDiagnostics -GitArgs @('-C', $RepoPath, 'diff', '--no-renames', '--name-only')
    $M2WarningLines = @(
        $M2GitProbe.Stderr |
            Where-Object { $_ -match 'LF will be replaced by CRLF' }
    )
    $M2WarningReproduced = $M2GitProbe.ExitCode -eq 0 -and $M2WarningLines.Count -gt 0
    if (-not $M2WarningReproduced) {
        throw 'SUCCESS_CASE_2 fixture did not reproduce the expected warning on the Harness-relevant git diff command.'
    }
    $Case2RemoteRefsBefore = @(Get-SyntheticRemoteRefs)
    $SuccessCase2Result = Invoke-HarnessProcess `
        -Case 'SUCCESS_CASE_2' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl
    $Case2RemoteRefsAfter = @(Get-SyntheticRemoteRefs)
    $Case2RemoteRefsUnchanged = Compare-StringArrays $Case2RemoteRefsBefore $Case2RemoteRefsAfter
    $SyntheticRemoteRefsUnchanged = $SyntheticRemoteRefsUnchanged -and $Case2RemoteRefsUnchanged
    $Results += Assert-SuccessResult -Case 'SUCCESS_CASE_2' -Result $SuccessCase2Result `
        -AdditionalEvidence (
            "SYNTHETIC_REMOTE_REFS_BEFORE_COUNT=$($Case2RemoteRefsBefore.Count)`r`n" +
            "SYNTHETIC_REMOTE_REFS_AFTER_COUNT=$($Case2RemoteRefsAfter.Count)`r`n" +
            "SYNTHETIC_REMOTE_REFS_UNCHANGED=$Case2RemoteRefsUnchanged`r`n" +
            "M2_HARNESS_RELEVANT_COMMAND=git diff --no-renames --name-only`r`n" +
            "M2_WARNING_REPRODUCED=$M2WarningReproduced`r`n" +
            ($M2WarningLines -join "`r`n")
        ) `
        -RequireNoGitWarningData

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Synthetic staged baseline'
    Commit-TestBaseline -Paths @('docs/article.md')
    [System.IO.File]::WriteAllText(
        (Join-Path $RepoPath 'docs/article.md'),
        "# Synthetic non-empty staged change`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'add', 'docs/article.md') | Out-Null
    $Case3StagedPaths = @(
        Invoke-TestGit -GitArgs @('-C', $RepoPath, 'diff', '--cached', '--no-renames', '--name-only') |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ }
    )
    $Case3StagedNumstat = @(
        Invoke-TestGit -GitArgs @('-C', $RepoPath, 'diff', '--cached', '--no-renames', '--numstat') |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ }
    )
    $Case3StagedDiffNonEmpty = $Case3StagedPaths.Count -eq 1 -and
        $Case3StagedPaths[0] -ceq 'docs/article.md' -and
        $Case3StagedNumstat.Count -gt 0
    if (-not $Case3StagedDiffNonEmpty) {
        throw 'SUCCESS_CASE_3 fixture did not produce the required non-empty staged diff.'
    }
    $Case3RemoteRefsBefore = @(Get-SyntheticRemoteRefs)
    $SuccessCase3Result = Invoke-HarnessProcess `
        -Case 'SUCCESS_CASE_3' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl
    $Case3RemoteRefsAfter = @(Get-SyntheticRemoteRefs)
    $Case3RemoteRefsUnchanged = Compare-StringArrays $Case3RemoteRefsBefore $Case3RemoteRefsAfter
    $SyntheticRemoteRefsUnchanged = $SyntheticRemoteRefsUnchanged -and $Case3RemoteRefsUnchanged
    $Results += Assert-SuccessResult -Case 'SUCCESS_CASE_3' -Result $SuccessCase3Result `
        -AdditionalEvidence (
            "SYNTHETIC_REMOTE_REFS_BEFORE_COUNT=$($Case3RemoteRefsBefore.Count)`r`n" +
            "SYNTHETIC_REMOTE_REFS_AFTER_COUNT=$($Case3RemoteRefsAfter.Count)`r`n" +
            "SYNTHETIC_REMOTE_REFS_UNCHANGED=$Case3RemoteRefsUnchanged`r`n" +
            "STAGED_DIFF_NONEMPTY=$Case3StagedDiffNonEmpty`r`n" +
            "STAGED_PATHS=$($Case3StagedPaths -join ',')`r`n" +
            "STAGED_NUMSTAT=$($Case3StagedNumstat -join ';')"
        )

    $Results | Format-Table -AutoSize
    $SourceHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePath).Hash
    $FailClosedHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $FailClosedTestPath).Hash
    $ProjectSourceUnchanged = $SourceHashBefore -eq $SourceHashAfter -and $FailClosedHashBefore -eq $FailClosedHashAfter
    $PathRestored = $env:Path -eq $OriginalPath
    $GlobalGitConfigAfter = Get-GlobalGitConfigSnapshot
    $GlobalGitConfigUnchanged = Compare-StringArrays $GlobalGitConfigBefore $GlobalGitConfigAfter
    Write-Output "PROJECT_SOURCE_UNCHANGED=$ProjectSourceUnchanged"
    Write-Output "PROCESS_LOCAL_PATH_RESTORED=$PathRestored"
    Write-Output "SYNTHETIC_REMOTE_REFS_UNCHANGED=$SyntheticRemoteRefsUnchanged"
    Write-Output "GLOBAL_SCOPE_GIT_CONFIG_UNCHANGED=$GlobalGitConfigUnchanged"
    Write-Output "M2_WARNING_REPRODUCED=$M2WarningReproduced"

    $Passed = (@($Results | Where-Object { $_.Verdict -ne 'PASS' }).Count -eq 0) -and $ProjectSourceUnchanged -and $PathRestored -and $SyntheticRemoteRefsUnchanged -and $GlobalGitConfigUnchanged -and $M2WarningReproduced
    if ($Passed) {
        Write-Output 'FINAL_RESULT=PASS'
        exit 0
    }

    Write-Error 'FINAL_RESULT=FAIL'
    exit 1
}
finally {
    # Retain test-owned evidence and synthetic repositories for review.
}
