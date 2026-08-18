# Upstream issue draft

> 发到 https://github.com/earendil-works/pi/issues (用官方 issue 模板,保持简短具体;新贡献者的 issue 默认自动关闭,达标才会被重开,数据齐全是关键)。
>
> 标题建议:
> **Windows: docs/installer steer users to the slow npm path; the release binary is 5x faster — please recommend it for Windows**

---

## What happened

On Windows 11 (Defender real-time scanning on, no exclusions), stock npm-installed pi starts in **3.2s wall / 0.2s CPU** — almost pure file-I/O wait: the npm package is unbundled tsc output (13k+ files), and every file open goes through the Defender scan hook. Startup network checks (version + package update, 2.6s RTT on slow links) add on top.

For comparison on the same machine: codex 0.47s, the release binary `pi-windows-x64.zip` **0.63s**, an esbuild rebundle of `dist/cli.js` 0.8s.

## The gap

The single-file binary (`build:binary`, bun compile) already exists and ships for every release — thank you! But neither the README install section nor `pi.dev/install.sh` mentions it; both point Windows users at `npm install -g` / the npm-based curl installer, which is the slowest path on this platform.

## Suggestion

One of:

1. Add a note to the README/quickstart: *"On Windows, prefer the release binary from GitHub Releases"* (fastest, no Node needed), or
2. Make `install.sh` / a future `install.ps1` prefer the release binary on Windows, or
3. If npm must stay the default, consider a postinstall hint printing the binary alternative.

## Measurements (one machine, pi 0.84.2, best of 3)

| Variant | `--version` | full `-p` turn |
|---|---|---|
| npm stock | 3.2s | 5.0s |
| esbuild rebundle of `dist/cli.js` | 0.8s | 2.4s |
| **release binary `pi.exe`** | **0.63s** | 2.5s |

Fresh-copy cold start of the npm tree: 32–46s (Defender per-file scan tax). `NODE_COMPILE_CACHE=1`: no improvement (bottleneck is file opens, not V8 compile).

Full methodology: https://github.com/keros68/pi-fast/blob/main/docs/benchmark-notes.md

## Why an issue, not a PR

There is no code gap — `build:binary` and the release assets already exist. This is purely a docs/install-routing suggestion, so it belongs here for maintainer judgement.
