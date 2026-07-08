---
name: debugging
description: Evidence-first debugging workflow. Use when Codex needs to investigate bugs, crashes, regressions, performance problems, flaky behavior, runtime errors, or confusing behavior; inspect the newest relevant logs first according to the project's log timestamp or run-folder format, then create or update a Markdown debug report containing the investigation, relevant log excerpts, findings, changes, and verification.
---

# Debugging

## Overview

Use evidence before hypotheses. Always identify and inspect the newest relevant logs first, then preserve the investigation in a Markdown file so the next pass can continue from facts instead of memory.

## Required Workflow

1. Locate the active log source from the code, docs, app startup output, test output, or existing debug reports.
2. Determine the newest relevant log run according to the project's log format. Prefer the timestamp or run identifier encoded by the logger; use file modification time only as a fallback or tie-breaker.
3. Inspect the latest relevant log files before proposing a cause. If the issue crosses components, inspect all logs from the same run.
4. Create or update a Markdown debug report before making substantial code changes. Prefer an existing related file; otherwise create a focused file under `Docs/` when that directory exists, or `debug/` when it does not.
5. Record the exact log paths, reproduction steps, commands, relevant log excerpts, observed facts, inferences, hypotheses, changes made, and verification results.
6. If the latest logs are missing the needed signal, add narrow temporary logs at the smallest uncertain boundary, reproduce the issue, then append the new latest-log evidence to the report.
7. Distinguish facts from interpretation. Do not present an inference as proven unless the logs or verification directly support it.

## McDiff Logs

For this repo, the normal run folder is:

```text
~/Library/Logs/mcdiff/yyyy-MM-dd:HH:mm:ss_pid/
```

Each run usually contains:

```text
swift.log
cpp.log
```

Treat the latest run as the newest folder by the `yyyy-MM-dd:HH:mm:ss_pid` name format. Use modification time only when folder names are missing, malformed, or tied.

Log lines use this shape:

```text
yyyy-MM-dd HH:mm:ss [LEVEL] File:function:line - message
```

Performance messages usually include stable key-value fragments:

```text
PERF operation total=12.3ms count=4 phase=1.2ms
PERF input.operation elapsed_ms=12.3 blocks=10 rows=20
```

When debugging McDiff, inspect both `swift.log` and `cpp.log` from the same newest run unless the issue is clearly isolated to one layer.

## Debug Report Shape

Use concise sections like these:

````markdown
# <Issue> Debug Notes

Date: YYYY-MM-DD

Log run inspected:

```text
<absolute/path/to/run-folder/>
```

Files inspected:

```text
swift.log: <line count or relevant range>
cpp.log: <line count or relevant range>
```

## Issue

<User-visible symptom and reproduction steps.>

## Relevant Logs

```text
<short excerpts with file:line references or timestamps>
```

## Findings

<Facts proven by logs or verification.>

## Hypotheses

<Clearly marked inferences and what would confirm them.>

## Changes

<Code or logging changes made during this pass.>

## Verification

<Commands run, reproduction results, remaining uncertainty.>

## Next Steps

<Follow-up logs, tests, or fixes.>
````

Keep log excerpts short and relevant. Summarize noisy regions, but include enough exact lines for another debugging pass to verify the reasoning.
