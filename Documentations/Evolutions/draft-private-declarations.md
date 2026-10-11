# Draft - 私有声明：从名字取 discriminator，按镜像反推源文件

- **状态**: In Progress
- **创建日期**: 2026-10-11
- **最后更新**: 2026-10-11
- **关联提案**: [0062-local-type-context-names](0062-local-type-context-names.md)（占位名与 `LocalTypeNaming`）；展示一侧是 RuntimeViewer 的 [draft-private-discriminator-tag](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/feature/private-discriminator-tag/Documentations/Evolutions/draft-private-discriminator-tag.md)
- **实现分支**: `feature/private-declarations`（worktree `.worktrees/MachOSwiftSection-PrivateDeclarations`），基于本地 `next` 100da85c，要用 0062 的 `LocalTypeNaming`

## 摘要

RuntimeViewer 的侧栏给私有类型挂一个 `Private` 标签，点开列出 private discriminator，以及 discriminator 来自哪个源文件。这背后的两件事现在都由 RuntimeViewer 自己做：

- 从名字的 demangle 树里收集 `privateDeclName` 节点。
- 拿候选文件名算 MD5 去撞 discriminator，反推源文件。discriminator 就是 `MD5(模块名 + 源文件名)`。

用户要求这两件逻辑下沉到本库，RuntimeViewer 只管展示。0062 之后，RuntimeViewer 的第一件有两处错，都出在整树搜索上：

- 它把占位名 `(Visitor in $1a2b3c)` 里的 `$` 地址当成了 discriminator。
- 局部类型的编译器全名带着所在函数的签名，参数、返回值里的 private 类型也会被收进来。

本提案在本库提供三样东西：

1. 名字经过的私有声明。
2. 局部类型给读者看的名字。
3. 按镜像反推源文件。

## 方案

### 名字经过的私有声明

- 接口：`Node.privateDeclarations` 和 `NodeReference.privateDeclarations`，公开，放在 `SwiftInspection`，挨着 `LocalTypeNaming`。返回 `[PrivateDeclaration]`，每项有 `name` 和 `discriminator`，按阅读顺序排列并去重。
- 语义：显示名里读得到的私有声明。RuntimeViewer 打印显示名时不打印 discriminator，discriminator 就靠这份列表保留下来。`Private` 标签和源文件反推共用这一份，不拆成两个接口。
- 取法：整棵树前序搜索 `privateDeclName`，只有两处不进：
  - 函数、闭包这类上下文节点的签名部分，即参数标签、参数类型和返回类型的子节点。局部类型给读者看的名字（下一节）不打印它们。
  - 按位置命名的占位名（`localTypeNaming == .positionBased`）里 `$` 开头的那一段，它不是 discriminator。
- 结果：
  - 不带函数上下文的名字，结果和今天 RuntimeViewer 的整树搜索相同，特化类型的泛型实参、扩展的约束照旧算。
  - 局部类型所在的函数本身是 private 时，函数的 discriminator 算进去，`name` 是函数名，如 `readEntryList`。
- 不改成「沿上下文链每层取第一个子节点」：`.extension` 的子节点是 `[module, 被扩展的类型, 泛型签名?]`，`.anonymousContext` 是 `[name, parent, types]`（swift-demangling `Demangler.swift` 的 `demangleExtensionContext` 与 `Z` 分支）。两者的父级都不在第一个子节点，只取第一个会从扩展直接跳到模块，漏掉被扩展的类型。

### 局部类型给读者看的名字

- 接口：`DefinitionName.localTypeDisplayName`（暂名）。
- 对局部类型和嵌在局部类型里的类型返回：
  - 编译器命名的：不带模块名和参数类型，保留 `#1` 序号，如 `Visitor #1 in TableDataSource.performDrop(to:)`。和 interface 里局部类型声明前那行注释是同一种写法，两处改用同一个实现。
    - 这套写法今天在 `SwiftPrinting` 的 `SwiftDeclarationPrinter+Headers.swift` 里：`localTypeDeclarationComment` 是 package 级，它用的 `DemangleOptions.localTypeDeclarationComment` 是同一文件里 fileprivate 的。
    - 命名挪到 `SwiftDeclaration` 的 `DefinitionName`，打印器往下调它，依赖方向不变。
    - 按位置命名时注释里那句说明是注释的事，留在打印器里。
  - 按位置命名的：`TableDataSource.(Visitor in $1a2b3c)`。同一类型下的几个无名局部类型只靠这个 `$` 地址区分，所以保留它。
  - 两种写法都不打印真正的 private discriminator。
- 其余类型返回 `nil`。

### 按镜像反推源文件

- **位置**：新开一个 target（暂名 `SwiftPrivateDiscriminators`，放在 `Sources/Declaration/` 下，公开 product）。代码从 RuntimeViewer 的 `RuntimePrivateDiscriminatorSourceFiles` 搬过来。
- **算法不变**：
  - 候选按代价从低到高分五步：
    1. 已知文件名。
    2. 镜像名字里的标识符和其中的驼峰片段。
    3. 同一 discriminator 下的名字两两拼成 `类型+分类`。
    4. 第 2 步的候选接常见结尾词或复数 `s`。
    5. 镜像里任一类型名接第 3 步的分类词。
  - 要的 discriminator 全部找到就停。
  - 128 位摘要对上才算数，所以结果只会还原不出，不会还原错。
  - 合成文件的 discriminator 是 `MD5(所属文件的 discriminator + "SYNTHESIZED FILE")`，顺带一起解出。
- **两层接口**：
  - **纯函数**：输入要还原的 discriminator、模块名候选、名字（每个名字带上它经过的 discriminator）和已知文件名。RuntimeViewer 现有的测试原样搬到这一层。
  - **镜像一层**：用一个已经 `prepare()` 过的 `SwiftDeclarationIndexer` 来建。
    - 名字候选：索引器里 Swift 类型、协议、扩展的名字，加上镜像里 ObjC 类与协议的名字。
      - 和 RuntimeViewer 原来用的侧栏对象表不是同一批。这里多了侧栏并进类型那一行的扩展，即被扩展的类型或协议就在本镜像里的那些，它们的名字多半和类型名重复。
      - 这里也少了侧栏列出的 C struct / union 名、ObjC 分类名，以及 Swift 类在 ObjC 运行时里的 `_Tt…` 名；`_Tt…` 名对应的 Swift 名字已经在里面。
      - RuntimeViewer 提案里的还原率是 macOS 26.7 上用侧栏那批候选量的，本 index 没有重新量。
    - 模块名候选：镜像文件名（`SwiftUICore`，不是 ABI 名 `SwiftUI`），加上带私有声明的名字里的模块名。
    - 候选在第一次请求时建好。每个 discriminator 的结果都记下来，还原不出也记，同一个对象再问就不再算。
    - 线程安全：
      - 状态在一把锁下，名字却在锁外读。读名字要打印镜像里的每个名字，不能持锁 demangle。
      - 请求可能来自 512 KB 栈的协作线程，所以整批名字放在大栈上读。
      - 搜索在锁内，同一镜像的两次请求只搜一次。
      - 名字读完就放掉读名字的闭包，连同它握着的索引器。
      - 调用方按镜像持有它，镜像卸载时一起释放。
- **已知文件名清单**：2007 个文件名，是生成出来的 Swift 源文件。它和生成脚本 `GenerateKnownSwiftSourceFileNames.sh` 一起搬过来，照旧不手改。
- **MD5**：用 CryptoKit 的 `Insecure.MD5`。本库只支持 Apple 平台，最低系统版本与 CryptoKit 的要求一致。

### 没有询问就采用的假设

- 这次不给 `swift-section` 加子命令，要的话以后另提。
- 镜像一层的候选不扩大到符号表里的全部标识符。RuntimeViewer 量过，这样只多还原 3 个百分点，候选却多一个数量级，还原不出的那些会更慢。那次是在 macOS 26.7 上量的，用的是侧栏那批候选和最初的规则。
- 反推算法不改，还原率不提高。

### 测试

- **私有声明**：用 0062 的 `LocalTypeFixture`，`MachOFile` 与进程内两条路径都跑。覆盖这些形状：
  - private 类型；
  - 嵌在 private 类型里的类型；
  - private 函数里的局部类型，算上函数的 discriminator；
  - 非 private 函数里的局部类型，什么都不算；
  - 按位置命名的局部类型，`$` 那一段不算；
  - 函数签名里出现 private 类型，不算；
  - 特化类型的泛型实参里有 private 类型，算；
  - 嵌在受约束扩展里的类型，被扩展类型的 private 名字算；
  - 不带函数上下文的名字，结果与整树搜索逐个相同（`PrivateDeclarationsWholeTreeTests`）：
    - 名字取自 fixture 的两条读取路径和 SymbolTestsCore 的全部定义名，再加几条编译样本的名字。
    - 只取既不经过签名、也不是按位置命名的那些。
    - 对照的是一份另外写的整树前序搜索。
- **显示名**：编译器命名的、按位置命名的、嵌在局部类型里的类型，以及非局部类型（应返回 `nil`）。
- **反推**：
  - 纯函数一层：RuntimeViewer 的 `RuntimePrivateDiscriminatorSourceFilesTests` 搬过来，期望值照旧是在代码之外用 `md5 -s` 算的。
  - 镜像一层（`PrivateDiscriminatorSourceFileIndexTests`）：
    - fixture 的 `Fixture.swift`，两条读取路径；
    - 名字只读一次，还原不出的也不再搜；
    - 名字在大栈上读；
    - 两个并发的首次请求都读名字，只搜一次；
    - 名字读完，index 放掉索引器。
  - 系统镜像（`PrivateDiscriminatorSourceFileSystemImageTests`，不进 CI）：
    - Foundation：`__JSONEncoder` → `JSONEncoder.swift`。
    - SwiftUICore：`EnabledKey` → SwiftUICore 的 `Enabled.swift`，钉住「模块名取镜像文件名，不是 ABI 名」。
    - 这两个 discriminator 是 macOS 27.2 上取的。

### 文档

同一批更新：

- 新 target 的 module 文档；
- AGENTS.md 的模块列表；
- `Documentations/README.md` 的索引；
- 演进账本；
- 术语表：「私有声明」要不要登记，落地时判断。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-11 | Created as Draft：「你这边把私有鉴别器的逻辑下沉到MachOSwiftSection，RV这边只负责展示的逻辑」 | 用户的原始描述。RuntimeViewer 那份提案原本就定了以后下沉到本库，拆法与接法当时未定 |
| 2026-10-11 | 反推由 RuntimeViewer 在引擎进程里调用，新增一条引擎命令；候选由本库从镜像取，结果按镜像缓存 | 用户选择。推荐的是在 App 进程里拿侧栏对象表现算，不加引擎命令，未采纳 |
| 2026-10-11 | 局部类型给读者看的名字不带模块名和参数类型 | 用户选择：侧栏里同名的几个局部类型要能分开，过滤时也不该被函数签名里的类型命中 |
| 2026-10-11 | 局部类型所在函数是 private 时，函数的 discriminator 算进私有声明 | 用户选择，与「名字经过的私有声明都算」一致 |
| 2026-10-11 | 实现分支基于本地 `next`（100da85c，未推送） | 要用 0062 的 `LocalTypeNaming`。`next` 推不推由用户定 |
| 2026-10-11 | 私有声明的取法由「沿上下文链取」改为「整树搜索，跳过函数与闭包的签名和占位名的 `$` 段」；标签与反推共用一份 | MSS 会话指出两点。一是 `.extension`、`.anonymousContext` 的父级在第二个子节点，已在 swift-demangling 源码核实，只取第一个子节点会漏掉被扩展的类型。二是 RuntimeViewer 现有语义有意收进泛型实参。按「显示名读得到的」来定，局部类型的显示名本来就不印签名，两种用途在局部类型上一致，不必拆成两个接口 |
| 2026-10-11 | Accepted，随即转 In Progress | 用户批准：「开工」 |
| 2026-10-11 | private 构造器与下标的 `PrivateDeclaration.name` 取 `init` / `subscript` | 实现时发现：编译样本里 private 构造器的私有名只有 discriminator，印成 `Holder.(in _C017…).init(argument:)`，下标同理；不补名字的话弹窗里只剩一个空名 |
| 2026-10-11 | 用索引器建 index 的两个初始化方法标 `@_spi(Support)` | `SwiftDeclarationIndexer` 本身是 `@_spi(Support)`，公开接口不能出现它；直接给名字闭包的初始化方法保持公开 |
| 2026-10-11 | ObjC 名字跳过 `_Tt` 开头的 | 那是 Swift 类型在 ObjC 运行时的 mangled 名，Swift 名字已经覆盖，留着只多出无用的候选 |
| 2026-10-11 | index 的状态用一把 `NSLock`，一次请求从头持有到尾，不用 `@Mutex` 属性 | `@Mutex` 只保护单次读写；整个请求加锁，同一镜像的两次并发请求才只搜一次。最低部署版本 10.15，用不上 `Synchronization.Mutex` |
| 2026-10-11 | 测试的名字取真实 mangling：macOS 27.2 SwiftUI 的类型描述符符号，加一个现编的小样本（`swiftc -c -Onone -module-name Shapes`），discriminator 写在测试文档里 | 签名里带 private 类型、private 构造器与下标、受约束扩展这几种形状 SwiftUI 里找不到现成的；手写 mangling 只用于两参数字典，并先用 `swift-demangle` 核对 |
| 2026-10-11 | 先红后绿：把取法临时改回整树读取（读签名、收 `$`），`PrivateDeclarationsTests` 里针对这两点的 4 个用例全红，其余 8 个照绿；改回后全绿 | 证明测试抓得住 RuntimeViewer 原来那两处错 |
| 2026-10-11 | MSS 会话审查了本分支，列出六条，用户要求全部修、不留「不修」项；以下各行是这六条的落实 | — |
| 2026-10-11 | 名字改在锁外读，取代上面「一次请求从头持有到尾」那一行。新的流程：<br>1. 锁内只看有没有没答过的 discriminator、候选建没建，并取出读名字的闭包。<br>2. 锁外把整批名字放进 `StackSafeExecutor.withLargeStack` 里读。<br>3. 再上锁，候选还没建才装进去，后到的丢掉自己读的那份。<br>搜索仍在锁内，两次请求仍只搜一次 | 审查指出两点。一是持锁读名字违反 AGENTS.md 的「Do not hold a lock across a demangle」，先例是 NodeStoreMigrationOpenIssues #9。二是 RuntimeViewer 从 `nonisolated async` 方法里调用，跑在 512 KB 栈的协作线程上，每打印一个名字都要切一次线程。先红后绿：读名字时的栈从 536,576 字节变为 8 MB；两个并发的首次请求，原来只有一个读到名字，现在两个都读到 |
| 2026-10-11 | 候选建好后放掉读名字的闭包 | 审查指出：闭包握着索引器，而镜像的缓存要等最后一个索引器释放才回收（`SwiftDeclarationIndexer` 的 deinit），index 活多久，缓存就留多久。先红后绿：只剩 index 握着索引器时，请求之后索引器原来还在，现在会释放 |
| 2026-10-11 | 补齐「测试」一节答应过的测试：<br>- 不带函数上下文的名字逐个对照另写的整树搜索（`PrivateDeclarationsWholeTreeTests`）。<br>- index 加一个 internal 的搜索次数，测还原不出的 discriminator 第二次问不再搜。<br>- 系统镜像补上 SwiftUICore，与 Foundation 一起挪进单独的 `PrivateDiscriminatorSourceFileSystemImageTests`。<br>另外 `PrivateDeclarationsTests` 补上 `ExclusiveImageAccess` 声明；除系统镜像那个套件外，新套件都加进 CI 的 `--filter` | 审查指出「测试」一节有三处没兑现，还有一个套件漏了 fixture 互斥声明。临时改坏三处验证测试会红：<br>- 删掉记录「还原不出」的几行：两个用例变红。<br>- 扩展只读第一个子节点：对照套件里受约束扩展的样本名字变红。fixture 的定义名里没有落在扩展节点下的 private 名字，那部分不红。<br>- struct 自己的 private 名字不读：SymbolTestsCore 有 6 个名字变红。<br>系统镜像那个套件不进 CI：它的 discriminator 是 macOS 27.2 上取的，CI runner 跑的是别的系统版本 |
| 2026-10-11 | 术语统一写 private discriminator / discriminator，标题一并改；用户原话照录 | 仓库其余文档和术语表写「鉴别符」，0062 写英文。按文档风格要求，术语保留英文，不用中文自造词 |
| 2026-10-11 | 更正「候选与 RuntimeViewer 侧栏对象表是同一批，还原率不变」 | 两边不是同一批：本库多收了侧栏并进类型的扩展名字，少了侧栏列出的 C struct / union 名、ObjC 分类名和 `_Tt…` 名。还原率是 RuntimeViewer 在 macOS 26.7 上用旧候选量的，本 index 没有重新量。搜索本身没有上限，候选多出来只会让还原出的变多，少掉的那几类能不能还原出东西没有量过 |
| 2026-10-11 | 更正：`next` 已推到 origin（100da85c） | 「实现分支基于本地 `next`（100da85c，未推送）」那一行写的时候是这样，之后已经推送 |
