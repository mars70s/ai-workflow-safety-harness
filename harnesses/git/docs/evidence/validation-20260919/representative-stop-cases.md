# Representative STOP cases

All examples below were produced by the unchanged existing fail-closed test script. Both shell runs produced the same stable STOP marker, expected child exit code 1, and case PASS verdict. Detailed stdout/stderr and runner assertions are in the linked evidence files.

## Write Set: out-of-scope untracked file

Condition: Case 1 created the non-ignored untracked path `config/new-secret.env` outside the allowed Write Set.

Expected: STOP / child exit 1.

Observed: `GSH_STOP_WRITE_SET: Write Set contains unexpected changes.` The unexpected path was emitted; `PASS: Secret Scan OK` was absent; the case verdict was PASS.

Shell: PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444.

Evidence file: `powershell7-fail-closed.txt` and `windows-powershell51-fail-closed.txt`, Case 1.

Interpretation: この条件ではHarnessが処理を継続せず停止した。

Boundary: この結果は当該条件での停止のみを示し、universal security guaranteeではない。

## Stage Set: independently reachable staged-file STOP

Condition: Case 13 staged `docs/article.md`; it was allowed by the Write Set but excluded from the allowed Stage Set.

Expected: STOP / child exit 1.

Observed: `GSH_STOP_STAGE_SET: Stage Set contains unexpected staged files.` The staged path was emitted; `PASS: Secret Scan OK` was absent; the case verdict was PASS.

Shell: PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444.

Evidence file: `powershell7-fail-closed.txt` and `windows-powershell51-fail-closed.txt`, Case 13.

Interpretation: この条件ではHarnessが処理を継続せず停止した。

Boundary: この結果は当該条件での停止のみを示し、universal security guaranteeではない。

## Branch: detached HEAD

Condition: Case 6 detached HEAD so `git symbolic-ref --short HEAD` could not resolve a symbolic branch.

Expected: STOP / child exit 1.

Observed: `STOP: GSH_STOP_GIT: git symbolic-ref --short HEAD failed.` The child exit was 1; the required symbolic-ref marker was present; the case verdict was PASS.

Shell: PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444.

Evidence file: `powershell7-fail-closed.txt` and `windows-powershell51-fail-closed.txt`, Case 6. Case 11 separately records `GSH_STOP_BRANCH: unexpected branch: feature/mismatch` with child exit 1.

Interpretation: この条件ではHarnessが処理を継続せず停止した。

Boundary: この結果は当該条件での停止のみを示し、universal security guaranteeではない。

## Push URL: exact single mismatch

Condition: Case 14 configured exactly one push URL different from the expected URL.

Expected: STOP / child exit 1.

Observed: `GSH_STOP_PUSH_URL: push URL did not match the expected value.` The fixture recorded one URL and `URLS_DIFFER=True`; the case verdict was PASS.

Shell: PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444.

Evidence file: `powershell7-fail-closed.txt` and `windows-powershell51-fail-closed.txt`, Case 14. Case 7 separately covers multiple configured push URLs.

Interpretation: この条件ではHarnessが処理を継続せず停止した。

Boundary: この結果は当該条件での停止のみを示し、universal security guaranteeではない。

## Gitleaks unavailable

Condition: Case 3 restricted Application discovery so Gitleaks was unavailable while Git remained available.

Expected: STOP / child exit 1.

Observed: `STOP: GSH_STOP_GITLEAKS_UNAVAILABLE: gitleaks is not available.` `PASS: Secret Scan OK` was absent; the case verdict was PASS.

Shell: PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444.

Evidence file: `powershell7-fail-closed.txt` and `windows-powershell51-fail-closed.txt`, Case 3.

Interpretation: この条件ではHarnessが処理を継続せず停止した。

Boundary: この結果は当該条件での停止のみを示し、universal security guaranteeではない。

## Gitleaks execution failure

Condition: Case 5 made a discovered test-owned `gitleaks.exe` invalid for execution.

Expected: STOP / child exit 1.

Observed: `STOP: GSH_STOP_GITLEAKS_EXECUTION: gitleaks execution failed:` The required test source marker was present; `PASS: Secret Scan OK` was absent; the case verdict was PASS.

Shell: PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444.

Evidence file: `powershell7-fail-closed.txt` and `windows-powershell51-fail-closed.txt`, Case 5.

Interpretation: この条件ではHarnessが処理を継続せず停止した。

Boundary: この結果は当該条件での停止のみを示し、universal security guaranteeではない。

## Real Gitleaks finding

Condition: Case 12 staged the synthetic fixture matched by the test-owned Gitleaks rule and confirmed the finding through real Gitleaks 8.30.1.

Expected: STOP / child exit 1.

Observed: Gitleaks emitted `leaks found: 1`; the probe exited 1; the Harness emitted `STOP: GSH_STOP_SECRET_SCAN: secret scan did not pass.` The case verdict was PASS.

Shell: PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444.

Evidence file: `powershell7-fail-closed.txt` and `windows-powershell51-fail-closed.txt`, Case 12.

Interpretation: この条件ではHarnessが処理を継続せず停止した。

Boundary: この結果は当該条件での停止のみを示し、complete secret detectionまたはuniversal security guaranteeではない。
