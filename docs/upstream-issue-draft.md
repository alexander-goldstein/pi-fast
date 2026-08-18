标题建议:Windows: startup is I/O-bound on 13k unbundled dist files; ship (or document) a single-file build

## 背景

Windows 11 上 pi 冷启动明显慢于 Claude Code / Codex / Kimi Code 等同为 CLI 的 agent。
在同一台机器实测:codex --version 0.47s,pi --version 3.2s(裸 node 0.12s)。
相关 issue:#6075(startup too slow)、#6794(model catalog refresh)、PR #7637(startup benchmark)。

## 归因(实测数据)

- `pi --version` 墙钟 3.2s,但 user+sys CPU 仅 ~0.2s → 纯 I/O 等待,不是计算
- pi 的 npm 包是 tsc 直出的散装 JS(dist/ + node_modules 共 13,181 个文件),
  Node 逐文件 open/read/parse,每次 open 都经过 Windows Defender 实时扫描钩子
- 对照:claude.exe / kimi.exe 是单文件原生二进制(324MB/150MB),codex 的 npm
  包只有 11 个文件(7KB launcher + Rust 二进制),它们天然免疫此问题
- 额外叠加:启动期版本检查网络往返(慢网环境 +2.6s,PI_OFFLINE 可关)

## 验证

用 esbuild 把 dist/cli.js 打成单个 12MB ESM 文件(原生 .node 模块外置):

- `--version`:3.2s → **0.8s**(4 倍)
- `-p` 全流程:5.0s → 2.4s
- 功能完整:TUI、主题(PI_PACKAGE_DIR 指回原安装读运行时 JSON)、扩展、skills 均正常

## 建议

1. 官方发布单文件构建(esbuild bundle 或 bun build --compile),Windows 用户受益最大
2. 或至少在文档的 Windows 一节给出本方案的等价做法与注意事项

(附:民间可用的打包脚本思路——bundle + 外置 pi-tui/clipboard 原生模块 +
PI_PACKAGE_DIR 指回原安装解析主题与版本号。)
