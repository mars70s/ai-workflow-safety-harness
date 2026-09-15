# AI Workflow Safety Harness

[English](README.md) | [日本語](README.ja.md)

AI支援ワークフローのための、ソフトなfail-closed型Safety Harnessのリファレンス実装です。

## このリポジトリの目的

AI支援による作業では、後続の効果を許可する前に、ワークフローの状態を明示的に確認する必要があります。このリポジトリには、選択したワークフローの状態を検証し、必要な条件を確認できない場合に停止するLayer 2のリファレンス実装を収録しています。

このモデルは、次の3つの層で構成されます。

1. **Layer 1 — Instruction:** 要求されたワークフローと、その認可を定める層。
2. **Layer 2 — Safety Harness:** 選択したワークフローの境界で検査を実行する層。
3. **Layer 3 — External Independent Enforcement:** Harnessのバイパスや、その後に発生する効果を制約し得る、Harness外部の独立した制御の層。

このリポジトリが実装するのはLayer 2のリファレンス実装です。Safety Harnessはsandboxでも、独立したsecurity boundaryでもありません。別のLayer 3制御がアクセスを制約しない限り、raw Git、shell、API、filesystemなどの直接アクセスでバイパスされる可能性があります。また、AI生成物の意味的な正しさを保証するものでもありません。

このリポジトリには、Safety Harnessの設計思想に適合する実装だけを収録します。一般的なAIユーティリティ集やツールの寄せ集めではなく、完全なsecurity enforcement systemでもありません。

## 現在の実装

- [Git Safety Harness](harnesses/git/README.ja.md)
- [Getting Started](harnesses/git/docs/getting-started.ja.md)
- [Validation Record](harnesses/git/docs/validation.ja.md)
- [Design](harnesses/git/docs/design.md)
- [Limitations](harnesses/git/docs/limitations.md)

## 背景と解説記事

このリファレンス実装の背景、設計意図、検証の考え方については、OSIIX.com の[「AI支援Git運用のSafety Harness — Write Setを実行前に検査する」](https://osiix.com/library/ai-git-safety-harness.html)で詳しく説明しています。

## Status

PUBLIC REFERENCE IMPLEMENTATION

本番運用における安全性を保証するものではありません。[MIT License](LICENSE)を参照してください。公開と、その後の運用操作は、それぞれ別の判断段階です。
