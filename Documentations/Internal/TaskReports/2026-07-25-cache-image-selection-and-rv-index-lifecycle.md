# 2026-07-25 — dyld cache 选镜像歧义修复 + RV 索引生命周期缺口复核与修复

承接同日的《NodeStore 迁移回归修复与三源基线建设》，处理其「待办」两项。

## 一、dyld cache 按名选镜像会静默选错（MachOSwiftSection）

### 问题

`swift-section --dyld-shared-cache -n SwiftUI` 对 iOS 27 模拟器 cache 输出 **0 字节 dump**、interface 只剩 4 行 import，**且退出码为 0**——完全不像失败。改用 `-p` 安装路径则正常输出 9.1MB。

### 根因

`MachOExtensions/DyldCache+.swift` 的名称匹配是

```swift
imagePath.lastPathComponent.deletingPathExtension == name
```

配合 `machOFiles().first(where:)` 的 first-match-wins。而 **cache 内叶名并不唯一**：iOS 27 同时存在

```
/System/Library/Frameworks/SwiftUI.framework/SwiftUI          ← 真正的框架
/System/Library/AccessibilityBundles/SwiftUI.axbundle/SwiftUI  ← 辅助功能 bundle
```

两者叶名都是 `SwiftUI`。模拟器 cache 先枚举到 axbundle，它几乎没有 Swift 元数据，于是「成功地」渲染出空内容。用 `strings` 扫 cache 的镜像路径表直接印证了这一点。

已验证的影响面：macOS 宿主 cache 的三件套、以及模拟器 cache 的 SwiftUICore / SwiftData，`-n` 与 `-p` 结果一致（只有 SwiftUI 撞名）。属既存缺陷，与 NodeStore 迁移无关。

### 修复

把「命中」从布尔改为**分级**（`DyldCacheImageSearchMode.matchRank(forImagePath:)`）：

| 级别 | 含义 |
|---|---|
| 0（`bestMatchRank`） | 位于 `<name>.framework` 目录内的规范二进制，含 macOS 的 `Versions/A/` 形态 |
| 1 | `.dylib` |
| 2 | 其它同叶名负载（`.axbundle` / `.bundle` / …） |

`bestMatch(in:)` 取最佳级；**遇到 0 级立即短路**，所以常见路径（精确 path、或框架二进制存在的名称查询）开销与原 first-match 相同，不是全量扫描。`.path` 精确匹配恒为 0 级，行为完全不变。平局保留最早者，对给定 cache 结果确定。

### 验收

- `Tests/MachOCachesTests/DyldCacheImageSearchTests.swift` 6 个用例全绿（纯路径运算，无需磁盘 cache；为此给 `MachOCachesTests` 加了 `MachOExtensions` 依赖）。
- 端到端：`-n SwiftUI` 从 0 字节变为 9,131,212 字节，且与 `-p` 生成的基线**逐字节一致**；`-n SwiftUICore`、`-n SwiftData`、macOS 宿主 cache 全部无回归。

## 二、RV 索引生命周期缺口（RuntimeViewer + 库）

前一轮由子 agent 静态审计提出四项嫌疑。本轮**逐项独立复核**，结论如下——其中一项证伪。

### 已证实并修复

**1. `removeSection` 本身不完整（真问题，且是关键的一处）**

`RuntimeSwiftSectionFactory.removeSection(for:)` 只删 `sections` 条目与候选 ID 表，**没有把 per-image 子索引器从聚合索引器摘掉**。而 `setupForFactory` 注册的正是 `indexer.addSubIndexer(...)`——聚合索引器（生命周期等于工厂，即等于所属 `RuntimeEngine`）持有的那份引用才是让整张 declaration 图（及其定义引用的 `NodeStore`）常驻的原因。所以即便调用 `removeSection`，也一寸内存都收不回。ObjC 侧 `RuntimeObjCSectionFactory` 同构。

**2. `addSubIndexer` 没有逆操作（真问题）**

RV 的 `RuntimeSwiftInterfaceIndexer` / `RuntimeObjCInterfaceIndexer` 只有 `addSubIndexer`。库侧 `SwiftDeclarationIndexer` 有 `removeSubIndexer(at index:)`（索引式），但没有身份式重载，RV 也没有包装。

修复：
- 库侧新增身份式 `SwiftDeclarationIndexer.removeSubIndexer(_:)`（`firstIndex(where: ===)` + 复用索引式实现）。
- RV 两个索引器各加 `removeSubIndexer(_:)`，Swift 侧同时撤销 upstream 注册。
- 两个工厂的 `removeSection` / `removeAllSections` 改为**先摘子索引器再删条目**。

链条成立的依据：库侧 `SwiftDeclarationIndexer.deinit` 在自己触发过构建时会驱逐 `SymbolIndexStore` 条目——所以摘掉最后一份引用 → per-image 索引器 deinit → SymbolIndexStore 驱逐 → NodeStore 真正释放。

**3. `removeSection` / `removeAllSections` 全无调用者（真问题）**

四个方法（Swift/ObjC × 单个/全部）此前只有定义。补了一个**由正确性驱动、而非产品策略**的触发点：`RuntimeEngine.stop()` 结束时调用 `releaseIndexedSections()`，把两个工厂的 section 全部释放。

理由：停掉的引擎通常随即析构、内存本会自然回收；但「通常」很脆弱——任何在 stop 之后仍持有引擎的东西（被放弃的探测 Task、悬挂的请求）都会把**用户打开过的每个镜像的完整索引图**一起钉住。显式释放把损失限定在引擎对象本身。工厂是 actor，故用 `Task` 跳出同步的 `stop()`，且只捕获两个工厂、不捕获 `self`。

*未采用*内存压力驱逐：RV 自身没有内存压力设施，且「浏览中突然丢弃全部索引」是产品级取舍（会带来重新索引的卡顿），不该由本次修复擅自决定。库侧 `SharedCache` 已有内存压力清理，可作为将来接线的先例。

**4. `pollUntilPeerAnswers` 的 `probeTask` 强捕获 engine（真问题）**

`RuntimeEngineManager.pollUntilPeerAnswers` 里的探测 Task 强捕获 `engine`，而函数注释自己就写明「abandoning (not awaiting) the stuck probe」——`probeTask.cancel()` 对忽略取消的 XPC send 无效，该 Task 可无限存活并钉住引擎及其索引图。改为 `[weak engine]` + 循环内 `guard let`：正常轮询期间调用方正 await 本函数，引擎必然存活；被放弃的探测在管理器释放引擎后自行退出。

### 复核后证伪（不修）

**`RuntimeMessageChannel` 无超时 continuation 会永久挂起** —— **不成立**。`finishReceiving` 在通道结束（FIN / 错误 / stop）时会**排空全部 `pendingRequests` 并逐个以错误 resume**，所以现实的失败模式（对端死亡 → 连接关闭）都会解除等待。唯一残留场景是「连接健康但对端对该请求永不回应」，属对端协议错误，且该 continuation 只持有小的 Codable 请求/响应值，不牵连 `NodeStore`。

因此**没有**加全局默认超时——生产侧四个连接类都已透传 `timeout`，只有 `RuntimeForwardingConnection` 的两处转发不传；给它们强加超时会打断合法的长时转发操作，是净损失。

## 验证

- MachOSwiftSection：`swift build` 通过；`DyldCacheImageSearchTests` 6/6 绿；`-n` 端到端对基线逐字节一致。
- RuntimeViewerCore：`swift build` 通过（含 `removeSubIndexer`、两个工厂、`RuntimeEngine.stop`）。
- RuntimeViewerPackages：`swift build` 通过（含 `probeTask` 弱捕获）。

**验证边界（须知）**：RV 的改动只做了编译级验证与代码推理，**没有**运行时验证——RV 是完整的 Xcode app，本轮未在 UI 中实际跑内存图对拍。三处修复都是「补齐缺失的逆操作 / 收紧捕获语义」，不改变正常路径行为；但「停止引擎后内存确实下降」这一效果仍需你在 RV 里实测确认。

## 差异

- 原计划把 RV 四项嫌疑全部当作缺陷修掉；复核后第 4 项证伪，改为记录理由而非改代码——避免为不存在的问题引入有害的默认超时。
- `removeSection` 的实现不完整这一点，是复核中新发现的（子 agent 只报告了「无调用者」），也是本轮最关键的修复：没有它，接线调用者也收不回内存。
