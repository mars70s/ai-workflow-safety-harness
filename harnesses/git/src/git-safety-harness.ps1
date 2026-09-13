[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedRootPath,

    [Parameter(Mandatory = $true)]
    [string[]]$AllowedFiles,

    [Parameter(Mandatory = $true)]
    [string[]]$AllowedStagedFiles,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedBranch,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedPushUrl,

    [string]$Remote = 'origin'
)

$ErrorActionPreference = 'Stop'

function Stop-Harness {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    throw [System.InvalidOperationException]::new("STOP: $Message")
}

function Invoke-NativeGit {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArgs,

        [switch]$UseRepositoryRoot
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    $Stdout = @()
    $Stderr = @()
    $ExitCode = $null
    $DiagnosticPath = [System.IO.Path]::GetTempFileName()
    try {
        $ErrorActionPreference = 'Continue'
        if ($UseRepositoryRoot) {
            $Stdout = @(& git -C $script:RepositoryRoot @GitArgs 2> $DiagnosticPath)
        }
        else {
            $Stdout = @(& git @GitArgs 2> $DiagnosticPath)
        }
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

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArgs
    )

    $Result = Invoke-NativeGit -GitArgs $GitArgs -UseRepositoryRoot

    if ($Result.ExitCode -ne 0) {
        $Diagnostic = @(
            $Result.Stderr |
                ForEach-Object { $_.ToString() } |
                Where-Object { $_ -and $_.Trim() }
        ) -join [Environment]::NewLine
        $Message = "GSH_STOP_GIT: git $($GitArgs -join ' ') failed."
        if ($Diagnostic) {
            $Message += "`n$Diagnostic"
        }
        Stop-Harness -Message $Message
    }

    return @($Result.Stdout)
}

try {
    $RootResult = Invoke-NativeGit -GitArgs @('rev-parse', '--show-toplevel')
    $ActualRootRaw = @($RootResult.Stdout)
    $RootExitCode = $RootResult.ExitCode

    if ($RootExitCode -ne 0 -or $ActualRootRaw.Count -eq 0) {
        $RootDiagnostic = @(
            $RootResult.Stderr |
                ForEach-Object { $_.ToString() } |
                Where-Object { $_ -and $_.Trim() }
        ) -join [Environment]::NewLine
        $Message = 'GSH_STOP_ROOT: Repository Root could not be confirmed.'
        if ($RootDiagnostic) {
            $Message += "`n$RootDiagnostic"
        }
        Stop-Harness -Message $Message
    }

    try {
        $ExpectedRoot = (Resolve-Path -LiteralPath $ExpectedRootPath -ErrorAction Stop).Path
        $ActualRootCandidate = ($ActualRootRaw | Select-Object -First 1).ToString().Trim()
        $ActualRoot = (Resolve-Path -LiteralPath $ActualRootCandidate -ErrorAction Stop).Path
    }
    catch {
        Stop-Harness -Message 'GSH_STOP_ROOT_RESOLUTION: Repository Root path resolution failed.'
    }

    if ($ActualRoot -ne $ExpectedRoot) {
        Stop-Harness -Message "GSH_STOP_ROOT: unexpected Repository Root: $ActualRoot"
    }

    $script:RepositoryRoot = $ActualRoot

    $CurrentBranchLines = @(
        Invoke-GitChecked -GitArgs @(
            'symbolic-ref',
            '--short',
            'HEAD'
        ) |
            Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { $_.Trim() }
    )

    if ($CurrentBranchLines.Count -ne 1) {
        Write-Error 'GSH_STOP_BRANCH: expected branch could not be determined.' -ErrorAction Continue
        exit 1
    }

    $CurrentBranch = [string]$CurrentBranchLines[0]

    if ($CurrentBranch -cne $ExpectedBranch) {
        Write-Error "GSH_STOP_BRANCH: unexpected branch: $CurrentBranch" -ErrorAction Continue
        exit 1
    }

    Write-Host "PASS: branch=$CurrentBranch"

    $PushUrls = @(
        Invoke-GitChecked -GitArgs @(
            'remote',
            'get-url',
            '--push',
            '--all',
            $Remote
        ) |
            Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { $_.Trim() }
    )

    if ($PushUrls.Count -ne 1 -or $PushUrls[0] -cne $ExpectedPushUrl) {
        Write-Error 'GSH_STOP_PUSH_URL: push URL did not match the expected value.' -ErrorAction Continue
        exit 1
    }

    $ChangedFiles = @(
        Invoke-GitChecked -GitArgs @('diff', '--no-renames', '--name-only')
        Invoke-GitChecked -GitArgs @('diff', '--cached', '--no-renames', '--name-only')
        Invoke-GitChecked -GitArgs @('ls-files', '--others', '--exclude-standard', '--full-name')
    ) |
        Where-Object { $_ -and $_.Trim() } |
        ForEach-Object { $_.Trim() } |
        Sort-Object -Unique -CaseSensitive

    $Unexpected = @($ChangedFiles | Where-Object { $_ -cnotin $AllowedFiles })
    if ($Unexpected.Count -gt 0) {
        Write-Error 'GSH_STOP_WRITE_SET: Write Set contains unexpected changes.' -ErrorAction Continue
        $Unexpected | ForEach-Object { Write-Host "  $_" }
        exit 1
    }

    $StagedFiles = @(Invoke-GitChecked -GitArgs @('diff', '--cached', '--no-renames', '--name-only')) |
        Where-Object { $_ -and $_.Trim() } |
        ForEach-Object { $_.Trim() }

    $UnexpectedStaged = @($StagedFiles | Where-Object { $_ -cnotin $AllowedStagedFiles })
    if ($UnexpectedStaged.Count -gt 0) {
        Write-Error 'GSH_STOP_STAGE_SET: Stage Set contains unexpected staged files.' -ErrorAction Continue
        $UnexpectedStaged | ForEach-Object { Write-Host "  $_" }
        exit 1
    }

    $GitleaksCommand = Get-Command gitleaks -CommandType Application -ErrorAction SilentlyContinue
    if (-not $GitleaksCommand -or -not $GitleaksCommand.Source) {
        Stop-Harness -Message 'GSH_STOP_GITLEAKS_UNAVAILABLE: gitleaks is not available.'
    }

    Write-Output "GITLEAKS_SOURCE=$($GitleaksCommand.Source)"

    $GitleaksExitCode = $null
    try {
        & $GitleaksCommand.Source git --staged --redact $RepositoryRoot
        $GitleaksExitCode = $LASTEXITCODE
    }
    catch {
        Stop-Harness -Message "GSH_STOP_GITLEAKS_EXECUTION: gitleaks execution failed: $($_.Exception.Message)"
    }

    if ($null -eq $GitleaksExitCode -or $GitleaksExitCode -ne 0) {
        Stop-Harness -Message 'GSH_STOP_SECRET_SCAN: secret scan did not pass.'
    }

    Write-Output 'PASS: Repository Root OK'
    Write-Output 'PASS: Branch OK'
    Write-Output 'PASS: Push URL OK'
    Write-Output 'PASS: Write Set OK'
    Write-Output 'PASS: Stage Set OK'
    Write-Output 'PASS: Secret Scan OK'
    exit 0
}
catch {
    $ErrorMessage = $_.Exception.Message
    if ($ErrorMessage -notmatch '^STOP:') {
        $ErrorMessage = "STOP: Harness execution failed: $ErrorMessage"
    }
    Write-Error $ErrorMessage -ErrorAction Continue
    exit 1
}
