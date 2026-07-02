---
name: logging
description: Guide for adding, placing, and using logs in codebases. Use when Codex is asked to add or adjust logging, choose log locations, debug with logs, inspect runtime behavior, diagnose performance, or keep logs informative without slowing the app down.
---

# Logging

## Overview

Use logging to make runtime behavior explainable without turning the application into a disk writer. Prefer targeted, durable signals over noisy traces.

## Guidelines

- Write logs to standard app-appropriate locations first, such as the platform logs directory, an app-specific run directory, or a configured test directory.
- Fall back to a temporary directory when the preferred path is not writable.
- Keep logs out of source directories, watched build paths, hot UI layout paths, and tight loops unless they are gated or sampled.
- Include enough context to diagnose the issue: operation name, inputs that identify the work, counts, result state, failure reason, and timing when useful.
- Avoid logging sensitive content, full file bodies, secrets, credentials, or large payloads. Log paths, sizes, hashes, or counts when those are enough.
- Add logs around boundaries and state transitions: startup, file/session load, save, bridge calls, parser failures, recoverable errors, and slow operations.
- Use logs actively while debugging. Inspect the newest relevant log before guessing, and add temporary logs only when existing signals are not enough.
- Remove or demote temporary noisy logs before finishing, unless they are broadly useful and low-volume.
- Make logging cheap when compiled or configured off. Avoid constructing expensive log metadata before checking the logging gate if the local logger requires it.

## Debug Workflow

1. Find the active log location from the code, README, or app startup output.
2. Reproduce the issue and inspect the newest log files.
3. Add narrow logs at the smallest uncertain boundary.
4. Reproduce again and compare before/after signals.
5. Keep the logs that would help the next debugging pass; delete noise.

## Message Shape

Use stable key-value fragments when possible:

```text
operationName state=value path=/path/to/file count=3 elapsed_ms=12.4
```

Prefer `info` for normal lifecycle and performance breadcrumbs, and `error` for failures that require user attention or explain an aborted operation.
