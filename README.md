# AI Workflow Safety Harness

Reference implementations of soft, fail-closed Safety Harnesses for AI-assisted workflows.

A Safety Harness constrains workflow behavior, but it is not an independent security boundary. Raw Git, shell, API, filesystem, or other direct access may bypass a Harness where independent controls do not constrain that access. Independent enforcement belongs to a separate Layer 3.

This repository accepts only implementations that conform to the Safety Harness design philosophy. It is not a general AI utility collection, tools dump, sandbox product, or complete security enforcement system.

## Current implementation

- `harnesses/git/`

## Status

PRE-PUBLICATION REVIEW

No production security guarantee is implied. License and publication decisions remain separate review gates.
