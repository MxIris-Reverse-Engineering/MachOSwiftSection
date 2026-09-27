# 0051 - `swift-section` 的 agent 插件：教 agent 用 CLI 的 skill 随仓库发布

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-27
- **最后更新**: 2026-09-27
- **所属愿景**: 无
- **关联提案**: [0036-objc-subcommands](0036-objc-subcommands.md)（`objc-section` 并入 `swift-section objc`；插件里的 `references/objc.md` 讲的就是它）
- **实现分支 / PR**: `feature/agent-plugin`，直接合入 `main`（只加插件与文档，不动库代码；合入后再把 `main` 合回 `next`）
- **配套文档**: README「Agent Plugin」一节（安装方法）；`AGENTS.md` 里「you are changing the swift-section CLI」一段（维护规则）

## 摘要

教 coding agent 用 `swift-section` 的那份 skill 此前只存在于维护者本机的全局配置里，别人装不到，
CLI 一改参数它也没人同步。本提案把它搬进本仓库，做成一个 Claude Code 与 Codex 都能直接从
GitHub 安装的插件 `swift-section`，并把「CLI 改了就改 skill、发版就改插件版本号」写进
`AGENTS.md`，版本号一致性交给 CI 把关。

## 方案

**布局**：

```
.claude-plugin/marketplace.json        Claude Code 在仓库根找 marketplace 的固定位置
.agents/plugins/marketplace.json       Codex 在仓库根找 marketplace 的固定位置
AgentPlugins/swift-section/
├── .claude-plugin/plugin.json
├── .codex-plugin/plugin.json
└── skills/swift-section-cli/
    ├── SKILL.md
    └── references/objc.md
```

- 两个工具各有自己的 marketplace 与 manifest 格式，互不识别，但都能指向同一个插件目录，
  `skills/` 只有一份。Codex 的 marketplace 里 `./AgentPlugins/…` 以 `.agents/` 所在目录
  （即仓库根）为基准解析，与 Claude Code 一致。
- **目录叫 `AgentPlugins/` 而不是两个工具示例里的 `plugins/`**：仓库根已有 SwiftPM 的
  `Plugins/`（`RegenerateBaselinesPlugin`），macOS 默认文件系统不区分大小写，两者会是同一个
  目录。
- 仓库打包约 30 MB，两个工具默认整仓克隆也能接受，不强制 sparse checkout。

**skill 内容**：以维护者本机那份为底，做了三类改动——

1. 删掉只在本机成立的内容（指向本机其他 skill 的交叉引用）。「何时用它、何时交给反汇编器」
   改写成通用说法：地址从这里拿，交给**同一构建**上打开的反汇编器。
2. `objc` 子命令的用法与坑原本写在本机另一个逆向 skill 里，整体搬进 `references/objc.md`，
   本机路径换成通用写法；在原有四条坑之外补上 `ObjCCommandLine.md` 里 diff 相关的两条
   （不分公私、快照格式版本）。
3. 补上 0.20.0 新增而原 skill 没写的 `--dependency-search-path` 与 `--infer-objc-overrides`。

skill 里出现的每个 `--flag` 都与已安装的 0.20.0 各子命令 `--help` 核对过，无一缺失。

**版本与更新**：`plugin.json` 的 `version` 跟 CLI 的 `BundledVersion.value` 走，起始 0.20.0。
两个工具都只在这个版本号变化时才给已安装的用户更新，所以发版忘改就等于用户永远停在旧 skill。
为此 `version-check.yml`（在合入 `main` 的 PR 上跑）新增一步：两个 `plugin.json` 的版本号
必须等于 `BundledVersion.value`，否则报错；`Version.swift` 顶部的发版提示同步加了这一条。

**校验**：`claude plugin validate`（插件与 `--strict` 的 marketplace）、Codex `plugin-creator`
的 `validate_plugin.py` 与 skill 的 `quick_validate.py` 均通过；另在一个临时 `CODEX_HOME` 里
实际执行了「添加 marketplace → 列出 → 安装」，skill 落进了插件缓存。Claude Code 侧未做实装测试
（`claude plugin` 命令行会写入用户的真实配置），只依赖官方校验器。

**未经询问取的假设**：插件名 `swift-section`、marketplace 名 `machoswiftsection`、skill 名沿用
`swift-section-cli`（在 Claude Code 里显示为 `swift-section:swift-section-cli`）；不附带仓库里的
`swift-section-mcp` 服务器，那是另一件事。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-27 | 把本机维护的 `swift-section-cli` skill 搬进本仓库，做成插件分发 | 维护者提出：交给仓库维护、让用户自己装，本机不再维护一份 |
| 2026-09-27 | 直接 PR 进 `main`，不等下个版本 | 维护者选择。只加插件与文档、不动库代码；skill 描述的正是 `main` 上已发布的 0.20.0；两个工具都跟踪默认分支，合入即可装 |
| 2026-09-27 | 同一插件目录同时放两个工具的 manifest | 两边格式互不识别但都支持相对路径指向同一目录，skill 只维护一份 |
| 2026-09-27 | 插件版本号由 CI 核对，而不只写进 `AGENTS.md` | 忘改的后果是用户静默停在旧版本、无人察觉；`version-check.yml` 本来就在发版 PR 上核对版本号，加一步成本最低 |
| 2026-09-27 | Implemented | 编号在落地 commit 里取：fetch 后 `main` / `next` 上最大为 0050 |
