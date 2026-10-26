# SwiftPrivateDiscriminators 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 来历与取舍见提案 [0063-private-declarations](../../Evolutions/0063-private-declarations.md)；接进 dump 与 interface 见提案 [0074-private-declaration-source-files](../../Evolutions/0074-private-declaration-source-files.md)。本文负责全貌与分工。

## 模块定位

private discriminator 是编译器给 private / fileprivate 声明的名字加的一段 `_` 加 32 位大写十六进制，值是 `MD5(模块名 + 源文件名)`（Swift `lib/AST/Module.cpp` 的 `SourceFile::getPrivateDiscriminator`）。它解不回去，但可以猜：拿候选文件名算一遍 MD5，128 位摘要对上就是确认。本模块做的就是这件事：给出一个镜像里的 discriminator，反推它们来自哪个源文件。

它只管反推。名字里读得到哪些私有声明，由 `SwiftInspection` 的 `DemanglingNode.privateDeclarations` 回答，那是所有名字都要用的轻量接口；本模块带着 2007 个已知文件名的清单，只有要反推的宿主才依赖它。

宿主有两个：

- RuntimeViewer：侧栏的 `Private` 标签弹窗里显示 discriminator 与反推出的文件名，引擎进程按镜像持有一个 `PrivateDiscriminatorSourceFileIndex`，每次只问弹窗那一行的。
- `swift-section dump` / `interface` 的 `--emit-private-source-files`（`SwiftSectionKit` 的 `emitsPrivateDeclarationSourceFiles`）：打印前用 `recoverSourceFiles(ofEveryDeclarationIn:)` 把整个镜像一次求完，再经 `SwiftDeclarationRendering` 的 `PrivateDeclarationSourceFileProviding` 交给 dumper 和打印器，每个声明问一次、都是查表。注释的写法和「只标外层没有的 discriminator」的规则在 `PrivateDeclarationSourceFileComments`，两条输出共用。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 搜索本身（纯函数） | `PrivateDiscriminatorSourceFiles.swift`：五步候选、`Search`（摘要比对、合成文件、一段字节两种读法）、`Candidates`（从名字里读出的模块名与标识符）、`Digest128` |
| 2. 已知文件名 | `PrivateDiscriminatorSourceFiles+KnownFileNames.swift`，由 `Scripts/GenerateKnownSwiftSourceFileNames.sh` 生成，不手改 |
| 3. 按镜像取候选、记答案；整镜像批量求；给 dump / interface 的 provider | `PrivateDiscriminatorSourceFileIndex.swift` |

## 关键契约

- **结果只会「还原不出」，不会「还原错」。** 候选只决定找到多少；对上的摘要就是确认。所以按文本切词、拼文件名这些做法再粗糙，也只影响还原率。
- **候选由五步组成，按代价从低到高，要的 discriminator 全部找到就停：** 已知文件名；名字里的标识符与驼峰片段；同一 discriminator 下名字的词两两拼 `类型+分类`；片段接常见结尾词或复数；镜像里任一类型名接分类。还原不出的 discriminator 要把五步全部算完，所以最慢：Debug 构建里 SwiftUICore 一个要三四秒。
- **模块名候选：镜像文件名在前。** 哈希用的是框架自己的名字（`SwiftUICore`），不是类型打印出来的 ABI 名（`SwiftUI`）；后者从带私有声明的名字前缀里补上。局部类型的名字以类型开头（`Visitor #1 in SwiftUI.…`），第一个点之前不是标识符，不会被当成模块名。
- **一个模块名是另一个的前缀时，同一段哈希输入有两种读法**（`SwiftUICoreGlue.swift` 既是 SwiftUICore 的 `Glue.swift`，也是 SwiftUI 的 `CoreGlue.swift`）：一律按模块名的先后取前一种，结果不随候选的尝试顺序变。
- **镜像一层的候选**：索引器里 Swift 类型、协议、扩展的名字（`.interfaceTypeBuilderOnly`，不带 discriminator），加上 ObjC 类与协议名。以 `_Tt` 开头的 ObjC 名是 Swift 类型的运行时 mangled 名，Swift 名字已经覆盖，跳过。
  - 和 RuntimeViewer 原来用的侧栏对象表不是同一批。这里多了侧栏并进类型那一行的扩展（被扩展的类型或协议就在本镜像里），这些名字多半和类型名重复；少了侧栏列出的 C struct / union 名、ObjC 分类名和 `_Tt…` 名。
  - RuntimeViewer 提案里的还原率是 macOS 26.7 上用侧栏那批候选量的，本 index 没有重新量。搜索本身没有上限，所以候选多出来只会让还原出的变多。
  - 不扩大到符号表的全部标识符：RuntimeViewer 当时量过，只多三个百分点，候选却多一个数量级。
- **名字在第一次请求时才读，每个答案都记住**，还原不出也记。宿主按镜像持有，随镜像释放。
- **要打印整个镜像的宿主先批量求一次**：`recoverSourceFiles(ofEveryDeclarationIn:)`（`@_spi(Support)`，取一个索引器）把名字里的 discriminator 和符号索引里成员符号、索引器全局声明的 discriminator 一起交给一次搜索。逐个声明去问的话，每个还原不出的都要把五步候选全部算一遍；一起问时第 1、2、4 步只算一次。候选不变，只是要求的 discriminator 多了：一个只写了 `extension View { private func … }` 的文件，名字里看不到它的 discriminator。Release 构建下一次求完整个镜像，SwiftUICore 约 15 秒、SwiftUI 约 41 秒（macOS 27.2，interface 开关前后之差，数据见提案的「实测」），几乎全花在还原不出的那些上；第 5 步按 discriminator 各自独立，要提速可以从这里并行。
- **结果类型有两个**：搜索本身返回 `PrivateDiscriminatorSourceFiles.SourceFile`，给 dump / interface 的是 `SwiftDeclarationRendering` 的 `PrivateDeclarationSourceFile`，index 遵循 `PrivateDeclarationSourceFileProviding` 时换一下。没有把前者挪下去留 typealias：RuntimeViewerCore 开了 `MemberImportVisibility`，读挪走的类型的成员可能要多 import 一个模块。
- **名字在锁外读，搜索在锁内。** `PrivateDiscriminatorSourceFileIndex` 的状态全在一把 `NSLock` 下。
  - 读名字要打印镜像里的每个名字，而 AGENTS.md 规定不能持锁 demangle。
  - 请求可能来自 512 KB 栈的协作线程，所以整批名字放进 `StackSafeExecutor.withLargeStack` 里读，一批只切一次线程；栈够大的线程就地读。
  - 两个并发的首次请求各读一遍，后到的丢掉自己那份。搜索仍在锁内，所以同一镜像的两次请求只搜一次。
- **名字读完就放掉读名字的闭包。** 按索引器建的 index 不再握着索引器：镜像缓存要等最后一个索引器释放才回收（`SharedCacheRegistry`），index 却随镜像活着。
- **`SwiftDeclarationIndexer` 是 `@_spi(Support)`**，所以按索引器建 index 的两个初始化方法也是 `@_spi(Support)`；不用索引器的初始化方法（直接给名字的闭包）是公开的。

## 测试锚点

- `Tests/SwiftPrivateDiscriminatorsTests/PrivateDiscriminatorSourceFilesTests.swift`：每条规则各一个用例，都不带已知文件名，期望值是在代码之外用 `md5 -s` 算的（从 RuntimeViewer 搬来）。
- `Tests/SwiftPrivateDiscriminatorsTests/PrivateDiscriminatorSourceFileIndexTests.swift`，与运行的系统无关，在 CI 里跑：
  - 局部类型 fixture 的 `Fixture.swift`（`MachOFile` 与进程内两条路径）；
  - 名字只读一次，还原不出的不再搜（`searchCount`）；
  - 名字在大栈上读；
  - 两个并发的首次请求都读名字、只搜一次；
  - 名字读完放掉索引器；
  - 整镜像批量求只搜一次，之后每个都是查表；provider 答的就是搜到的，还原不出的答 `nil`、不再搜。
- 注释的写法与该标哪些：`Tests/SwiftDeclarationRenderingTests/PrivateDeclarationSourceFileCommentsTests.swift`（模块名不同、合成文件、还原不出、没有名字的私有声明、一个名字两个 discriminator、外层已有的不标）。
- 两条输出端到端：`Tests/SwiftSectionKitTests/PrivateDeclarationSourceFileRequestTests.swift`，SymbolTestsCore 上两个同名 `PrivateDoppelganger`（第二个文件 `PrivateDoppelgangersSecondFile.swift` 拼不出，正好测还原不出的写法），加 `LocalTypeFixture` 里公开类型 `Holder` 的私有方法 `hiddenValues()`。
- `Tests/SwiftPrivateDiscriminatorsTests/PrivateDiscriminatorSourceFileSystemImageTests.swift`，读运行中系统的 dyld shared cache，不进 CI，因为它的 discriminator 是 macOS 27.2 上取的：
  - Foundation 的 `__JSONEncoder` → `JSONEncoder.swift`；
  - SwiftUICore 的 `EnabledKey` → SwiftUICore 的 `Enabled.swift`，钉住模块名取镜像文件名。
- 名字经过的私有声明：
  - `Tests/SwiftInspectionTests/PrivateDeclarationsTests.swift`：逐个形状。
  - `Tests/SwiftIndexingTests/PrivateDeclarationsWholeTreeTests.swift`：不经过签名、也不是按位置命名的定义名，与另写的整树搜索逐个相同。

## 相关文档

- 提案：[0063-private-declarations](../../Evolutions/0063-private-declarations.md)、[0074-private-declaration-source-files](../../Evolutions/0074-private-declaration-source-files.md)（接进 dump 与 interface）
- 局部类型与占位名：[0062-local-type-context-names](../../Evolutions/0062-local-type-context-names.md)
