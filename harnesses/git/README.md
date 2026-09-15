# Git Safety Harness

[English](README.md) | [日本語](README.ja.md)

A reference implementation of a soft, fail-closed Safety Harness for selected Git workflow boundaries. The current status is **PRE-PUBLICATION REFERENCE IMPLEMENTATION**.

The Harness is a Layer-2 workflow control. It is not a sandbox, an independent security boundary, or a production security guarantee. Raw Git, shell, API, or filesystem access may bypass it unless separate Layer-3 controls constrain that access.

Related documents: [Getting Started](docs/getting-started.md) | [Validation Record](docs/validation.md) | [Design](docs/design.md) | [Limitations](docs/limitations.md) | [MIT License](../../LICENSE)

After the repository root is established, policy Git operations use the resolved root through `git -C <resolved-root> ...`. Initial root discovery is the bootstrap exception. The Write Set is derived from tracked unstaged changes, staged changes, and non-ignored untracked paths as implemented; the allow-set comparison is case-sensitive.

## Validated gates

The current tests directly exercise these gates:

1. Repository Root: non-repository execution, root-resolution failure, and mismatch against another valid repository.
2. Write Set: an out-of-scope untracked file, rename exposure, and case-collision path handling.
3. Stage Set: an independently reachable staged-file failure.
4. Branch: detached HEAD and expected-branch mismatch.
5. Push URL: multiple push URLs, exactly one mismatching push URL, and a valid exact single match in the success path.
6. Secret Scan: unavailable Gitleaks, discovered-but-unexecutable Gitleaks, an actual real-Gitleaks finding, and a successful real-Gitleaks scan.
7. Fail-closed STOP behavior.

The success path directly exercises three workflows: a valid clean workflow; the M2 line-ending warning condition with an initially unstaged allowed change; and a valid non-empty allowed staged diff scanned successfully by real Gitleaks. This is bounded coverage, not exhaustive testing of Git, PowerShell, Gitleaks, or all edge cases.

## Validation reference environments

- Git 2.54.0.windows.1
- PowerShell 7.6.5
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

The fail-closed suite passed 14 cases under PowerShell 7 and 14 cases under Windows PowerShell 5.1: **28/28 PASS**. The positive suite passed 3 cases under each shell using real Gitleaks 8.30.1: **6/6 PASS**. Success Case 2 may exercise an empty staged diff after the Harness-relevant unstaged warning path; Success Case 3 explicitly exercises a non-empty staged diff. These are validated reference environments and test results, not universal compatibility guarantees.

## Invocation contract

The Harness script requires:

- `-ExpectedRootPath`: the expected repository root;
- `-AllowedFiles`: the exact case-sensitive allowed Write Set;
- `-AllowedStagedFiles`: the exact case-sensitive allowed Stage Set;
- `-ExpectedBranch`: the expected symbolic branch;
- `-ExpectedPushUrl`: the exact expected push URL; and
- `-Remote`: the remote to inspect, defaulting to `origin`.

Gitleaks is an external dependency. The Harness discovers an Application named `gitleaks` through `Get-Command gitleaks -CommandType Application` and invokes the staged scan. The caller should resolve the Harness script path independently; the target repository root is a separate parameter/state. The validated automation boundary is a PowerShell wrapper or caller that creates native PowerShell objects, including a `[string[]]` `AllowedFiles` value, builds a parameter hashtable, invokes the Harness with splatting, and propagates both invocation failures and the child exit code fail-closed:

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

This wrapper/splatting form is the validated multi-file automation pattern. Its explicit error boundary returns exit 1 for wrapper-level invocation or binding failure, a missing/null child exit state, or a non-zero Harness result; only a successful Harness invocation returns exit 0. Direct `-File` invocation is not the validated general multi-value interface for `AllowedFiles`; shell-to-PowerShell array binding can differ, so `@('a', 'b')` should not be passed as though it were native external command-line array syntax. A direct `-File` call remains useful only for a single-value parameter when its shell binding is understood. Dot-sourcing and arbitrary in-process invocation are not claimed as fully validated invocation modes.

## Secret Scan scope

The current implementation invokes the equivalent of `gitleaks git --staged --redact` for the confirmed repository root. Secret Scan therefore covers the staged Git diff examined by Gitleaks. It does not imply that every repository file was scanned, that allowed unstaged or untracked files were scanned, or that committed content, including commits that have not yet been pushed, is scanned merely because it exists in repository history. It is not complete secret detection.

Gitleaks behavior can be influenced by applicable scanner configuration and ignore mechanisms, including repository-local configuration where supported by Gitleaks. The Harness does not independently validate that the Gitleaks configuration or ignore rules are correct.

The operational exit contract is conservative: zero means the scan is accepted as successful; non-zero, null, or execution failure means STOP. The Harness does not claim that a numeric exit code alone always distinguishes a secret finding from a scanner or runtime error.

## Push contract

The Harness validates the configured push URL for the specified remote. It does not perform the later `git push` and does not independently guarantee which remote or ref an arbitrary later push will use when ambient Git configuration supplies defaults. Any subsequent authorized push should explicitly name the intended remote and ref or branch.

## Test evidence and provenance

The current evidence measured unchanged synthetic remote refs, unchanged Git configuration in the global scope during the success tests, restoration of the process-local PATH, real Gitleaks execution, and the expected STOP and success paths. The separately verified Gitleaks executable used for positive-path validation was version 8.30.1. The tests use synthetic local remotes. These measurements do not constitute broad network monitoring; the Harness code does not perform the later deployment or push action.

Current locally recovered and validated working source was adopted as the v0.1 baseline. Earlier exact file lineage is not asserted. The repository implementation intentionally includes bounded corrections and compatibility hardening beyond code examples shown in the earlier explanatory article.

## Limitations

The Harness does not guarantee safety, act as a sandbox, or provide an independent security boundary. See [design.md](docs/design.md) and [limitations.md](docs/limitations.md) for the full bounded scope. Known limitations include semantic mistakes inside allowed files, a correct remote paired with wrong content, raw Git or shell bypass, incomplete and staged-only secret detection, filesystem changes invisible to selected Git checks, `assume-unchanged`, `skip-worktree`, human approval of an incorrect state, deploy/API/external actions outside Git, TOCTOU, path edge cases, submodules, symlinks, junctions, environment influence, tool/version differences, and configuration-dependent behavior.
