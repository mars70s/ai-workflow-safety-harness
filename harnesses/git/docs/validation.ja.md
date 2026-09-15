# Git Safety Harness Validation Record

[English](validation.md) | [日本語](validation.ja.md)

## Validation target

Git Safety Harness v0.1 pre-publication candidate。

review済みimplementation commit: `15fc65a7975cdf76cac313e312c2b122af421c0f`

後続のdocumentation-only publication commitはreview済みcommitと異なる場合があります。下記のsource/test hashは、implementationおよびtest candidateのvalidation identityとして維持されます。

## Sourceとtestのidentity

| File | SHA256 |
| --- | --- |
| `harnesses/git/src/git-safety-harness.ps1` | `D9B48AA478387AE50049D98CC777FE7745B7A59F12E574DEE74518F5C687719A` |
| `harnesses/git/tests/verify-fail-closed.ps1` | `68CA5A2D2CF3895B2C11F45A8FAC0B0873E152B5433D79988AD7EC7F332C4CD4` |
| `harnesses/git/tests/verify-success-path.ps1` | `56998713AAF2BCE2C2CEDE541BFA74F4772043D11FBC3A6CFB69C509C2554784` |

## Validation environment

- Git 2.54.0.windows.1
- PowerShell 7.6.5
- Windows PowerShell 5.1.26100.9444
- Gitleaks 8.30.1

これらはvalidated reference environmentであり、universal compatibility guaranteeではありません。

## Fail-closed results

- PowerShell 7: **14/14 PASS**
- Windows PowerShell 5.1: **14/14 PASS**
- Total: **28/28 PASS**

current test scriptは次のconditionを対象とします。

1. Case 1 — Write Setのscope外untracked file。
2. Case 2 — staged no-renames listingでのrename exposure。
3. Case 3 — Application discoveryでGitleaks unavailable。
4. Case 4 — expected repository rootをresolveできない。
5. Case 5 — discoverされたGitleaksをexecuteできない。
6. Case 6 — detached HEADとsymbolic branch unresolved。
7. Case 7 — configured push URLが複数。
8. Case 8 — repository外での実行とroot confirmation failure。
9. Case 9 — caseだけが異なる2つのstaged path。
10. Case 10 — expected rootとして別の有効なrepositoryを指定。
11. Case 11 — symbolic branchは有効だがexpected branchと不一致。
12. Case 12 — synthetic fixture ruleによる実際のreal-Gitleaks finding。
13. Case 13 — independently reachableなStage Set-specific STOP。
14. Case 14 — expected URLと一致しない、ちょうど1つのpush URL。

両shellでwrapperのfail-closed behaviorも検証しました。valid Harness STOPはexit 1、missing Harness path、parameter-binding failure、stale prior `$LASTEXITCODE`も、wrapper invocation boundaryを通ってexit 1になります。

## Success results

- PowerShell 7: **3/3 PASS**
- Windows PowerShell 5.1: **3/3 PASS**
- Total: **6/6 PASS**

positive caseは次のとおりです。

1. Success Case 1 — valid clean workflow。
2. Success Case 2 — 最初はunstagedのallowed changeでLF/CRLF stderr-isolation regressionを検証します。Harness関連Git pathでwarningを再現し、current Harnessがそれをpolicy dataとして解釈しないことを確認します。このpathの後はstaged scanがemptyになる場合があります。
3. Success Case 3 — non-empty allowed staged diffをreal Gitleaksでscanし、成功するpath。

## Additional validation

- M2 differential regression: historical pre-fix HarnessはGit stderrがpolicy dataを汚染したためSTOPし、current Harnessは同じrelevant fixtureをPowerShell 7とWindows PowerShell 5.1の両方でPASSしました。
- case-sensitive path collision: 両shellでPASS。
- real Gitleaks actual finding: 両shellでPASS。
- 両shellのwrapper contract: valid success => 0、Harness STOP => 1、missing Harness path => 1、parameter-binding failure => 1、stale prior `$LASTEXITCODE` => 1。
- no-global-config handling: 両shellでPASS。
- GUID-based fixture-root collision resistance: PASS。

測定または観測したevidenceには、unchanged synthetic remote refs、process-local PATH restoration、relevant validation中のglobal scope Git configuration unchanged、明示的なcase resultとexit code、source/test hash、そして対象caseでのreal Gitleaks execution/findingが含まれます。

## Evidence boundaries

### Measured / observed

- 上記のtest result、exit code、source/test hash。
- synthetic remote refsがunchangedであること。
- process-local PATHがrestoreされたこと。
- global-scope Git configurationの比較がunchangedであること。
- 対象caseでのreal Gitleaks executionとactual finding。

### Design-bound

- Harness自体は後続のpushまたはdeploymentを実行しません。
- testはsynthetic local remoteを使用します。
- 後続の運用動作はHarness boundaryの外側です。

### Not proven / out of scope

- Git、PowerShell、Gitleaksのuniversal compatibility。
- complete secret detection。
- allowed changeのsemantic correctness。
- raw Gitまたはshell accessが残る場合にHarnessをbypassできないこと。
- broad network inactivity。
- 任意のexternal enforcementのcorrectness。
- 後続のdeploy/API operationのsecurity。

boundedなlimitation setは[limitations.md](limitations.md)を参照してください。これはreference Harnessであり、independent security boundaryではありません。
