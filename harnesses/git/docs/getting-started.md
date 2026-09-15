# Git Safety Harness — Getting Started

[English](getting-started.md) | [日本語](getting-started.ja.md)

This guide explains the basic first-use path for the Git Safety Harness. The Harness is a Layer-2 workflow control for checking that work has not moved outside a pre-defined policy. Fail-closed means that when a required condition cannot be confirmed, processing stops instead of continuing. Layer 2 checks before execution whether the current state matches conditions defined in advance. It is not a sandbox or an independent security boundary.

## 1. What this Harness checks

Suppose you ask an AI assistant:

“On the `main` branch, update only `docs/article.md` and `public/article.html`. After the checks are complete, separately authorize a push to `origin`.”

Before later operations continue, the Git Safety Harness checks:

- whether you are in the intended repository;
- whether unexpected files changed;
- whether staged files are within the intended staged set;
- whether the branch is correct;
- whether the push destination is the expected one; and
- whether Gitleaks accepts the staged change.

If a required condition does not match, the Harness stops.

The Harness does not decide what the correct state is. A human defines the expected state first. The Harness checks whether that policy matches the Git state it can observe.

### How checks map to settings

The six settings are not a one-to-one list of all checks. Secret Scan, for example, has no user allow-list parameter; Gitleaks runs it automatically as part of the Harness.

| Harness check | Related setting | Automatic |
| --- | --- | --- |
| Whether Repository Root is the expected root | `ExpectedRootPath` | Yes |
| Whether the Write Set is within the allowed scope | `AllowedFiles` | Yes |
| Whether the Stage Set is within the allowed scope | `AllowedStagedFiles` | Yes |
| Whether the branch is the expected symbolic branch | `ExpectedBranch` | Yes |
| Whether the selected remote has the expected push URL | `Remote` + `ExpectedPushUrl` | Yes |
| Secret Scan of staged changes | No user policy parameter; Gitleaks runs automatically as part of the Harness | Yes |

## 2. Prerequisites

Make the following tools available:

- Git
- PowerShell
- Gitleaks

The reference validation versions are:

- Git 2.54.0.windows.1
- PowerShell 7.6.5
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

These are reference validation versions, not a guarantee of compatibility in every environment. Compatibility with versions not listed here is unverified. If you use another version, run the test suite included in this repository in that environment and inspect the result before incorporating the Harness into production work. The Harness does not check Git, PowerShell, or Gitleaks versions itself.

## 3. Locate the Harness

The Git implementation is located at:

`harnesses/git/src/git-safety-harness.ps1`

Resolve the script path independently from the target repository root. Do not assume that the current working directory contains the script.

## 4. Define the six settings first

These six settings tell the Harness which state the human considers acceptable.

| Setting | Plain meaning | What the human decides | What the Harness checks | Why it exists | Example | STOP example |
| --- | --- | --- | --- | --- | --- | --- |
| `ExpectedRootPath` | The repository location for this work | Which repository is the intended target | Whether the repository root found from the current directory exactly matches it | To prevent running in another repository | `C:\work\example-project` | The actual root is `C:\work\other-project` |
| `AllowedFiles` | Files that may contain changes | Which files may be changed for this task | Whether every path in the current Write Set is allowed | To detect unexpected edits | `docs/article.md`, `public/article.html` | `README.md` also changed |
| `AllowedStagedFiles` | Files that may be staged as commit candidates | Which files may be staged for the next commit | Whether every path in the Stage Set is allowed | To limit the next commit candidate set | `docs/article.md`, `public/article.html` | An unapproved file is staged |
| `ExpectedBranch` | The branch for this work | Which branch is intended | Whether the symbolic branch exactly matches | To avoid continuing on the wrong branch | `main` | `feature/test` or detached HEAD |
| `Remote` | The name of the remote whose push URL is checked | Which remote to inspect; this is not a URL | Which remote is used for push-URL inspection | To avoid checking the wrong remote | `origin` | An unintended or missing remote is selected |
| `ExpectedPushUrl` | The push URL that should be configured for that remote | Which exact push URL is expected | Whether exactly one configured push URL matches | To detect an unintended destination | `git@github.com:example/example-project.git` | The URL differs, multiple URLs exist, or it cannot be confirmed |

`ExpectedRootPath` helps prevent running the workflow in another repository. `AllowedFiles` detects unexpected edits: if the plan allows two files but `README.md` also changed, the Harness stops.

`AllowedFiles` and `AllowedStagedFiles` are deliberately separate. A file may be allowed to contain a current change without being allowed as a staged candidate for the next commit.

`Remote` is a remote name, not a URL. With `Remote = origin`, the Harness inspects the push URL configured for `origin`. The Harness does not push.

## 5. Worked example — change only two files

**All values below are examples. Replace them with values for the real repository.**

AI request:

“On the `main` branch, update only `docs/article.md` and `public/article.html`. After the checks are complete, separately authorize a push to `origin`.”

| Setting | Example |
| --- | --- |
| `ExpectedRootPath` | `C:\work\example-project` |
| `AllowedFiles` | `docs/article.md`, `public/article.html` |
| `AllowedStagedFiles` | `docs/article.md`, `public/article.html` |
| `ExpectedBranch` | `main` |
| `Remote` | `origin` |
| `ExpectedPushUrl` | `git@github.com:example/example-project.git` |

Conceptually, the Harness then:

1. confirms the repository root from the current directory;
2. checks which files have changed;
3. checks which files are staged;
4. checks the current branch;
5. checks the push URL for `origin`;
6. checks the staged change with Gitleaks; and
7. returns PASS only if all required checks are accepted.

## 6. Write Set and Stage Set

The Write Set is the set of files that the Harness recognizes as changed in the current worktree. It includes tracked unstaged changes, staged changes, and non-ignored untracked paths. It answers: “Did anything change outside the files we allowed for this work?”

The Stage Set is the subset of paths currently staged as candidates for the next commit. It answers a different question: “Are the files staged for the next commit the files we allowed to stage?”

Example policy:

`AllowedFiles`:

- `article.md`
- `figure.svg`

`AllowedStagedFiles`:

- `article.md`

Under this policy:

- `article.md` changed and staged → OK
- `figure.svg` changed but is not staged → OK
- `figure.svg` is staged → STOP
- `README.md` changed → STOP

## 7. Run the wrapper

For multiple allowed paths, use a PowerShell caller or wrapper. It does the following:

1. identifies the Harness path;
2. creates arrays of allowed files;
3. collects the six settings in a hashtable;
4. invokes the Harness;
5. treats a failure to invoke it as a STOP;
6. treats a non-zero Harness result as a STOP; and
7. returns 0 only after successful Harness execution.

The validated general multi-file interface is native PowerShell objects, a parameter hashtable, and splatting. Direct external `-File` invocation is not the validated general multi-value interface for `AllowedFiles`.

### Avoid this — pass multiple values directly to an external `-File` invocation

`pwsh -File <path-to-harness> -AllowedFiles @('a', 'b')`

This is not the validated general multi-value interface. Shell-to-PowerShell array binding may not behave as intended.

### Use this

Use the existing wrapper below, which creates PowerShell objects, builds a parameter hashtable, and invokes the Harness with splatting. This is the validated multi-file pattern.

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

This wrapper returns exit 1 for an invocation or binding failure, a missing or null child exit state, or a non-zero Harness result. It returns exit 0 only after successful Harness execution.

Make sure Gitleaks is discoverable as an Application named `gitleaks`:

```powershell
Get-Command gitleaks -CommandType Application
```

## 8. When the result is PASS

**PASS does not mean that the work content is correct.**

PASS means that the conditions defined by the human matched the Git state observed by the Harness.

PASS does not prove:

- that the article content is correct;
- that code is semantically correct;
- that the human policy itself is correct; or
- that a later push will be safe.

## 9. When the result is STOP

**STOP does not mean “repair it automatically and continue.”**

It means that one or more required conditions could not be accepted. Inspect the STOP marker and the current Git state, identify the reason, and decide whether the policy or the work state needs human review.

## 10. What Gitleaks checks

Gitleaks is an external tool that checks staged changes for secret-like information. In this Harness invocation, Gitleaks checks the staged diff.

The following are not included merely because they exist:

- unstaged files;
- untracked files;
- the full repository history; or
- committed or unpushed content.

An untracked file can become part of the staged diff if it is staged. Scanner configuration and ignore rules can also influence results. Complete secret detection is not guaranteed.

## 11. Push is a separate operation

The Harness checks the push-URL configuration but does not push. PASS does not automatically authorize a push. If a later push is separately authorized, explicitly name the intended remote and ref or branch.

```powershell
git push <remote> <ref-or-branch>
```

## 12. Common STOP conditions

- `README.md` also changed → STOP because it is not in `AllowedFiles`.
- The branch is `feature/test` → STOP because it differs from `ExpectedBranch`.
- HEAD is detached → STOP because no symbolic branch can be confirmed.
- `origin` points to another repository → STOP because it differs from `ExpectedPushUrl`.
- Multiple push URLs exist → STOP because exactly one is required.
- Gitleaks is not installed or discoverable → STOP.
- Gitleaks cannot execute → STOP.
- Gitleaks returns non-zero → STOP.

## 13. What this Harness cannot prevent

This Harness checks whether work remains within a defined procedure. If a human or AI can operate Git or the shell directly without using the Harness, the Harness cannot itself prohibit that direct operation.

Layer 3 may include server-side repository controls, protected branches or required checks, independent CI-side secret scanning, and OS, container, or account permission boundaries. The appropriate controls depend on the execution environment; this repository does not implement or validate them. Stronger independent restrictions belong to Layer 3, External Independent Enforcement. This repository implements Layer 2 only.

## 14. More examples

See the [Examples](examples.md) cookbook for reusable configuration patterns.
