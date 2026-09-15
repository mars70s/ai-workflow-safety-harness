# AI Workflow Safety Harness

[English](README.md) | [日本語](README.ja.md)

Reference implementations of soft, fail-closed Safety Harnesses for AI-assisted workflows.

## Why this exists

AI-assisted work needs explicit workflow checks before a later effect is allowed. This repository contains Layer-2 reference implementations that validate selected workflow state and stop when required conditions cannot be verified.

The model has three distinct layers:

1. **Layer 1 — Instruction:** the requested workflow and its authorization.
2. **Layer 2 — Safety Harness:** executable checks around a selected workflow boundary.
3. **Layer 3 — External Independent Enforcement:** controls outside the Harness that can constrain bypasses or the later effect.

This repository implements Layer-2 reference implementations. A Harness is not a sandbox or an independent security boundary. Raw Git, shell, API, filesystem, or other direct access may bypass it when separate Layer-3 controls do not constrain that access. It does not guarantee that AI-generated work is semantically correct.

This repository accepts only projects that conform to the Safety Harness design philosophy. It is not a general AI utility collection, tools dump, or complete security enforcement system.

## Current implementation

- [Git Safety Harness](harnesses/git/README.md)
- [Getting Started](harnesses/git/docs/getting-started.md)
- [Validation Record](harnesses/git/docs/validation.md)
- [Design](harnesses/git/docs/design.md)
- [Limitations](harnesses/git/docs/limitations.md)

## Background and article

The background, design intent, and validation approach behind this reference implementation are explained in more detail in the OSIIX.com article [“Safety Harness for AI-Assisted Git Operations — Checking the Write Set Before Execution”](https://osiix.com/en/library/ai-git-safety-harness.html).

## Status

PRE-PUBLICATION REFERENCE IMPLEMENTATION

No production security guarantee is implied. See the [MIT License](LICENSE). Publication and later operational actions remain separate gates.
