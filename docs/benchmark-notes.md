# Benchmark notes

All measurements from one machine — treat as indicative, not universal.

```
Windows 11, Defender real-time protection ON (no exclusions)
Node v22.23.1 (WinGet install)
pi @earendil-works/pi-coding-agent 0.84.2 (npm)
Default provider: zai-coding-cn (network latency matters for -p tests)
Timing: bash `time`, best of 3 after one warmup run unless noted
```

## Startup (`--version`, no model calls)

| Variant | Wall | CPU (user+sys) |
|---|---|---|
| bare `node -e 1` | 0.12s | ~0.01s |
| `codex --version` (11-file npm wrapper → Rust binary) | 0.47s | ~0.24s |
| stock `pi --version` (13,181 files) | 3.2s | **~0.2s** |
| stock `pi --version`, fresh copy of node_modules (Defender cold) | 32–46s | ~0.2s |
| bundled `pi --version` (pi-fast) | **0.8s** | ~0.06s |
| **official release binary `pi.exe` (bun compile, 108MB)** | **0.63s** | ~0.05s |

Key evidence for the I/O-bound diagnosis: 3.2s wall but 0.2s CPU on the stock
install. CPU is idle ~94% of startup — the process is waiting on file opens.
Writing ~13k new files (NODE_COMPILE_CACHE warmup, first bundle build) took
46s on the same directory, i.e. each first-open pays a Defender scan tax.

Same npm package tree copied to a different directory ran `--version` in 2.1s
vs 3.0s — the per-directory scan cache state is visible in the numbers.

## Network roundtrip at startup

`curl https://pi.dev/api/latest-version` from this network: **2.6s**. Stock
pi performs this check at interactive startup (plus package update checks).
`PI_OFFLINE=1` removes it entirely; that alone is a large fraction of the
"feels slow" experience on slow links.

## Full turn (`-p "..."`, includes model API roundtrip)

| Variant | Wall |
|---|---|
| stock pi, PI_OFFLINE unset | 5.0–11.9s (varies with link quality) |
| stock pi, PI_OFFLINE=1 | 4.9s |
| pi-fast bundle | **2.4s** |
| official release binary | 2.5s |

## What pi-fast changes

- 13,181 files → 1 bundle file (11.7MB) + ~11 external packages on disk
  (native `.node` modules and extension-resolved deps cannot be bundled)
- startup network calls disabled by default (`PI_OFFLINE=1`, overridable)

Note: pi's own releases ship a bun-compiled single-file binary with the same
external-packages architecture (`native/`, `node_modules/`, `theme/` next to
`pi.exe`) — measured 0.63s. It is the recommended solution for Windows users;
the docs just don't mention it.

## What it does NOT change

- `~/.pi` config, sessions, extensions, skills: untouched, shared with stock
- runtime behavior, tools, providers: identical code, just pre-bundled

## Things that did not work (measured)

- `NODE_COMPILE_CACHE=1`: no improvement (3.1–3.5s warm); first-run cache
  population cost 46s
- `npx pi`: ~25s — one order of magnitude worse than the global shim
