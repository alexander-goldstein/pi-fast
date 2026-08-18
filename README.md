# pi-fast

**Make the [pi coding agent](https://github.com/earendil-works/pi) start ~4x faster on Windows** by rebundling the npm-installed CLI into a single file.

```
pi --version        before: 3.2s   after: 0.8s
pi -p (full turn)   before: 5.0s   after: 2.4s   (rest is model API latency)
```

Measured on Windows 11 with Defender real-time scanning on, one machine, pi 0.84.2. See [docs/benchmark-notes.md](docs/benchmark-notes.md) for methodology.

## The problem

pi ships on npm as unbundled tsc output: **13,000+ small JS files**. Node opens, reads and parses every one of them at startup, and on Windows every file open goes through the Defender real-time scan hook. The result is startup that is almost pure I/O wait — measured **3.2s wall clock but only 0.2s CPU** — plus a version-check network roundtrip (2.6s on slow links) on top.

Single-binary agents (claude.exe 324MB, kimi.exe 150MB, codex's 11-file npm wrapper around a Rust binary) don't have this problem structurally.

## Install

Requirements: Windows, Node.js LTS with npm on PATH. (pi itself is installed automatically if missing.)

```powershell
powershell -ExecutionPolicy Bypass -File pi-fast.ps1
```

The script:

1. installs or upgrades pi globally via npm (skip with `-NoUpdate`)
2. bundles `dist/cli.js` into one ~12MB ESM file with esbuild (native `.node` modules stay external)
3. copies the runtime externals (pi-tui, clipboard native, packages used by extensions)
4. writes `pi` / `pi.cmd` launchers into `%USERPROFILE%\.local\bin` and warns with a fix command if that dir is not on PATH
5. verifies: version consistency, PATH resolution order, actual startup time

The original npm install stays untouched — everything else (`~/.pi` config, sessions, extensions, skills) is shared and unaffected.

## Update

Re-run the same script. It upgrades the npm package and rebuilds the bundle together, so you can never end up running a stale bundle that reports a new version number (the classic frozen-snapshot trap). A `pi-single.version` marker file records what the bundle actually is.

## Caveats

- `PI_OFFLINE=1` is set in the launchers: no startup version/package checks. To start once with them back, set `PI_OFFLINE` to an *empty* value before launching.
- Bundles are frozen snapshots — security fixes need a re-run.
- A user extension importing a third-party package not covered by the script will fail with `Cannot find module`. Copy that package from pi's npm install `node_modules` into the install dir's `node_modules` (default `%LOCALAPPDATA%\pi-dist`).

## Rollback

Delete `%USERPROFILE%\.local\bin\pi`, `%USERPROFILE%\.local\bin\pi.cmd`, and the install dir. You are back on the stock npm install.

## How it works / related approaches

| Approach | Why it isn't enough here |
|---|---|
| Microsoft Dev Drive (ReFS + async Defender) | Official answer for slow node_modules, but needs its own volume and only addresses scanning, not 13k file opens |
| Defender exclusion for node dirs | Security tradeoff; still 13k file opens |
| `NODE_COMPILE_CACHE` (Node 22+) | Measured: no improvement for pi — the bottleneck is file I/O, not V8 compile |
| Vendor-shipped single-file binaries | The real fix; this project is a stopgap until pi ships one. See [docs/upstream-issue-draft.md](docs/upstream-issue-draft.md) |

The bundling trick itself is standard esbuild; the interesting parts are handling runtime asset resolution (`PI_PACKAGE_DIR` pointing back to the real install for themes/version), keeping native modules external, and making npm upgrade + rebuild one atomic operation.

## FAQ

**Does it change what pi can do?** No. Same code, same config, same `~/.pi`. Only module loading and startup network calls differ.

**I launch pi from another tool (Coffee CLI, etc.)** — as long as `.local\bin` precedes the npm dir on PATH, the launcher wins transparently. The script's verification step checks exactly this.

**Does it work if npm prefix / Node install moved off C:?** Yes — every path is resolved at run time via `npm root -g`; nothing is hardcoded.

**ARM64 Windows?** Native module selection follows `node -p process.arch` (same rule npm uses for optionalDependencies).

## License

[MIT](LICENSE)
