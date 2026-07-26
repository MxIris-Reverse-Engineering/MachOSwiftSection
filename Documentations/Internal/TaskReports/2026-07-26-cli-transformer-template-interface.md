# 2026-07-26 给 swift-section 补注释模板的命令行入口

## 问题

用户要求：`swift-section` 的注释内容应当允许用户传模板自定义输出格式，走 `Transformer` 替换，跟 RuntimeViewer 一样；判断"逻辑应该都有了，就差一个接口"。

## 调研

先摸清库侧到底齐不齐。结论是用户的判断准确：

- `Transformer.SwiftConfiguration` 聚合五个 Swift 侧注释模块（`swiftFieldOffset` / `swiftVTableOffset` / `swiftMemberAddress` / `swiftTypeLayout` / `swiftEnumLayout`），每个模块都有 `template` 字段、`Token` 枚举、`Templates.all` 内置命名模板清单。
- 该聚合是 `Codable` 且缺 key 容错，属性名即存储 key，与 RuntimeViewer 此前用 MetaCodable 持久化的 JSON 同构——意味着 RuntimeViewer 存的配置可以原样喂进 CLI，不需要任何转换层。
- 接线两侧都在：`SwiftDeclarationRendering` 的 `DeclarationRenderConfiguration.applyTransformers(_:)`（dump 路径）与 `SwiftPrinting` 的 `SwiftDeclarationPrintConfiguration.applyTransformers(_:)`（interface 路径）。

缺口确实只在 CLI：

- `dump` 只有 `--enum-layout-style`，五个预设之一，且要配 `--emit-enum-layout` 才有输出。
- `interface` 完全没有接 transformer，且连 `--emit-type-layout` / `--emit-enum-layout` 都没暴露（打印配置本身有这两个字段，静态 layout provider 也由 `SwiftDeclarationPrinter.staticFieldLayoutProvider()` 按需自建，纯粹是 CLI 漏了）。

## 最终方案

动手前就两个决策点问了用户，均取推荐项：CLI 入口三层全做；`interface` 顺带补齐两个 emit 开关。

方案写在 [CLITransformerTemplateInterface.md](../CLITransformerTemplateInterface.md)，要点：

1. **三层入口**，后层覆盖前层——`--transformer-config <json>`（RuntimeViewer 同构配置文件）→ `--enum-layout-style`（整模块预设）→ 逐模块模板/进制选项。
2. **模板值二义消解**：含 `${` 当字面模板，否则按内置模板名查（归一化：小写、去空格/连字符/下划线）。查不到**报错**，不退化成字面模板。
3. **`isEnabled` 驱动 emit 开关**：最终配置里启用的模块自动打开它渲染的那类注释。
4. **`transformer` 子命令**做发现性：`tokens` / `templates` / `config`。

## 实际执行

按设计实现，没有偏离。落地文件：

- 新增 `Sources/swift-section/Models/TransformerOptionGroup.swift`——参数组 + `TransformerTemplateResolver`（模板名解析）+ 两个 `applyTransformersEnablingCommentKinds` 扩展（分别挂在 `DeclarationRenderConfiguration` 与 `SwiftDeclarationPrintConfiguration` 上）。
- 新增 `Sources/swift-section/Commands/TransformerCommand.swift`——`TransformerModuleSelector` 把五个模块的 token 集合与模板清单收拢成统一的描述结构，三个子命令共用。
- `DumpCommand`：删掉独立的 `--enum-layout-style` 声明与 `ExpressibleByArgument` 一致性（移进参数组），换成 `@OptionGroup(title: "Comment Templates")`。
- `InterfaceCommand`：加两个 emit 开关，把原先内联构造的 `printConfiguration` 拆成 `var` 以便应用 transformer。
- `SwiftSectionCommand`：注册 `TransformerCommand`。
- `Package.swift`：新增 `SwiftSectionCommandTests` 测试 target（依赖可执行 target `swift-section`，本仓首个 CLI 测试 target）。

三处实现细节值得记：

**参数组返回 `Transformer.SwiftConfiguration?` 而不是总返回一个配置。** 没传任何模板选项时返回 `nil`，调用方完全不碰渲染配置。这是保证默认输出逐字节不变的机制——如果总返回配置并无条件 `applyTransformers`，五个禁用模块会把闭包槽位全部写成 `nil`，虽然结果等价，但"默认路径不经过 transformer 代码"这条性质会丢，日后改动难以论证安全。

**emit 开关用 OR 合并而非直接赋值。** `printTypeLayout = printTypeLayout || commentFlags.printTypeLayout`。若直接赋值，`--emit-type-layout --field-offset-template range` 会把用户显式要的 type layout 注释关掉——模块禁用只意味着"用内置渲染"，不意味着"不要这类注释"。这条有专门的测试 pin 住。

**布尔选项声明为 `Bool?`（`@Flag(inversion: .prefixedNo)`）。** 不传即 `nil`，保留下层取值。若用 `Bool` 带默认值，`--transformer-config` 文件里设的 `useHexadecimal` 会被"用户根本没传的开关"冲掉。

## 验证

- `swift build --build-tests`：无 error 无 warning。
- `swift test --skip IntegrationTests`：1269 tests / 242 suites 全通过，其中新增 `TransformerOptionGroupTests` 14 项（模板名解析的五种拼写、字面模板、未知名字报错、三层优先级、隐式启用、配置文件往返、不可读文件报错、emit 开关映射与 OR 合并）。
- CLI 冒烟（fixture：`SymbolTestsCore.framework`）：
  - `transformer tokens --module field-offset` / `templates --module field-offset` 输出正常；
  - `transformer config --field-offset-template range --enum-layout-style compact` 输出的 JSON 中两个模块 `isEnabled: true` 且模板已展开；
  - `--field-offset-template rnge` 报错并列出可用名字；
  - `dump --field-offset-template range`（不配 `--emit-field-offsets`）输出 `// 0x0 ..< 0x10`，隐式启用生效；
  - `dump --transformer-config <file>` 往返后输出 `// [0x0, 0x10)`；
  - `dump --enum-layout-style inline` 输出单行 case 注释；
  - `interface --emit-type-layout --field-offset-template labeled` 产出 355 处 type layout 注释与 `// offset: 0x10` 形式的字段偏移。
- README 里写的每条示例命令都实际跑过，包括 `'@${startOffset}'` 字面模板与 `strategyOnly` / `inlineSummary` 这类去空格的模板名。

## 与计划的偏差

一处：测试构造 `DeclarationRenderConfiguration` 时用了无参 `init()`，但该类型是 `@MemberwiseInit` 且 `demangleResolver` 无默认值，编译报缺参。改用既有的 `.demangleOptions(.default)` 工厂。无设计影响。
