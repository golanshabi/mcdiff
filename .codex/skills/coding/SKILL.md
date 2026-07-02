---
name: coding
description: Guide for conservative code changes and code organization. Use when Codex is implementing, fixing, or refactoring code, especially to keep changes minimal, split large files, keep files below 1000 lines, improve readability, or add logically focused files.
---

# Coding

## Overview

Prefer the smallest code change that clearly solves the user-visible problem. Keep files readable by splitting responsibilities before a file grows past 1000 lines.

## Guidelines

- Read the surrounding code first and follow the repo's existing patterns.
- Add the minimal amount of code that satisfies the request and preserves behavior.
- Wherever possible use an external library, if a library already implements an algorithm there's no need to reimplement it.
- Avoid broad rewrites, speculative abstractions, and style churn unrelated to the task.
- Keep every source file below 1000 lines. If a file is near or over that limit, split it into logical files as part of the work.
- Prefer new files when they make ownership clearer: views, models, adapters, rendering, persistence, tests, and feature-specific helpers should not all live together by default.
- Name split files by responsibility, not by chronology. Examples: `Thing_Rendering.swift`, `Thing_+_Persistence.swift`, `ThingControls.swift`.
- Keep public API surface small. Use the narrowest access control that still works across split files.
- Preserve existing tests and add focused tests when behavior changes or regressions are likely.
- Verify with the repo's normal formatter, build, or test command before finishing when available.

## File Splitting

1. Identify cohesive regions by data ownership, UI construction, rendering, persistence, side effects, and tests.
2. Move code in chunks that can be named cleanly.
3. Keep shared state in one primary type file; put behavior in extensions or collaborators.
4. Adjust access control only as much as the split requires.
5. Run line counts after the split and continue until every file is under 1000 lines.

## Finishing Standard

Before finishing, check that the implementation is smaller and clearer than where it started, all touched files are below 1000 lines, and verification results are known.
