# Git Safety Harness validation evidence

This directory contains a bounded local re-execution of the unchanged Git Safety Harness test suites. The directory name follows the requested work-unit evidence location; the actual capture date was 2026-09-20 (Asia/Tokyo).

## Result

- PowerShell 7 fail-closed: 14/14 PASS; suite exit 0.
- Windows PowerShell 5.1 fail-closed: 14/14 PASS; suite exit 0.
- PowerShell 7 success path: 3/3 PASS; suite exit 0.
- Windows PowerShell 5.1 success path: 3/3 PASS; suite exit 0.

Each fail-closed case record includes the child stdout, stderr, exit code, expected and required markers, forbidden success marker check, and runner verdict. Each success case record includes the child stdout, stderr, exit code, pass/STOP marker checks, Gitleaks source checks, and runner verdict.

## Identity and execution boundary

The three source/test SHA256 values matched the published Validation Record before execution. The suites were invoked unchanged with their supported `-GitleaksPath` parameter. Gitleaks was not available through the ambient PATH, so an existing local Gitleaks 8.30.1 archive was verified against its existing checksum manifest, checked for unsafe ZIP entry names, extracted to a temporary directory, and passed explicitly to the unchanged tests.

`origin/main` records the existing local remote-tracking ref. No fetch or other network operation was performed. The implementation, tests, README files, Validation Record, and limitations document were not modified.

## Sanitization

Public evidence replaces local repository, temporary-fixture, tool-extraction, and user-profile paths with `[REDACTED_LOCAL_PATH]` or `[REDACTED_USER]`. Known synthetic secret fixture text, if present, is replaced with `[REDACTED_SECRET_FIXTURE]`. PowerShell executable locations are reduced to executable names. These replacements do not alter case results, STOP markers, exit codes, or PASS/FAIL verdicts.

The PowerShell 7 Case 5 child diagnostic contains encoding-corrupted localized text emitted by the nested process boundary. It is retained as observed; the stable `GSH_STOP_GITLEAKS_EXECUTION` marker, child exit code 1, required source marker, and PASS verdict remain readable.

## Files

- `environment.txt`: repository, tool, source/test identity, and suite summary.
- `powershell7-fail-closed.txt`: suite output plus all 14 retained case records.
- `windows-powershell51-fail-closed.txt`: suite output plus all 14 retained case records.
- `powershell7-success-path.txt`: suite output plus all 3 retained case records.
- `windows-powershell51-success-path.txt`: suite output plus all 3 retained case records.
- `representative-stop-cases.md`: representative STOP interpretations linked to detailed evidence.
- `SHA256SUMS.txt`: SHA256 manifest for the other evidence files in this directory.

## Evidence boundary

This capture demonstrates the observed behavior of the identified source and tests in the recorded local environments. It is not a universal compatibility or security guarantee, does not prove complete secret detection, and does not constrain direct Git, shell, API, deploy, or other activity outside the Harness.
