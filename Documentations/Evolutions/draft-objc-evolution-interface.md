# Draft - `objc evolution --interface`：带演进标注的合并 ObjC 头文件

- **状态**: In Progress
- **创建日期**: 2026-10-28
- **最后更新**: 2026-10-28
- **关联提案**: [0013-swift-evolution-interface-builder](0013-swift-evolution-interface-builder.md)（Swift 一侧的同一种视图）；MachOObjCSection 一侧的库提案（由那边的会话撰写）
- **实现分支 / PR**: `feature/objc-evolution-interface`（worktree `.worktrees/MachOSwiftSection-ObjCEvolutionInterface`，自 `next` 分出）

## 摘要

`swift-section objc evolution` 现在只输出逐条变化的报告（每个声明一条存在位图加事件列表）和 JSON。读 AppKit 这种有几千个类的框架时，很难从中看出全貌。Swift 一侧早有 `evolution --interface`：把各版本合并成一份 interface，在有变化的声明上标出位图和事件。本提案给 ObjC 加上同一种视图：把 N 个版本的头文件按声明合并成一份，外观沿用 `objc dump` 的渲染，在类、协议、分类以及它们的方法、属性、ivar 上标出在哪一版加入、删除或修改，并可选地补上 `API_AVAILABLE` / `API_OBSOLETED`。CLI 和集成测试都做。

## 方案

- **分工**：合并和标注的渲染放在 MachOObjCSection。ObjC 的声明模型、头文件渲染器和现有的演进报告都在那里，由负责那个仓库的会话实现并发版，那边另有一份提案。本库只做接线：CLI 选项、SwiftSectionKit 的请求、集成测试和文档。
- **声明从哪来**：每个版本用现有的头文件渲染器（`objc dump` 和 RuntimeViewer 用的那一套）渲染声明，再按快照里的 identity key（`class:NSView`、`method:-initWithFrame:`、`property:-title`、`ivar:_style`、`adopts:…`）对齐，这样每条标注都和 `objc evolution` 报告里的一条 lineage 一一对应。「modified」沿用快照的 payload 比较，显示时给出两个版本各自渲染出的那一行。每个版本渲染完就释放它的索引器，不让 N 个索引器同时留在内存里：51 个版本的 AppKit 放不下。
- **标注**：照 Swift 的写法。文件头写出版本轴，以及位图每一位对应的版本。有变化的声明在行尾加 `// [●○●] added in X`、`removed in X` 或 `modified in X: 旧 → 新`；删掉的声明留在合并结果里原来的位置。加上 `--emit-available` 时再补一行可用性：只有引入的写 `API_AVAILABLE`，引入后又删掉的写 `API_OBSOLETED`（SDK 里这个宏带引入、废弃、移除三个版本）。一条标注表达不了的生命周期（删了又加回、只被修改过）不写这一行，位图注释照旧都在。平台从各输入的 `LC_BUILD_VERSION` 推出，也可以用 `--platform` 指定。
- **CLI**：`swift-section objc evolution --interface [--emit-available [--platform <name>]]`。`--interface` 与 `--json`、`--summary-only` 互斥。`--interface` 下每个输入都必须是二进制或 cache，传入快照 JSON 会报错退出：快照里没有渲染头文件所需的完整声明，这一点和 Swift 的 `--interface` 相同。`--fail-on-breaking` 照常生效。
- **集成测试**：在 `ObjCAPIEvolutionTests.swift` 里新加一组套件，版本轴与已有的报告格式套件相同（三版本轴，以及 51 个归档 cache），输出 `-ObjCEvolutionInterface.h`；归档套件带上 `macOS` 的可用性标注。报告格式的那组保留，Swift 一侧两种视图也都有。
- **同批更新**：`ObjCCommandLine.md`（及 `_zh`）、agent 插件里的 `swift-section-cli` skill 与 `references/objc.md`、演进账本。SwiftSectionKit 和 CLI 各加测试：选项校验、快照输入被拒，以及用 fixture 二进制完整跑通一次。
- **依赖**：MachOObjCSection 发出带这个渲染器的版本后，本库抬依赖下限；在那之前用本地兄弟依赖开发。

## 落地步骤

1. [x] **选项与校验**：SwiftSectionKit 的 `ObjCAPIEvolutionRequest` 加带标注头文件这种输出，可用性分「不写 / 从 `LC_BUILD_VERSION` 推断 / 指定平台」三种，平台按 ObjC 可用性宏的写法（`macos`、`ios`、`macCatalyst` …）；`--interface` 下的快照输入报错。CLI 加 `--interface`、`--emit-available`、`--platform` 及互斥校验，错误照现有措辞翻译成用法错误。两侧各加测试。这一步还没有渲染器，`--interface` 校验通过后报「渲染器尚未接入」。
2. [ ] **接上渲染**：对接 MachOObjCSection 的渲染接口（先用本地兄弟依赖），去掉第 1 步的占位；用 fixture 二进制完整跑通一次。
3. [ ] **集成测试**：`ObjCAPIEvolutionTests.swift` 新加一组套件，输出 `-ObjCEvolutionInterface.h`。
4. [ ] **文档**：`ObjCCommandLine.md`（及 `_zh`）、agent 插件的 `swift-section-cli` skill 与 `references/objc.md`、演进账本。
5. [ ] **依赖**：MachOObjCSection 发版后抬依赖下限，用远端依赖重新验证。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-28 | Created as Draft | 用户要的是在头文件上标出演进，而不是逐条报告；刚加的报告格式集成测试不是想要的形式 |
| 2026-10-28 | 声明沿用 `objc dump` 的渲染，不用快照里的签名行 | 用户选定：外观和 `objc dump`、RuntimeViewer 一致，有参数名、ivar 块和分组；代价是 `--interface` 只接受二进制或 cache |
| 2026-10-28 | CLI 和集成测试都做 | 用户选定，与 Swift 一侧一致：集成测试走的就是 CLI 背后的同一个接口 |
| 2026-10-28 | 用户批准，开始实现 | 状态改为 Accepted；精简提案原本没有落地步骤，按方案拆成五步，第 1 步不依赖 MachOObjCSection 的渲染器，先做 |
| 2026-10-28 | 第 1 步：平台推断失败用 ObjC 自己的错误类型 `ObjCAvailabilityPlatformInferenceError`；`--platform` 不校验拼写 | Swift 一侧的错误讲的是 `@available`，ObjC 要讲可用性宏，平台名也不同（`macos` 而不是 `macOS`，还多出 `driverkit`）；不校验拼写与 Swift 一侧一致，宏以后加平台也不用改 CLI |
