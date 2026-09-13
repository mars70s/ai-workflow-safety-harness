# Limitations

- An allowed file may still contain the wrong content.
- Ignored files are not full filesystem monitoring.
- `assume-unchanged` and `skip-worktree` have caveats.
- Unusual or non-ASCII filename handling may require stronger parsing.
- Direct Git invocation may bypass the Harness.
- A scanner cannot detect every secret.
- Verification is point-in-time.
- File or index changes after verification require re-checking.
- Git-external deploy and API actions are outside scope.
- Version-specific behavior may differ.

The Harness does not guarantee safety and does not replace OS permissions, credential separation, repository-side protection, secret-management controls, or Human review.
