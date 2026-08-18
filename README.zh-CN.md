# pi-fast

**让 [pi coding agent](https://github.com/earendil-works/pi) 在 Windows 上启动快约 4 倍**——把 npm 安装的 CLI 重打包为单文件。

```
pi --version        之前: 3.2s   之后: 0.8s
pi -p (完整一轮)    之前: 5.0s   之后: 2.4s   (剩余为模型 API 延迟)
```

Windows 11 + Defender 实时扫描开启下单机实测,pi 0.84.2。方法学见 [docs/benchmark-notes.md](docs/benchmark-notes.md)(英文)。

## 问题成因

pi 以 npm 形态发布,是 tsc 直出的散装代码:**13,000+ 个小 JS 文件**。Node 启动时逐个打开、读取、解析,而 Windows 上每次文件打开都要过 Defender 实时扫描钩子。结果是启动几乎全是 I/O 等待——实测 **3.2s 墙钟,但 CPU 只用了 0.2s**——再叠加启动时版本检查的网络往返(慢网环境 +2.6s)。

单文件二进制的 agent(claude.exe 324MB、kimi.exe 150MB、codex 用 11 个文件的 npm 包装 Rust 二进制)在结构上就没有这个问题。

## 安装

要求:Windows + Node.js LTS(npm 在 PATH)。pi 本体缺失时会自动安装。

```powershell
powershell -ExecutionPolicy Bypass -File pi-fast.ps1
```

脚本会:①经 npm 安装/升级 pi(`-NoUpdate` 可跳过);②用 esbuild 把 `dist/cli.js` 打成单个 ~12MB ESM 文件(原生 `.node` 模块外置);③拷贝运行时外置依赖;④在 `%USERPROFILE%\.local\bin` 写入 `pi` / `pi.cmd` 启动器(该目录不在 PATH 时给出修复命令);⑤自检:版本一致性、PATH 解析顺序、实际启动耗时。

原 npm 安装原样保留——`~/.pi` 配置、session、扩展、skills 全部共享,不受影响。

## 更新

重跑同一脚本即可。npm 升级与重打包绑定为一次操作,不会出现「版本号显示新版、实际跑旧代码」的冻结陷阱。`pi-single.version` 标记文件记录 bundle 的真实版本。

## 代价

- 启动器内置 `PI_OFFLINE=1`:启动时不再查版本/包更新。想临时恢复,启动前把 `PI_OFFLINE` 设为**空值**。
- bundle 是冻结快照——安全修复需要重跑脚本。
- 自装扩展若 import 脚本未覆盖的第三方包,会报 `Cannot find module`:把该包从 pi 原安装的 `node_modules` 拷到安装目录的 `node_modules`(默认 `%LOCALAPPDATA%\pi-dist`)即可。

## 回滚

删除 `%USERPROFILE%\.local\bin\pi`、`%USERPROFILE%\.local\bin\pi.cmd` 和安装目录,即回到 npm 原版。

## 相关方案对比

| 方案 | 为什么在这里不够 |
|---|---|
| 微软 Dev Drive(ReFS + Defender 异步扫描) | 官方对 node_modules 慢的回应,但要单独一块卷,且只治扫描、不治 13k 文件打开 |
| 给 node 目录加 Defender 排除 | 有安全代价;仍是 13k 文件打开 |
| Node 22+ 的 `NODE_COMPILE_CACHE` | 实测对 pi 无效——瓶颈是文件 I/O,不是 V8 编译 |
| 厂商官方单文件构建 | 真正的解法;在 pi 官方出单文件构建前,本项目是过渡方案,见 [docs/upstream-issue-draft.md](docs/upstream-issue-draft.md) |

## 许可

[MIT](LICENSE)
