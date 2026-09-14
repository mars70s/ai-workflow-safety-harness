[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitleaksPath
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $RepositoryRoot 'src\git-safety-harness.ps1'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunId = [guid]::NewGuid().ToString('N')
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "git-safety-harness-test-$Timestamp-$RunId"
$RepoPath = Join-Path $TestRoot 'repo'
$FakeBinPath = Join-Path $TestRoot 'fake-bin'
$RemotePath = Join-Path $TestRoot 'remote.git'
$WrapperPath = Join-Path $TestRoot 'wrappers'
$EvidencePath = Join-Path $TestRoot 'evidence'
$OriginalPath = $env:Path
$ResolvedGitleaksPath = $null
$GitleaksDirectory = $null
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

function Invoke-GitleaksFindingProbe {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $Output = @()
    $ExitCode = $null
    try {
        $ErrorActionPreference = 'Continue'
        $Output = @(& $ResolvedGitleaksPath git --staged --redact $RepoPath 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    [pscustomobject]@{
        Output = @($Output | ForEach-Object { $_.ToString() })
        ExitCode = $ExitCode
    }
}

function Get-VerifiedGitleaksPath {
    $PreviousPath = $env:Path
    try {
        if ($GitleaksPath) {
            if (-not (Test-Path -LiteralPath $GitleaksPath -PathType Leaf)) {
                throw "GITLEAKS_DEPENDENCY_UNAVAILABLE: supplied path does not exist: $GitleaksPath"
            }

            $ExpectedPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $GitleaksPath -ErrorAction Stop).Path)
            $ExpectedDirectory = Split-Path -Parent $ExpectedPath
            $env:Path = "$ExpectedDirectory;$PreviousPath"
        }

        try {
            $Command = Get-Command gitleaks -CommandType Application -ErrorAction Stop
        }
        catch {
            throw 'GITLEAKS_DEPENDENCY_UNAVAILABLE: gitleaks was not found through Application command discovery.'
        }

        if (-not $Command.Source) {
            throw 'GITLEAKS_DEPENDENCY_UNAVAILABLE: Application command discovery returned no executable path.'
        }

        $ResolvedPath = [System.IO.Path]::GetFullPath($Command.Source)
        if ($GitleaksPath -and $ResolvedPath -cne $ExpectedPath) {
            throw "GITLEAKS_PATH_MISMATCH: expected $ExpectedPath but resolved $ResolvedPath"
        }

        return [pscustomobject]@{
            Path = $ResolvedPath
            Directory = Split-Path -Parent $ResolvedPath
        }
    }
    finally {
        $env:Path = $PreviousPath
    }
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
        [string]$ExpectedPushUrl,

        [string]$HarnessPathOverride,

        [switch]$PreInvocationSuccess,

        [switch]$EmptyAllowedFiles
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
        '$HarnessParams = @{'
        "    ExpectedRootPath = $(ConvertTo-PowerShellLiteral -Value $ExpectedRoot)"
        '    AllowedFiles = @('
    )
    if (-not $EmptyAllowedFiles) {
        foreach ($AllowedFile in $AllowedFiles) {
            $Lines += "        $(ConvertTo-PowerShellLiteral -Value $AllowedFile)"
        }
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
    if ($Case -in @('CASE_5', 'CASE_12')) {
        $Lines += @(
            '$GitleaksTestCommand = Get-Command gitleaks -CommandType Application -ErrorAction SilentlyContinue'
            'if ($GitleaksTestCommand) {'
            '    Write-Output "GITLEAKS_TEST_SOURCE=$($GitleaksTestCommand.Source)"'
            '}'
        )
    }
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

        [string]$PathOverride,

        [string]$HarnessPathOverride,

        [switch]$PreInvocationSuccess,

        [switch]$EmptyAllowedFiles
    )

    $WrapperFile = New-HarnessWrapper `
        -Case $Case `
        -ExpectedRoot $ExpectedRoot `
        -AllowedFiles $AllowedFiles `
        -AllowedStagedFiles $AllowedStagedFiles `
        -ExpectedPushUrl $ExpectedPushUrl `
        -HarnessPathOverride $HarnessPathOverride `
        -PreInvocationSuccess:$PreInvocationSuccess `
        -EmptyAllowedFiles:$EmptyAllowedFiles

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

        [string]$AdditionalEvidence,

        [switch]$RequireExplicitStop
    )

    $CombinedForMatching = $Result.Combined -replace '\s+', ''
    $HasForbiddenPass = $Result.Combined -match 'PASS: Secret Scan OK'
    $ExpectedMarkerPattern = [regex]::Escape(($ExpectedMarker -replace '\s+', ''))
    if ($ExpectedMarker -notmatch ':$') {
        $ExpectedMarkerPattern += '(?=[:]|$)'
    }
    $HasExpectedMarker = $CombinedForMatching -match $ExpectedMarkerPattern
    $HasRequiredMarker = $true
    if ($RequiredMarker) {
        $HasRequiredMarker = $CombinedForMatching -match [regex]::Escape(($RequiredMarker -replace '\s+', ''))
    }
    $HasExplicitStop = $true
    if ($RequireExplicitStop) {
        $HasExplicitStop = ($CombinedForMatching -match 'STOP:') -and
            ($CombinedForMatching -notmatch 'STOP:Harness execution failed:')
    }
    $Pass = $Result.ExitCode -eq 1 -and $HasExpectedMarker -and $HasRequiredMarker -and -not $HasForbiddenPass -and $HasExplicitStop

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
        "REQUIRE_EXPLICIT_STOP: $([bool]$RequireExplicitStop)"
        "HAS_EXPLICIT_STOP: $([bool]$HasExplicitStop)"
        "RUNNER_PASS_EXPRESSION: $([bool]$Pass)"
        "TEST_RESULT: $(if ($Pass) { 'PASS' } else { 'FAIL' })"
    ) -join "`r`n"
    if ($AdditionalEvidence) {
        $ResultText += "`r`nADDITIONAL_EVIDENCE_BEGIN`r`n$AdditionalEvidence`r`nADDITIONAL_EVIDENCE_END"
    }
    $CaseNumber = $Case -replace '^CASE_', ''
    $CaseFile = Join-Path $EvidencePath ("case-{0}.txt" -f $CaseNumber.PadLeft(2, '0'))
    [System.IO.File]::WriteAllText($CaseFile, $ResultText, [System.Text.UTF8Encoding]::new($false))

    [pscustomobject]@{
        Case = $Case
        Shell = $PSVersionTable.PSVersion.ToString()
        ExitCode = $Result.ExitCode
        ForbiddenPass = $HasForbiddenPass
        Verdict = if ($Pass) { 'PASS' } else { 'FAIL' }
    }
}

function Assert-WrapperContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Result,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedExitCode,

        [switch]$RequireInvocationCatch
    )

    $HasInvocationCatch = $Result.Combined -match 'WRAPPER_INVOCATION_FAILURE_CAUGHT=YES'
    $Pass = $Result.ExitCode -eq $ExpectedExitCode -and
        (-not $RequireInvocationCatch -or $HasInvocationCatch)
    if (-not $Pass) {
        throw "WRAPPER_CONTRACT_$Name failed: expected exit $ExpectedExitCode, observed $($Result.ExitCode)."
    }

    [pscustomobject]@{
        Name = $Name
        ExitCode = $Result.ExitCode
        InvocationCatch = $HasInvocationCatch
        Verdict = 'PASS'
    }
}

$Passed = $false
try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $RepoPath, $FakeBinPath, $WrapperPath, $EvidencePath -Force | Out-Null

    $GitleaksInfo = Get-VerifiedGitleaksPath
    $ResolvedGitleaksPath = $GitleaksInfo.Path
    $GitleaksDirectory = $GitleaksInfo.Directory
    Write-Output "GITLEAKS_RESOLVED_PATH=$ResolvedGitleaksPath"

    $Results = @()
    $WrapperContractResults = @()

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Write-TestFile -RelativePath 'public/article.html' -Content '<p>Test article</p>'
    Commit-TestBaseline -Paths @('docs/article.md', 'public/article.html')
    Write-TestFile -RelativePath 'config/new-secret.env' -Content 'DUMMY_TEST_VALUE=not-a-credential'
    $Case1Result = Invoke-HarnessProcess `
        -Case 'CASE_1' `
        -WorkingDirectory (Join-Path $RepoPath 'docs') `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md', 'public/article.html') `
        -AllowedStagedFiles @('docs/article.md', 'public/article.html') `
        -ExpectedPushUrl $RemoteUrl
    $Results += Assert-CaseResult -Case 'CASE_1' -Result $Case1Result `
        -ExpectedMarker 'GSH_STOP_WRITE_SET:' `
        -RequiredMarker 'config/new-secret.env'
    $WrapperContractResults += Assert-WrapperContract -Name 'HARNESS_STOP' -Result $Case1Result -ExpectedExitCode 1

    $MissingHarnessResult = Invoke-HarnessProcess `
        -Case 'WRAPPER_PATH_MISSING' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl `
        -HarnessPathOverride (Join-Path $TestRoot 'missing-harness.ps1')
    $WrapperContractResults += Assert-WrapperContract -Name 'HARNESS_PATH_MISSING' -Result $MissingHarnessResult -ExpectedExitCode 1 -RequireInvocationCatch

    $ParameterBindingResult = Invoke-HarnessProcess `
        -Case 'WRAPPER_PARAMETER_BINDING_FAILURE' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl `
        -EmptyAllowedFiles
    $WrapperContractResults += Assert-WrapperContract -Name 'PARAMETER_BINDING_FAILURE' -Result $ParameterBindingResult -ExpectedExitCode 1 -RequireInvocationCatch

    $StaleLastExitCodeResult = Invoke-HarnessProcess `
        -Case 'WRAPPER_STALE_LASTEXITCODE' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl `
        -HarnessPathOverride (Join-Path $TestRoot 'missing-harness-after-success.ps1') `
        -PreInvocationSuccess
    $WrapperContractResults += Assert-WrapperContract -Name 'STALE_LASTEXITCODE_PRECONDITION' -Result $StaleLastExitCodeResult -ExpectedExitCode 1 -RequireInvocationCatch

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'config/app.json' -Content '{"mode":"test"}'
    Commit-TestBaseline -Paths @('config/app.json')
    New-Item -ItemType Directory -Path (Join-Path $RepoPath 'docs') -Force | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'mv', 'config/app.json', 'docs/article.md') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'add', '-A') | Out-Null
    $RenamePaths = @(Invoke-TestGit -GitArgs @('-C', $RepoPath, 'diff', '--cached', '--no-renames', '--name-only'))
    $RenameVisible = ($RenamePaths -contains 'config/app.json') -and ($RenamePaths -contains 'docs/article.md')
    if (-not $RenameVisible) {
        throw 'CASE_2 fixture did not expose both rename paths in the staged no-renames listing.'
    }
    $Results += Assert-CaseResult -Case 'CASE_2' -Result (Invoke-HarnessProcess `
        -Case 'CASE_2' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_WRITE_SET:' `
        -RequiredMarker 'config/app.json' `
        -AdditionalEvidence ("git diff --cached --no-renames --name-only`r`n" + ($RenamePaths -join "`r`n"))

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $GitDirectory = Split-Path -Parent (Get-Command git -CommandType Application -ErrorAction Stop).Source
    $Results += Assert-CaseResult -Case 'CASE_3' -Result (Invoke-HarnessProcess `
        -Case 'CASE_3' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl `
        -PathOverride $GitDirectory) `
        -ExpectedMarker 'GSH_STOP_GITLEAKS_UNAVAILABLE:'

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
        -ExpectedMarker 'GSH_STOP_ROOT_RESOLUTION:'

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
        -ExpectedMarker 'GSH_STOP_GITLEAKS_EXECUTION:' `
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
        -ExpectedMarker 'GSH_STOP_GIT:' `
        -RequiredMarker 'symbolic-ref --short HEAD'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $AdditionalPushUrl = Join-Path $TestRoot 'alternate.git'
    Invoke-TestGit -GitArgs @(
        '-C',
        $RepoPath,
        'config',
        '--local',
        '--add',
        'remote.origin.pushurl',
        $RemoteUrl
    ) | Out-Null
    Invoke-TestGit -GitArgs @(
        '-C',
        $RepoPath,
        'config',
        '--local',
        '--add',
        'remote.origin.pushurl',
        $AdditionalPushUrl
    ) | Out-Null
    $Case7PushUrls = @(
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
    $Case7HasExpected = @($Case7PushUrls | Where-Object { $_ -ceq $RemoteUrl }).Count -eq 1
    $Case7HasDifferent = @($Case7PushUrls | Where-Object { $_ -cne $RemoteUrl }).Count -eq 1
    if ($Case7PushUrls.Count -ne 2 -or -not $Case7HasExpected -or -not $Case7HasDifferent) {
        throw "CASE_7 fixture did not produce exactly two push URLs: $($Case7PushUrls -join ', ')"
    }
    $Results += Assert-CaseResult -Case 'CASE_7' -Result (Invoke-HarnessProcess `
        -Case 'CASE_7' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_PUSH_URL:' `
        -AdditionalEvidence ("git remote get-url --push --all origin`r`n" + ($Case7PushUrls -join "`r`n"))

    $NonRepositoryPath = Join-Path $TestRoot 'not-a-repository'
    New-Item -ItemType Directory -Path $NonRepositoryPath -Force | Out-Null
    $Results += Assert-CaseResult -Case 'CASE_8' -Result (Invoke-HarnessProcess `
        -Case 'CASE_8' `
        -WorkingDirectory $NonRepositoryPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_ROOT:' `
        -RequiredMarker 'could not be confirmed' `
        -RequireExplicitStop

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $BlobOnePath = Join-Path $TestRoot 'case-sensitive-one.txt'
    $BlobTwoPath = Join-Path $TestRoot 'case-sensitive-two.txt'
    Set-Content -LiteralPath $BlobOnePath -Value 'case-sensitive-one' -Encoding UTF8
    Set-Content -LiteralPath $BlobTwoPath -Value 'case-sensitive-two' -Encoding UTF8
    $BlobOne = (Invoke-TestGit -GitArgs @('-C', $RepoPath, 'hash-object', '-w', $BlobOnePath)).ToString().Trim()
    $BlobTwo = (Invoke-TestGit -GitArgs @('-C', $RepoPath, 'hash-object', '-w', $BlobTwoPath)).ToString().Trim()
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'update-index', '--add', '--cacheinfo', "100644,$BlobOne,docs/CaseCollision.md") | Out-Null
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'update-index', '--add', '--cacheinfo', "100644,$BlobTwo,docs/casecollision.md") | Out-Null
    $CaseCollisionPaths = @(Invoke-TestGit -GitArgs @('-C', $RepoPath, 'diff', '--cached', '--no-renames', '--name-only'))
    $Results += Assert-CaseResult -Case 'CASE_9' -Result (Invoke-HarnessProcess `
        -Case 'CASE_9' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/CaseCollision.md') `
        -AllowedStagedFiles @('docs/CaseCollision.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_WRITE_SET:' `
        -RequiredMarker 'docs/casecollision.md' `
        -AdditionalEvidence ("git diff --cached --no-renames --name-only`r`n" + ($CaseCollisionPaths -join "`r`n"))

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $AlternateRepoPath = Join-Path $TestRoot 'alternate-repo'
    New-Item -ItemType Directory -Path $AlternateRepoPath -Force | Out-Null
    Invoke-TestGit -GitArgs @('init', $AlternateRepoPath) | Out-Null
    Invoke-TestGit -GitArgs @('-C', $AlternateRepoPath, 'config', '--local', 'user.name', 'Harness Test') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $AlternateRepoPath, 'config', '--local', 'user.email', 'harness-test@example.invalid') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $AlternateRepoPath, 'branch', '-M', 'main') | Out-Null
    Set-Content -LiteralPath (Join-Path $AlternateRepoPath 'alternate.txt') -Value 'alternate repository' -Encoding UTF8
    Invoke-TestGit -GitArgs @('-C', $AlternateRepoPath, 'add', 'alternate.txt') | Out-Null
    Invoke-TestGit -GitArgs @('-C', $AlternateRepoPath, 'commit', '-m', 'test: alternate baseline') | Out-Null
    $Results += Assert-CaseResult -Case 'CASE_10' -Result (Invoke-HarnessProcess `
        -Case 'CASE_10' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $AlternateRepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_ROOT:' `
        -RequiredMarker 'unexpected Repository Root'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'branch', '-M', 'feature/mismatch') | Out-Null
    $Results += Assert-CaseResult -Case 'CASE_11' -Result (Invoke-HarnessProcess `
        -Case 'CASE_11' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_BRANCH:' `
        -RequiredMarker 'unexpected branch: feature/mismatch'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    $SyntheticGitleaksConfig = @'
title = "Synthetic Gitleaks test configuration"

[[rules]]
id = "synthetic-test-secret"
description = "Detects only the synthetic marker used by this test."
regex = '''SYNTHETIC_GITLEAKS_TEST_[0-9]+'''
keywords = ["SYNTHETIC_GITLEAKS_TEST_"]
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $RepoPath '.gitleaks.toml'),
        $SyntheticGitleaksConfig,
        [System.Text.UTF8Encoding]::new($false)
    )
    Commit-TestBaseline -Paths @('docs/article.md', '.gitleaks.toml')
    Write-TestFile -RelativePath 'config/synthetic-secret.txt' -Content 'SYNTHETIC_GITLEAKS_TEST_1234567890'
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'add', 'config/synthetic-secret.txt') | Out-Null
    $Case12FindingProbe = Invoke-GitleaksFindingProbe
    $Case12FindingMarker = 'leaks found: 1'
    $Case12FindingObserved = $Case12FindingProbe.ExitCode -eq 1 -and
        @($Case12FindingProbe.Output | Where-Object { $_ -match [regex]::Escape($Case12FindingMarker) }).Count -gt 0
    if (-not $Case12FindingObserved) {
        throw 'CASE_12 fixture did not produce the expected real Gitleaks finding marker.'
    }
    $Results += Assert-CaseResult -Case 'CASE_12' -Result (Invoke-HarnessProcess `
        -Case 'CASE_12' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('config/synthetic-secret.txt') `
        -AllowedStagedFiles @('config/synthetic-secret.txt') `
        -ExpectedPushUrl $RemoteUrl `
        -PathOverride "$GitleaksDirectory;$OriginalPath") `
        -ExpectedMarker 'GSH_STOP_SECRET_SCAN:' `
        -RequiredMarker $Case12FindingMarker `
        -AdditionalEvidence (
            "GITLEAKS_FINDING_PROBE_EXIT=$($Case12FindingProbe.ExitCode)`r`n" +
            "GITLEAKS_FINDING_MARKER=$Case12FindingMarker`r`n" +
            ($Case12FindingProbe.Output -join "`r`n")
        )

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Stage set test change'
    Invoke-TestGit -GitArgs @('-C', $RepoPath, 'add', 'docs/article.md') | Out-Null
    $Results += Assert-CaseResult -Case 'CASE_13' -Result (Invoke-HarnessProcess `
        -Case 'CASE_13' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('public/allowed.html') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_STAGE_SET:' `
        -RequiredMarker 'docs/article.md'

    $RemoteUrl = Reset-Scenario
    Write-TestFile -RelativePath 'docs/article.md' -Content '# Test article'
    Commit-TestBaseline -Paths @('docs/article.md')
    $MismatchingPushUrl = Join-Path $TestRoot 'mismatching.git'
    Invoke-TestGit -GitArgs @(
        '-C',
        $RepoPath,
        'config',
        '--local',
        'remote.origin.pushurl',
        $MismatchingPushUrl
    ) | Out-Null
    $Case14PushUrls = @(
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
    $Case14UrlsDiffer = $Case14PushUrls.Count -eq 1 -and ($Case14PushUrls[0] -cne $RemoteUrl)
    if ($Case14PushUrls.Count -ne 1 -or -not $Case14UrlsDiffer) {
        throw 'CASE_14 fixture did not produce exactly one mismatching push URL.'
    }
    $Results += Assert-CaseResult -Case 'CASE_14' -Result (Invoke-HarnessProcess `
        -Case 'CASE_14' `
        -WorkingDirectory $RepoPath `
        -ExpectedRoot $RepoPath `
        -AllowedFiles @('docs/article.md') `
        -AllowedStagedFiles @('docs/article.md') `
        -ExpectedPushUrl $RemoteUrl) `
        -ExpectedMarker 'GSH_STOP_PUSH_URL:' `
        -RequiredMarker 'push URL did not match' `
        -AdditionalEvidence (
            "PUSH_URL_COUNT=$($Case14PushUrls.Count)`r`n" +
            "ACTUAL_PUSH_URL=$($Case14PushUrls[0])`r`n" +
            "EXPECTED_PUSH_URL=$RemoteUrl`r`n" +
            "URLS_DIFFER=$Case14UrlsDiffer"
        )

    $Results | Format-Table -AutoSize
    $WrapperContractResults | Format-Table -AutoSize
    foreach ($WrapperContractResult in $WrapperContractResults) {
        Write-Output "WRAPPER_CONTRACT_$($WrapperContractResult.Name)=$($WrapperContractResult.Verdict)"
    }
    $FalsePass = @($Results | Where-Object { $_.ForbiddenPass -eq $true }).Count -gt 0
    $WrapperContractPassed = @($WrapperContractResults | Where-Object { $_.Verdict -ne 'PASS' }).Count -eq 0
    $Passed = (@($Results | Where-Object { $_.Verdict -ne 'PASS' }).Count -eq 0) -and $WrapperContractPassed -and -not $FalsePass
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
