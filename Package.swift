// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

@preconcurrency import PackageDescription
import CompilerPluginSupport
import Foundation

func envEnable(_ key: String, default defaultValue: Bool = false) -> Bool {
    let value = Context.environment[key]
    guard let value else {
        return defaultValue
    }
    if value == "1" {
        return true
    } else if value == "0" {
        return false
    } else {
        return defaultValue
    }
}

extension Product {
    static func library(_ target: Target) -> Product {
        .library(name: target.name, targets: [target.name])
    }

    static func executable(_ target: Target) -> Product {
        .executable(name: target.name, targets: [target.name])
    }
}

extension Target.Dependency {
    static func target(_ target: Target) -> Self {
        .targetItem(name: target.name, condition: nil)
    }

    static func product(_ dependency: Self) -> Self {
        dependency
    }
}

let usingLocalDependencies = envEnable("USING_LOCAL_DEPENDENCIES")

extension Package.Dependency {
    enum LocalSearchPath {
        case package(path: String, isRelative: Bool, isEnabled: Bool = usingLocalDependencies, traits: Set<PackageDescription.Package.Dependency.Trait> = [.defaults])
    }

    static func package(local localSearchPaths: LocalSearchPath..., remote: Package.Dependency) -> Package.Dependency {
        let currentFilePath = #filePath
        let isClonedDependency = currentFilePath.contains("/checkouts/") ||
            currentFilePath.contains("/SourcePackages/") ||
            currentFilePath.contains("/.build/")

        if isClonedDependency {
            return remote
        }
        for local in localSearchPaths {
            switch local {
            case .package(let path, let isRelative, let isEnabled, let traits):
                guard isEnabled else { continue }
                let url = if isRelative {
                    URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentFilePath))
                } else {
                    URL(fileURLWithPath: path)
                }

                if FileManager.default.fileExists(atPath: url.path) {
                    return .package(path: url.path, traits: traits)
                }
            }
        }
        return remote
    }
}

let isSilentTest = envEnable("MACHO_SWIFT_SECTION_SILENT_TEST", default: false)

var testSettings: [SwiftSetting] = []

if isSilentTest {
    testSettings.append(.define("SILENT_TEST"))
}

var dependencies: [Package.Dependency] = [
    .MachOKit,
    .MachOObjCSection,
    .MachOKitExtensions,
    .Demangling,
    .Semantic,
    .Capstone,

    .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0" ..< "605.0.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.1"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.2.0"),

    .package(url: "https://github.com/p-x9/AssociatedObject", from: "0.13.0"),
    .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", from: "0.17.0"),

    .package(url: "https://github.com/gohanlon/swift-memberwise-init-macro", from: "0.6.0"),

    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),

    // The SDK index `SwiftTypeNameResolution` resolves `__C` types with, moved
    // out of this package (proposal swift-type-indexing-package). Its sources
    // are all `#if os(macOS)`, so targets depend on it with a macOS-only
    // condition. 0.1.1 closes each module interface it generates once read:
    // with 0.1.0, `--resolve-c-module-names` grew SourceKitService to tens of GB.
    // 0.2.0 answers which module declares a Swift type the SDK moved
    // (`@_originallyDefinedIn`), for `--resolve-moved-type-modules`.
    .package(
        local: .package(
            path: "../swift-type-indexing",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-type-indexing",
            from: "0.2.0",
        ),
    ),

    // CLI
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),

    // Testing
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.9"),
]

extension Package.Dependency {
    static let MachOKit = Package.Dependency.package(
        local: .package(
            path: "../MachOKit",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOKit.git",
            // 0.54.101 is the fork's release over upstream 0.54.0. It keeps the
            // fixes the 0.52 line needed: no chained-fixup starts read for a
            // segment that has none, which crashed on a dylib with no `__DATA`
            // segment; no rebase target for a slot holding no pointer instead
            // of a trap; and a file handle's identity released with the
            // handle, which MachOObjCSection keys its mapping on. It also
            // reads an image without an export trie as exporting nothing:
            // 0.53.0 through 0.54.100 trapped there, and the ObjC ancestor
            // lookup reads the exports of every image it walks, the iOS 15.5
            // simulator's UIKit among them. MachOObjCSection and
            // MachOKitExtensions require it as well. 0.55.101 gives a file not
            // read out of a dyld cache no cache instead of opening its path as
            // one on every `cache` access: offline reading of a standalone file
            // spent two thirds of its time reopening the file. 0.55.102 hands
            // over the bytes it mapped a file into (`fileBytes`), which every
            // `MachOFile` read now goes through, and remembers a dyld cache's
            // mapping tables and its main, full and symbol caches safely when
            // several threads first read one image at once: two indexes built
            // on one image crashed in `mappingInfo(for:)`.
            from: "0.55.102",
        ),
    )

    static let MachOKitExtensions = Package.Dependency.package(
        local: .package(
            path: "../MachOKitExtensions",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOKitExtensions",
            // 1.0.0 no longer exports the throwing `init(bitPattern:)`, which
            // Utilities now declares; an earlier release would make every
            // call ambiguous. 1.1.0 keys an image read from a dyld cache by
            // its cache too (`dyldCacheImage`), which `SharedCacheKey` hashes.
            // 1.1.1 builds each dyld sub-cache once instead of on every read
            // that crosses into another cache file, and hands back the same
            // instance each time.
            // 1.1.2 adds `FullDyldCache.cachedHost`, the system cache opened
            // once per process rather than once per dependency locator.
            // 1.3.0 adds `MachOReaderWrapper`, through which every reader-kind
            // question (`asMachOImage`, `asMachOFile`, `underlyingReader`)
            // sees through a host's wrapper type. 1.3.1 grows the memos of
            // `resolveRebase(fileOffset:)` / `resolveBind(fileOffset:)` in
            // place, where each new entry used to copy the whole dictionary.
            // 1.3.2 stores a file's `identifier` and its bind index once:
            // threads reading a new file for the first time each stored their
            // own, freeing the value another thread was still reading, and
            // `SharedCacheKey` reads the identifier on every lookup.
            // 2.0.0 carries MachOReading and MachOResolving, which used to be
            // targets of this package; earlier releases do not have them.
            // 3.0.0 leaves Swift symbol names to this package: `SwiftSymbols`
            // defines `SymbolLanguage.swift` and registers it when the image
            // loads (proposal split-symbol-language).
            // 3.2.0 ships the test support this package builds on: the
            // `MachOFixtureSupport` and `MachOTestingSupport` products.
            from: "3.2.0",
        ),
    )

    static let MachOObjCSection = Package.Dependency.package(
        local: .package(
            path: "../MachOObjCSection",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/MachOObjCSection.git",
            // 0.8.108 decodes the pointer slots of a dyld cache's method lists:
            // earlier releases trapped on every image of the macOS 14.4-15.3.2
            // caches and lost protocol method names on older ones. 0.8.109
            // stops remapping a sub-cache file on every read of a cache opened
            // from its main file alone. 0.8.110 reads the classes a simulator
            // runtime's frameworks bind to their own exports (`-interposable`),
            // which the static layout engine and the ObjC ancestor chain need,
            // and names a legacy LC_DYLD_INFO file's bound superclass itself.
            // 0.8.111 reads the property and protocol lists a macOS 26.4+ cache
            // keeps in another file than the image's header: `objc` lost every
            // instance property and adopted protocol of a class other images
            // extend, such as NSView. 0.8.200 merges upstream 0.8.2 and reads
            // every list an image attaches to a class, not just its first:
            // `_UTCoreType` lost the methods of its second list. 0.8.201
            // takes the classes without a class object a host supplies
            // (`ObjCSuppliedClass`): generic Swift classes and the ones
            // `__objc_stublist` registers, read from Swift metadata here.
            // 0.8.202 reads the method names of a macOS 11 dyld cache, whose
            // relative method lists count a selector from the name field
            // itself: the selector base it used to add only exists from
            // macOS 12, so every class and category method of an 11.x cache
            // read as garbage. 0.8.204 adds `ObjCEvolutionInterfaceBuilder`,
            // the merged and annotated header `objc evolution --interface`
            // prints; 0.8.203 carried it too, but crashes the Swift 6.3
            // compiler of Xcode 26. 0.8.205 compares a version made up of a
            // group of images (`evolution(ofImageGroups:versions:)`,
            // `addVersion(images:version:)`), which the integration tests
            // drive over AppKit with the frameworks Apple moved its classes
            // into. 0.8.206 finds the image of a dyld cache an address or a
            // header index lies in through tables built once per cache file,
            // where reading a protocol list walked every image of the cache
            // for each pointer.
            // 0.8.207 holds `ObjCCodeReferences`, the Objective-C layer of the
            // cross-reference analysis, and takes MachOKitExtensions 2.0.0.
            // 0.8.208 defines `SymbolLanguage.objectiveC` and registers it when
            // its image loads, and takes MachOKitExtensions 3.0.0, which this
            // package requires (proposal split-symbol-language).
            // 0.8.209 adds `ObjCTypeIndexing`, the bridge to swift-type-indexing
            // `SwiftTypeNameResolution` hands dependency images through
            // (proposal swift-type-indexing-package), and prints `NS_SWIFT_NAME`
            // and `NS_REFINED_FOR_SWIFT` as macros.
            "0.8.209" ..< "0.9.0",
        ),
    )
}

extension Package.Dependency {
    static let Demangling = Package.Dependency.package(
        local: .package(
            path: "../swift-demangling",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-demangling",
            // 0.7.1 gives a private / local entity name its kind and scope when
            // printed, which `dump`'s semantic output of such names relies on.
            // 0.7.2 adds `DemangleOptions.useModuleSelectors`, which
            // `--module-selectors` prints with, and answers kind queries on a
            // `NodeReference` without retaining its store, which parallel
            // printing contended on. 0.7.3 demangles without copying the
            // whole demangler on each `require(pop())` and remangles without
            // visiting every slot of its hash cache on the way out: building
            // a symbol index on several threads spent 2.3 times its
            // single-threaded CPU time on those copies.
            // 0.7.4 spells existentials with `any` on request
            // (`DemangleOptions.useExistentialAny`), which `interface` and
            // `dump` print with by default.
            "0.7.4" ..< "0.8.0",
        ),
    )

    static let Semantic = Package.Dependency.package(
        local: .package(
            path: "../swift-semantic-string",
            isRelative: true,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-semantic-string",
            // 0.6.0 adds the annotation regions `marksCommentStructure` marks
            // every comment with; 0.5.0 added the definition regions
            // `marksNestedDefinitions` wraps each nested definition in. 0.7.0
            // adds `SemanticType.macro`, which MachOObjCSection 0.8.209 prints
            // two macros with (proposal swift-type-indexing-package).
            from: "0.7.0",
        ),
    )

    /// Capstone's Swift bindings, used by `SwiftThunkAnalysis` to decode a
    /// metadata accessor thunk's instructions.
    ///
    /// Only its AARCH64 trait is forwarded: the thunk decoder is ARM64-only,
    /// so the other architectures Capstone ships stay out of the build.
    static let Capstone = Package.Dependency.package(
        local: .package(
            path: "../swift-capstone",
            isRelative: true,
            traits: capstoneTraits,
        ),
        remote: .package(
            url: "https://github.com/MxIris-Reverse-Engineering/swift-capstone",
            from: "7.0.0",
            traits: capstoneTraits,
        ),
    )

    /// The one architecture the thunk decoder reads. A Capstone built without
    /// its AARCH64 backend would let `SwiftThunkAnalysis` compile and every
    /// decode fail.
    private static let capstoneTraits: Set<Package.Dependency.Trait> = [
        .trait(name: "AARCH64"),
    ]
}

extension Target.Dependency {
    static let MachOKit = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit",
    )
    static let MachOObjCSection = Target.Dependency.product(
        name: "MachOObjCSection",
        package: "MachOObjCSection",
    )
    static let ObjCCodeReferences = Target.Dependency.product(
        name: "ObjCCodeReferences",
        package: "MachOObjCSection",
    )
    static let MachOKitExtensions = Target.Dependency.product(
        name: "MachOKitExtensions",
        package: "MachOKitExtensions",
    )
    // The reading layer: targets of this package until MachOKitExtensions
    // 2.0.0 took them over under the same names.
    static let MachOReading = Target.Dependency.product(
        name: "MachOReading",
        package: "MachOKitExtensions",
    )
    static let MachOResolving = Target.Dependency.product(
        name: "MachOResolving",
        package: "MachOKitExtensions",
    )
    // The rest of the Mach-O layer, which MachOKitExtensions 2.0.0 took over
    // under the same names. `MachOSymbols` there is the language-neutral
    // half of what was this package's `MachOSymbols`: the symbol table, the
    // sweep and the C, C++ and Objective-C symbol index; the Swift half is
    // `SwiftSymbols` below.
    static let MachOPointers = Target.Dependency.product(
        name: "MachOPointers",
        package: "MachOKitExtensions",
    )
    static let MachOCaches = Target.Dependency.product(
        name: "MachOCaches",
        package: "MachOKitExtensions",
    )
    static let MachODependencies = Target.Dependency.product(
        name: "MachODependencies",
        package: "MachOKitExtensions",
    )
    static let MachOSymbols = Target.Dependency.product(
        name: "MachOSymbols",
        package: "MachOKitExtensions",
    )
    static let ARM64InstructionDecoding = Target.Dependency.product(
        name: "ARM64InstructionDecoding",
        package: "MachOKitExtensions",
    )
    static let MachOAddressResolution = Target.Dependency.product(
        name: "MachOAddressResolution",
        package: "MachOKitExtensions",
    )
    static let MachOCodeReferences = Target.Dependency.product(
        name: "MachOCodeReferences",
        package: "MachOKitExtensions",
    )
    static let MachOBase = Target.Dependency.product(
        name: "MachOBase",
        package: "MachOKitExtensions",
    )
    static let MachOFoundation = Target.Dependency.product(
        name: "MachOFoundation",
        package: "MachOKitExtensions",
    )
    // The Swift-free half of the test support, shared with
    // MachOKitExtensions' own tests since its 3.2.0: fixture names, opening
    // caches and images, slice picking, the fixture compiler
    // (`MachOFixtureSupport`, no Testing), and the trait and base classes on
    // top of it (`MachOTestingSupport`).
    static let MachOFixtureSupport = Target.Dependency.product(
        name: "MachOFixtureSupport",
        package: "MachOKitExtensions",
    )
    static let MachOTestingSupport = Target.Dependency.product(
        name: "MachOTestingSupport",
        package: "MachOKitExtensions",
    )
    static let MachOKitMain = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit",
    )
    static let MachOKitSPM = Target.Dependency.product(
        name: "MachOKit",
        package: "MachOKit-SPM",
    )
    static let Demangling = Target.Dependency.product(
        name: "Demangling",
        package: "swift-demangling",
    )
    static let Semantic = Target.Dependency.product(
        name: "Semantic",
        package: "swift-semantic-string",
    )
    static let OutputTransformer = Target.Dependency.product(
        name: "OutputTransformer",
        package: "swift-semantic-string",
    )
    static let Capstone = Target.Dependency.product(
        name: "Capstone",
        package: "swift-capstone",
    )
    static let SwiftSyntax = Target.Dependency.product(
        name: "SwiftSyntax",
        package: "swift-syntax",
    )
    static let SwiftParser = Target.Dependency.product(
        name: "SwiftParser",
        package: "swift-syntax",
    )
    static let SwiftSyntaxMacros = Target.Dependency.product(
        name: "SwiftSyntaxMacros",
        package: "swift-syntax",
    )
    static let SwiftCompilerPlugin = Target.Dependency.product(
        name: "SwiftCompilerPlugin",
        package: "swift-syntax",
    )
    static let SwiftSyntaxMacrosTestSupport = Target.Dependency.product(
        name: "SwiftSyntaxMacrosTestSupport",
        package: "swift-syntax",
    )
    static let SwiftSyntaxBuilder = Target.Dependency.product(
        name: "SwiftSyntaxBuilder",
        package: "swift-syntax",
    )
    static let SwiftSyntaxMacroExpansion = Target.Dependency.product(
        name: "SwiftSyntaxMacroExpansion",
        package: "swift-syntax",
    )
    static let SwiftSyntaxMacrosGenericTestSupport = Target.Dependency.product(
        name: "SwiftSyntaxMacrosGenericTestSupport",
        package: "swift-syntax",
    )
    static let SwiftTUI = Target.Dependency.product(
        name: "SwiftTUI",
        package: "SwiftTUI",
    )
    static let TermKit = Target.Dependency.product(
        name: "TermKit",
        package: "TermKit",
    )
}

@MainActor
extension Target {
    static let Utilities = Target.target(
        name: "Utilities",
        dependencies: [
            .target(.SwiftSectionMacros),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .product(name: "AssociatedObject", package: "AssociatedObject"),
            .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .product(name: "Dependencies", package: "swift-dependencies"),
            .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        ],
        path: "Sources/Support/Utilities",
    )

    /// The Swift symbol index: every Swift name of an image demangled and
    /// classified (members, types, witnesses, thunks), on top of
    /// MachOKitExtensions' `MachOSymbols`, whose sweep collects the names.
    static let SwiftSymbols = Target.target(
        name: "SwiftSymbols",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOKitExtensions),
            .product(.Demangling),
            .product(.MachOReading),
            .product(.MachOResolving),
            .product(.MachOSymbols),
            .product(.MachOCaches),
            .target(.Utilities),
            .target(.SwiftSymbolsRegistration),
        ],
        path: "Sources/Symbols/SwiftSymbols",
    )

    /// Registers `SymbolLanguage.swift` with MachOKitExtensions' symbol
    /// language registry when the image loads: a constructor that calls the
    /// `@c` function `SwiftSymbols` exports. Swift has no load-time
    /// initializers of its own; linking `SwiftSymbols` links this target.
    static let SwiftSymbolsRegistration = Target.target(
        name: "SwiftSymbolsRegistration",
        path: "Sources/Symbols/SwiftSymbolsRegistration",
    )

    static let MachOSwiftSectionC = Target.target(
        name: "MachOSwiftSectionC",
        path: "Sources/ABI/MachOSwiftSectionC",
    )

    /// The ABI model. Depends on the reader / resolver / pointer layer only:
    /// no symbol index, no demangler (evolution proposal
    /// `self-contained-abi-layer`).
    static let MachOSwiftSection = Target.target(
        name: "MachOSwiftSection",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOBase),
            .target(.Utilities),
            .target(.MachOSwiftSectionC),
            .target(.SwiftSectionMacros),
        ],
        path: "Sources/ABI/MachOSwiftSection",
    )

    /// Token-template transformers for rendered output — the `Transformer`
    /// namespace RuntimeViewer's settings UI edits (Swift comment token
    /// templates with presets). Lives at the bottom of the graph (no
    /// dependencies) so the rendering pipeline and RuntimeViewer share one
    /// definition; RuntimeViewer keeps only the UI (plus, for now, the
    /// ObjC-side modules — `CType`, `ObjCIvarOffset` — declared there as
    /// extensions of this namespace).
    /// The Swift-specific transformer modules. They extend the shared
    /// `Transformer` namespace from swift-semantic-string, but their token
    /// vocabulary (`bitsNeededForTag`, `payloadRegionBytesHex`, …) is Swift
    /// runtime metadata, so they belong here rather than in a general-purpose
    /// string package.
    static let SwiftOutputTransformer = Target.target(
        name: "SwiftOutputTransformer",
        dependencies: [
            .product(.OutputTransformer),
        ],
        path: "Sources/Output/SwiftOutputTransformer",
    )

    static let SwiftInspection = Target.target(
        name: "SwiftInspection",
        dependencies: [
            .product(.MachOKit),
            .product(.Semantic),
            .product(.Demangling),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .target(.Utilities),
            .product(.MachOCaches),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.MachOSwiftSectionC),
            .target(.SwiftOutputTransformer),
        ],
        path: "Sources/Analysis/SwiftInspection",
    )

    /// The Objective-C side of Swift types: the class objects of Swift
    /// classes, `@objc @implementation` classes, `@objc` protocols declared
    /// in Swift, ObjC method tables and ancestor chains, and the
    /// ClangImporter's naming rules (evolution proposal
    /// `swift-objc-interop-module`). Sits directly above `SwiftInspection`,
    /// whose demangler it uses; this is where `MachOObjCSection` enters the
    /// Swift-facing stack.
    static let SwiftObjCInterop = Target.target(
        name: "SwiftObjCInterop",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Demangling),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .target(.Utilities),
            .product(.MachOCaches),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
        ],
        path: "Sources/Analysis/SwiftObjCInterop",
    )

    /// Static aggregate-layout engine: computes Swift struct/class field
    /// offsets offline from a Mach-O file without loading the process or
    /// calling the runtime. Ports the runtime `performBasicLayout` algorithm
    /// and a static `mangled name -> TypeLayoutInfo` resolver. Sits above
    /// `SwiftInspection` so it can reuse `EnumLayoutCalculator` and
    /// `MetadataReader`. Consumed by the static ABI-analysis path.
    static let SwiftLayout = Target.target(
        name: "SwiftLayout",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Demangling),
            .target(.Utilities),
            .product(.MachOCaches),
            .product(.MachODependencies),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
        ],
        path: "Sources/Analysis/SwiftLayout",
    )

    /// Low-level Swift declaration rendering engine extracted from `SwiftDump`:
    /// pure `Keyword`/`Node`/`SemanticString`/`String` extensions, the
    /// `DemangleResolver`, the render configuration, the header-rendering
    /// helpers, and the field-metadata comment engine. Shared by both the
    /// raw-descriptor dump path (`SwiftDump`) and the model-driven interface
    /// path (`SwiftPrinting`), so neither has to depend on the other.
    static let SwiftDeclarationRendering = Target.target(
        name: "SwiftDeclarationRendering",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .target(.Utilities),
            .product(.MachOCaches),
            .product(.MachODependencies),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftOutputTransformer),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftLayout),
            .target(.SwiftThunkAnalysis),
            .product(.MachOAddressResolution),
        ],
        path: "Sources/Output/SwiftDeclarationRendering",
    )

    /// Recovers what a **kind-9 accessor-function symbolic reference** points
    /// at without executing it: disassembles the metadata accessor thunk,
    /// recognizes the availability check and the branch it selects with, and
    /// reads back each branch's type (evolution proposal
    /// `offline-opaque-accessor-thunk-resolution`).
    ///
    /// A target of its own because it is the only thing in the package that
    /// needs a C disassembly engine, so the engine stays out of every module
    /// that does not read thunks. `SwiftDeclarationRendering` depends on it
    /// and calls the reader directly; this target knows nothing about the
    /// rendering layer.
    static let SwiftThunkAnalysis = Target.target(
        name: "SwiftThunkAnalysis",
        dependencies: [
            .product(.MachOAddressResolution),
            .product(.MachOKit),
            .product(.MachOKitExtensions),
            .product(.Demangling),
            .product(.Capstone),
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .target(.Utilities),
            .product(.MachOCaches),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
        ],
        path: "Sources/Analysis/SwiftThunkAnalysis",
    )

    /// What each function of an image references, read from its arm64
    /// machine code (evolution proposals `cross-reference-analysis`,
    /// `offline-cross-references-and-symbolication`): the Swift layer and
    /// the public facade over the two layers below it.
    static let CrossReferenceAnalysis = Target.target(
        name: "CrossReferenceAnalysis",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Demangling),
            .product(.ARM64InstructionDecoding),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            // `SymbolicDemangler`: a type's name from its descriptor when no
            // symbol spells it.
            .target(.SwiftInspection),
            .product(.MachOCodeReferences),
            .product(.ObjCCodeReferences),
        ],
        path: "Sources/Analysis/CrossReferenceAnalysis",
    )

    static let SwiftDump = Target.target(
        name: "SwiftDump",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.Utilities),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftThunkAnalysis),
        ],
        path: "Sources/Output/SwiftDump",
    )

    /// Shared declaration model: `TypeDefinition`, `ProtocolDefinition`,
    /// `ExtensionDefinition`, names, kinds, and `DefinitionBuilder`. Consumed by
    /// both `SwiftIndexing` (which populates it) and `SwiftPrinting` (which
    /// renders it), keeping those two peers that never depend on each other.
    static let SwiftDeclaration = Target.target(
        name: "SwiftDeclaration",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            // `@Loggable` / `#log` for `SwiftIndexEvents.Dispatcher`'s
            // zero-handler floor, same as every other logging site in the
            // package. The macro also supplies the `#available` fallback to
            // `os_log` that a bare `os.Logger` would need here — this package
            // deploys to macOS 10.15, below `Logger`'s macOS 11.
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .target(.Utilities),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftThunkAnalysis),
        ],
        path: "Sources/Declaration/SwiftDeclaration",
    )

    /// Builds the `SwiftDeclaration` model from a Mach-O image:
    /// `SwiftDeclarationIndexer`, its events/configuration, and the
    /// `GenericSpecializer` analysis built on top of the index.
    static let SwiftIndexing = Target.target(
        name: "SwiftIndexing",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            // The adapter that hands `ObjCIndexing.ObjCInterfaceIndexer`'s class
            // groups to the ObjC-ancestor override recovery
            // (`ObjCInterfaceIndexerClassHierarchyProvider`).
            .product(name: "ObjCIndexing", package: "MachOObjCSection"),
            .product(name: "ObjCMetadataSource", package: "MachOObjCSection"),
            .product(.Semantic),
            .product(.Demangling),
            .target(.Utilities),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftThunkAnalysis),
            .target(.SwiftDeclaration),
            .target(.SwiftDeclarationRendering),
        ],
        path: "Sources/Declaration/SwiftIndexing",
    )

    /// Recovers the source files private discriminators were derived from:
    /// MD5 over candidate file names, drawn from an indexed image's names and
    /// a generated list of known file names (evolution proposal
    /// `private-declarations`). Its index is what tells dump and interface
    /// those files (`private-declaration-source-files`).
    static let SwiftPrivateDiscriminators = Target.target(
        name: "SwiftPrivateDiscriminators",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Demangling),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDeclaration),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftIndexing),
        ],
        path: "Sources/Declaration/SwiftPrivateDiscriminators",
    )

    /// Infers source-level Swift attributes (`@propertyWrapper`,
    /// `@resultBuilder`, `@dynamicMemberLookup`, `@objc`, …) from the
    /// `SwiftDeclaration` model. A low-level peer over the model so the
    /// inference can be reused independently of printing.
    static let SwiftAttributeInference = Target.target(
        name: "SwiftAttributeInference",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.Utilities),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDeclaration),
        ],
        path: "Sources/Declaration/SwiftAttributeInference",
    )

    /// Diffs the Swift ABI of two indexed modules. Keys every declaration on
    /// its remangled `Node` and computes a recursive set difference; a pure
    /// peer over the model (no Mach-O), so it only needs `SwiftDeclaration`
    /// and `Demangling`.
    static let SwiftDiffing = Target.target(
        name: "SwiftDiffing",
        dependencies: [
            .product(.Demangling),
            .target(.SwiftDeclaration),
        ],
        path: "Sources/Output/SwiftDiffing",
    )

    /// Renders the `SwiftDeclaration` model as Swift source:
    /// `SwiftDeclarationPrinter`, the node printers/printables, and the
    /// print configuration. Consumes `SwiftAttributeInference` for the
    /// attribute annotations.
    static let SwiftPrinting = Target.target(
        name: "SwiftPrinting",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.Utilities),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftOutputTransformer),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftDeclaration),
            .target(.SwiftAttributeInference),
            // `Transformer.CType.Pattern`, the keys of
            // `SwiftDeclarationPrintConfiguration.cTypeReplacements`.
            .product(.OutputTransformer),
            .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
        ],
        path: "Sources/Output/SwiftPrinting",
    )

    /// Runtime generic-specialization engine (`GenericSpecializer`,
    /// `ConformanceProvider`). Sits above `SwiftIndexing` because it queries a
    /// populated index to resolve candidates and conformances; kept out of
    /// `SwiftIndexing` so the index can be built and consumed without pulling
    /// in the runtime specialization machinery.
    static let SwiftSpecialization = Target.target(
        name: "SwiftSpecialization",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.Utilities),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            // The host's runtime names for `.metatype` arguments and the
            // member projection the offline specialization substitutes with.
            .target(.SwiftDeclarationRendering),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
        ],
        path: "Sources/Declaration/SwiftSpecialization",
    )

    /// Orchestrator: `SwiftInterfaceBuilder` ties indexing and printing
    /// together into a full interface dump.
    static let SwiftInterface = Target.target(
        name: "SwiftInterface",
        dependencies: [
            .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            .product(.MachOKit),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .target(.Utilities),
            .product(.MachODependencies),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftAttributeInference),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.SwiftDiffing),
        ],
        path: "Sources/Output/SwiftInterface",
    )

    /// The printer's side of swift-type-indexing (proposal
    /// swift-type-indexing-package): `TypeDatabaseTypeNameResolver` answers the
    /// printer's `ModuleNameResolving` and `CImportedNameResolving` from a
    /// `TypeDatabase`, so `__C.UICellConfigurationState` prints as
    /// `UIKit.__UICellConfigurationState`; `SwiftInterfaceBuilderTypeNameProvider`
    /// attaches one to a `SwiftInterfaceBuilder` for a binary and its
    /// dependencies. Every source file is `#if os(macOS)`.
    static let SwiftTypeNameResolution = Target.target(
        name: "SwiftTypeNameResolution",
        dependencies: [
            .target(.SwiftInterface),
            .target(.SwiftPrinting),
            .target(.MachOSwiftSection),
            .product(.MachOKit),
            .product(.MachOKitExtensions),
            .product(name: "ObjCMetadataSource", package: "MachOObjCSection"),
            .product(name: "ObjCTypeIndexing", package: "MachOObjCSection", condition: .when(platforms: [.macOS])),
            .product(name: "TypeIndexing", package: "swift-type-indexing", condition: .when(platforms: [.macOS])),
        ],
        path: "Sources/Output/SwiftTypeNameResolution",
    )

    // MARK: - Commands

    /// Everything `swift-section` does, as a library (evolution proposal
    /// `swift-section-kit`): one request type per subcommand, its product and
    /// diagnostics delivered to a host-supplied `SwiftSectionOutput`. The
    /// executable is a wrapper around it — flag parsing, error wording,
    /// stream routing and exit codes.
    static let SwiftSectionKit = Target.target(
        name: "SwiftSectionKit",
        dependencies: [
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.MachOSwiftSection),
            .target(.SwiftDump),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftOutputTransformer),
            .target(.SwiftDeclaration),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftDiffing),
            .target(.SwiftInterface),
            .target(.SwiftPrivateDiscriminators),
            .target(.SwiftTypeNameResolution),
            // `APINotesFile`, which checks `--supplementary-apinotes` paths.
            .product(name: "TypeIndexing", package: "swift-type-indexing", condition: .when(platforms: [.macOS])),
            // `objc interface --mark-sdk-swift-names`.
            .product(name: "ObjCTypeIndexing", package: "MachOObjCSection", condition: .when(platforms: [.macOS])),
            .target(.Utilities),
            // `refs` and `symbolicate`.
            .target(.CrossReferenceAnalysis),
            .product(.MachOKit),
            .product(.MachOKitExtensions),
            .product(.Semantic),
            .product(.Demangling),
            .product(.OutputTransformer),
            .product(name: "ObjCDeclarationRendering", package: "MachOObjCSection"),
            .product(name: "ObjCDiffing", package: "MachOObjCSection"),
            .product(name: "ObjCIndexing", package: "MachOObjCSection"),
            .product(name: "ObjCInterface", package: "MachOObjCSection"),
            // `ObjCInterfaceSession` names `ObjCInterfaceIndexer<MachOFile>`,
            // whose `MachOFile: ObjCMetadataSource` conformance lives here;
            // Swift 6.4 warns when a file uses a conformance from a module it
            // does not import.
            .product(name: "ObjCMetadataSource", package: "MachOObjCSection"),
            .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
        ],
        path: "Sources/Commands/SwiftSectionKit",
    )

    static let swift_section = Target.executableTarget(
        name: "swift-section",
        dependencies: [
            .target(.SwiftSectionKit),
            // What the wrapper names itself while mapping its flags onto the
            // library's requests: `DependencySearchPath`, `DemangleOptions`,
            // `Transformer.SwiftConfiguration`, `ConsoleEventHandler`,
            // `MultilineTypeFormatting`, the ObjC generation options and C
            // type presets.
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.SwiftDump),
            .target(.SwiftOutputTransformer),
            .target(.SwiftDeclaration),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftIndexing),
            .product(.Semantic),
            .product(.OutputTransformer),
            .product(name: "ObjCDeclarationRendering", package: "MachOObjCSection"),
            .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
            .product(name: "Rainbow", package: "Rainbow"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        path: "Sources/Executables/swift-section",
    )

    /// Maintainer tool, not a product: times indexing and printing one image's
    /// interface through `MachOImage` or `MachOFile` in an ordinary process
    /// (evolution proposal `machofile-performance`).
    static let reader_benchmark = Target.executableTarget(
        name: "reader-benchmark",
        dependencies: [
            .target(.SwiftSectionKit),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftInterface),
            .target(.SwiftDeclarationRendering),
            .product(.MachOKit),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        path: "Sources/Executables/reader-benchmark",
    )

    static let baseline_generator = Target.executableTarget(
        name: "baseline-generator",
        dependencies: [
            .target(.SwiftSectionFixtureSupport),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        path: "Sources/Executables/baseline-generator",
        swiftSettings: testSettings,
    )

    // MARK: - Plugins

    /// `swift package regen-baselines` — regenerates the auto-generated
    /// `__Baseline__/<File>Baseline.swift` files consumed by the fixture-based
    /// test coverage suites. Replaces the legacy `Scripts/regen-baselines.sh`.
    static let RegenerateBaselinesPlugin = Target.plugin(
        name: "RegenerateBaselinesPlugin",
        capability: .command(
            intent: .custom(
                verb: "regen-baselines",
                description: "Regenerate MachOSwiftSection fixture-test ABI baselines.",
            ),
            permissions: [
                .writeToPackageDirectory(
                    reason: "Writes regenerated baselines under Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/.",
                ),
            ],
        ),
        dependencies: [
            .target(.baseline_generator),
        ],
    )

    // MARK: - Macros

    static let SwiftSectionMacros = Target.macro(
        name: "SwiftSectionMacros",
        dependencies: [
            .product(.SwiftSyntax),
            .product(.SwiftSyntaxMacros),
            .product(.SwiftCompilerPlugin),
            .product(.SwiftSyntaxBuilder),
        ],
        path: "Sources/Support/SwiftSectionMacros",
    )

    /// The test support's macros: `@FixtureSuite`. Kept apart from
    /// `SwiftSectionMacros`, so the plugin the production targets load
    /// carries no test-only macro.
    static let SwiftSectionTestingMacros = Target.macro(
        name: "SwiftSectionTestingMacros",
        dependencies: [
            .product(.SwiftSyntax),
            .product(.SwiftSyntaxMacros),
            .product(.SwiftCompilerPlugin),
            .product(.SwiftSyntaxBuilder),
        ],
        path: "Sources/TestSupport/SwiftSectionTestingMacros",
    )

    // MARK: - Testing

    /// Fixture-loading helpers, baseline generators, coverage scanners, and
    /// non-Testing-dependent code. Importable from non-test targets (e.g.
    /// `baseline-generator`) without dragging in `Testing.framework`.
    /// Re-exports MachOKitExtensions' `MachOFixtureSupport`, which it adds
    /// this package's fixture names and named caches to.
    static let SwiftSectionFixtureSupport = Target.target(
        name: "SwiftSectionFixtureSupport",
        dependencies: [
            .product(.MachOKit),
            .product(.MachOFoundation),
            .product(.MachOFixtureSupport),
            .target(.SwiftSymbols),
            .product(.MachOReading),
            .product(.MachOResolving),
            .target(.MachOSwiftSectionC),
            .target(.SwiftDump),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftInterface),
            .target(.SwiftSectionTestingSupportC),
            .product(.Demangling),
            .product(.SwiftSyntax),
            .product(.SwiftParser),
            .product(.SwiftSyntaxBuilder),
        ],
        path: "Sources/TestSupport/SwiftSectionFixtureSupport",
        swiftSettings: testSettings,
    )

    /// `swift-testing` support: `MachOSwiftSectionFixtureTests` and the Swift
    /// fixtures, on top of MachOKitExtensions' `MachOTestingSupport` (the
    /// `MachOFileTests`, `MachOImageTests`, `DyldCacheTests`,
    /// `XcodeMachOFileTests` and `MachOFixtureTests` base classes and
    /// `ExclusiveImageAccess`), which it re-exports.
    /// Splitting this out from `SwiftSectionFixtureSupport` keeps `Testing.framework`
    /// out of the link line for non-test targets.
    static let SwiftSectionTestingSupport = Target.target(
        name: "SwiftSectionTestingSupport",
        dependencies: [
            .product(.MachOKit),
            .product(.Demangling),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .product(.MachOReading),
            .product(.MachOResolving),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOTestingSupport),
            .target(.MachOSwiftSection),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.SwiftInterface),
            .target(.SwiftSectionTestingMacros),
            .product(.Semantic),
        ],
        path: "Sources/TestSupport/SwiftSectionTestingSupport",
        swiftSettings: testSettings,
    )

    static let SwiftSectionTestingSupportC = Target.target(
        name: "SwiftSectionTestingSupportC",
        dependencies: [
        ],
        path: "Sources/TestSupport/SwiftSectionTestingSupportC",
        swiftSettings: testSettings,
    )

    static let SwiftSymbolsTests = Target.testTarget(
        name: "SwiftSymbolsTests",
        dependencies: [
            .target(.SwiftSymbols),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.Demangling),
            .product(.MachOResolving),
        ],
        swiftSettings: testSettings,
    )

    static let MachOSwiftSectionTests = Target.testTarget(
        name: "MachOSwiftSectionTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .target(.SwiftDump),
            .target(.SwiftInspection),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .product(.Demangling),
        ],
        swiftSettings: testSettings,
    )


    static let SwiftOutputTransformerTests = Target.testTarget(
        name: "SwiftOutputTransformerTests",
        dependencies: [
            .target(.SwiftOutputTransformer),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftInspectionTests = Target.testTarget(
        name: "SwiftInspectionTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .target(.SwiftOutputTransformer),
            .target(.SwiftInspection),
            // The suites that read ObjC classes through
            // `ObjCImplementationClassReading` or evict an ObjC-side index.
            .target(.SwiftObjCInterop),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftObjCInteropTests = Target.testTarget(
        name: "SwiftObjCInteropTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftLayoutTests = Target.testTarget(
        name: "SwiftLayoutTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftLayout),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.Demangling),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftDumpTests = Target.testTarget(
        name: "SwiftDumpTests",
        dependencies: [
            .target(.SwiftThunkAnalysis),
            .target(.SwiftDump),
            .target(.SwiftObjCInterop),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOObjCSection),
            .product(.Semantic),
            .product(.Demangling),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        exclude: ["Snapshots/__Snapshots__"],
        swiftSettings: testSettings,
    )

    static let SwiftTypeNameResolutionTests = Target.testTarget(
        name: "SwiftTypeNameResolutionTests",
        dependencies: [
            .target(.SwiftTypeNameResolution),
            .target(.SwiftPrinting),
            // The provider's tests build a small library to read
            // (proposal moved-swift-type-modules).
            .target(.SwiftInterface),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOKit),
            .product(name: "TypeIndexing", package: "swift-type-indexing", condition: .when(platforms: [.macOS])),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftInterfaceTests = Target.testTarget(
        name: "SwiftInterfaceTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .product(name: "ObjCIndexing", package: "MachOObjCSection"),
            .product(name: "ObjCMetadataSource", package: "MachOObjCSection"),
            .target(.SwiftObjCInterop),
            .target(.SwiftThunkAnalysis),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.SwiftInterface),
            // The nested-definition contract with source-file comments on.
            .target(.SwiftPrivateDiscriminators),
            // `Transformer.CType`, the C type replacements of a recovered
            // `@objc @implementation` stored property's type.
            .product(.OutputTransformer),
            .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
            .product(.MachOKitExtensions),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        exclude: ["Snapshots/__Snapshots__"],
        swiftSettings: testSettings,
    )

    static let SwiftPrintingTests = Target.testTarget(
        name: "SwiftPrintingTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftDump),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftDeclarationRenderingTests = Target.testTarget(
        name: "SwiftDeclarationRenderingTests",
        dependencies: [
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftLayout),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftThunkAnalysis),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.Semantic),
            .product(.Demangling),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftThunkAnalysisTests = Target.testTarget(
        name: "SwiftThunkAnalysisTests",
        dependencies: [
            .product(.MachOAddressResolution),
            .target(.SwiftThunkAnalysis),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftDump),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .product(.Demangling),
        ],
        swiftSettings: testSettings,
    )

    static let CrossReferenceAnalysisTests = Target.testTarget(
        name: "CrossReferenceAnalysisTests",
        dependencies: [
            .target(.CrossReferenceAnalysis),
            .product(.MachOCodeReferences),
            .product(.MachOAddressResolution),
            .product(.ObjCCodeReferences),
            .product(.ARM64InstructionDecoding),
            .product(.MachOKit),
            .product(.Capstone),
            .product(.Demangling),
            .target(.MachOSwiftSection),
            .product(.MachOReading),
            .target(.SwiftInspection),
            .target(.SwiftSectionFixtureSupport),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftAttributeInferenceTests = Target.testTarget(
        name: "SwiftAttributeInferenceTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftAttributeInference),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftDiffingTests = Target.testTarget(
        name: "SwiftDiffingTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftDiffing),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftSectionCommandTests = Target.testTarget(
        name: "SwiftSectionCommandTests",
        dependencies: [
            .target(.swift_section),
            .target(.SwiftSectionKit),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            .target(.SwiftOutputTransformer),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftPrinting),
            // For the `objc` subcommand tests under `ObjC/`.
            .product(name: "ObjCDeclarationRendering", package: "MachOObjCSection"),
            .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "Rainbow", package: "Rainbow"),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftSectionKitTests = Target.testTarget(
        name: "SwiftSectionKitTests",
        dependencies: [
            .target(.SwiftSectionKit),
            // `FixtureCompiler`, for a library that names a moved Swift type
            // (proposal moved-swift-type-modules).
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
            // `LocalTypeFixture` and `ExclusiveImageAccess`, for the source
            // files of a public type's private members.
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftDeclaration),
            .target(.SwiftDiffing),
            .target(.SwiftOutputTransformer),
            // `MultilineTypeFormatting`, which the `dump` and `interface`
            // requests take.
            .target(.SwiftDeclarationRendering),
            // What `refs` and `symbolicate` return.
            .target(.CrossReferenceAnalysis),
            .product(.Semantic),
            .product(.OutputTransformer),
            .product(name: "ObjCDiffing", package: "MachOObjCSection"),
            .product(name: "ObjCOutputTransformer", package: "MachOObjCSection"),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftPrivateDiscriminatorsTests = Target.testTarget(
        name: "SwiftPrivateDiscriminatorsTests",
        dependencies: [
            .target(.SwiftPrivateDiscriminators),
            .target(.SwiftInspection),
            .target(.SwiftDeclaration),
            .target(.SwiftDeclarationRendering),
            .target(.SwiftIndexing),
            .target(.SwiftSectionFixtureSupport),
            .target(.SwiftSectionTestingSupport),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftIndexingTests = Target.testTarget(
        name: "SwiftIndexingTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftAttributeInference),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftSpecializationTests = Target.testTarget(
        name: "SwiftSpecializationTests",
        dependencies: [
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftSpecialization),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOFoundation),
            .target(.SwiftSymbols),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftSectionTestingMacrosTests = Target.testTarget(
        name: "SwiftSectionTestingMacrosTests",
        dependencies: [
            .target(.SwiftSectionTestingMacros),
            .product(.SwiftSyntax),
            .product(.SwiftSyntaxBuilder),
            .product(.SwiftSyntaxMacros),
            .product(.SwiftSyntaxMacroExpansion),
            .product(.SwiftSyntaxMacrosGenericTestSupport),
        ],
        swiftSettings: testSettings,
    )

    static let SwiftSectionTestingSupportTests = Target.testTarget(
        name: "SwiftSectionTestingSupportTests",
        dependencies: [
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .target(.SwiftDeclaration),
            .product(.Demangling),
        ],
        exclude: [
            "Coverage/Fixtures/SampleSource.swift.txt",
            "Coverage/Fixtures/SuiteSampleSource.swift.txt",
        ],
        swiftSettings: testSettings,
    )

    static let IntegrationTests = Target.testTarget(
        name: "IntegrationTests",
        dependencies: [
            .product(.MachOKitExtensions),
            .product(.MachOCaches),
            .product(.MachOReading),
            .product(.MachOResolving),
            .target(.SwiftSymbols),
            .product(.MachOPointers),
            .product(.MachOFoundation),
            .target(.MachOSwiftSection),
            .target(.SwiftInspection),
            .target(.SwiftObjCInterop),
            .target(.SwiftDump),
            .target(.SwiftDeclaration),
            .target(.SwiftIndexing),
            .target(.SwiftPrinting),
            .target(.SwiftInterface),
            .target(.SwiftDiffing),
            .target(.SwiftTypeNameResolution),
            .product(name: "TypeIndexing", package: "swift-type-indexing", condition: .when(platforms: [.macOS])),
            .target(.SwiftSectionTestingSupport),
            .target(.SwiftSectionFixtureSupport),
            .product(.MachOKit),
            .product(.MachOObjCSection),
            // The Objective-C inspection dumps run the `swift-section objc
            // dump`, `objc diff` and `objc evolution` pipelines on
            // MachOObjCSection's own modules.
            .product(name: "ObjCDeclarationRendering", package: "MachOObjCSection"),
            .product(name: "ObjCDiffing", package: "MachOObjCSection"),
            .product(name: "ObjCIndexing", package: "MachOObjCSection"),
            .product(name: "ObjCInterface", package: "MachOObjCSection"),
            .product(name: "ObjCMetadataSource", package: "MachOObjCSection"),
            .product(.Demangling),
            .product(.Semantic),
            .product(name: "Dependencies", package: "swift-dependencies"),
        ],
        swiftSettings: testSettings,
    )
}

let package = Package(
    name: "MachOSwiftSection",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1)],
    products: [
        .library(.MachOSwiftSection),
        // The ABI model does not re-export the symbol index (evolution
        // proposal `self-contained-abi-layer`), so a downstream target that
        // uses `SwiftSymbolIndexStore` / `DemangledSymbol` depends on
        // `SwiftSymbols` explicitly; `MachOBase`, `MachOFoundation` and
        // `MachODependencies` are products of MachOKitExtensions.
        .library(.SwiftSymbols),
        .library(.SwiftOutputTransformer),
        .library(.SwiftInspection),
        .library(.SwiftObjCInterop),
        .library(.SwiftLayout),
        .library(.SwiftDeclarationRendering),
        .library(.SwiftThunkAnalysis),
        .library(.CrossReferenceAnalysis),
        .library(.SwiftDump),
        .library(.SwiftDeclaration),
        .library(.SwiftAttributeInference),
        .library(.SwiftDiffing),
        .library(.SwiftIndexing),
        .library(.SwiftPrivateDiscriminators),
        .library(.SwiftPrinting),
        .library(.SwiftSpecialization),
        .library(.SwiftInterface),
        .library(.SwiftTypeNameResolution),
        .library(.SwiftSectionKit),
        .executable(.swift_section),
    ],
    dependencies: dependencies,
    targets: [
        // Library
        .Utilities,
        .SwiftOutputTransformer,
        .SwiftSymbols,
        .SwiftSymbolsRegistration,
        .MachOSwiftSectionC,
        .MachOSwiftSection,
        .SwiftInspection,
        .SwiftObjCInterop,
        .SwiftLayout,
        .SwiftDeclarationRendering,
        .SwiftThunkAnalysis,
        .CrossReferenceAnalysis,
        .SwiftDump,
        .SwiftDeclaration,
        .SwiftAttributeInference,
        .SwiftDiffing,
        .SwiftIndexing,
        .SwiftPrivateDiscriminators,
        .SwiftPrinting,
        .SwiftSpecialization,
        .SwiftInterface,
        .SwiftTypeNameResolution,
        .SwiftSectionKit,
        .SwiftSectionMacros,
        .SwiftSectionTestingMacros,
        .SwiftSectionFixtureSupport,
        .SwiftSectionTestingSupport,
        .SwiftSectionTestingSupportC,

        // Executable
        .swift_section,
        .reader_benchmark,
        .baseline_generator,

        // Plugins
        .RegenerateBaselinesPlugin,

        // Testing
        .SwiftSymbolsTests,
        .MachOSwiftSectionTests,
        .SwiftInspectionTests,
        .SwiftObjCInteropTests,
        .SwiftOutputTransformerTests,
        .SwiftLayoutTests,
        .SwiftDumpTests,
        .SwiftTypeNameResolutionTests,
        .SwiftPrintingTests,
        .SwiftDeclarationRenderingTests,
        .SwiftThunkAnalysisTests,
        .CrossReferenceAnalysisTests,
        .SwiftAttributeInferenceTests,
        .SwiftDiffingTests,
        .SwiftSectionCommandTests,
        .SwiftSectionKitTests,
        .SwiftIndexingTests,
        .SwiftPrivateDiscriminatorsTests,
        .SwiftSpecializationTests,
        .SwiftInterfaceTests,
        .SwiftSectionTestingMacrosTests,
        .SwiftSectionTestingSupportTests,
        .IntegrationTests,
    ],
)

extension SwiftSetting {
    static let existentialAny: Self = .enableUpcomingFeature("ExistentialAny") // SE-0335, Swift 5.6,  SwiftPM 5.8+
    static let internalImportsByDefault: Self = .enableUpcomingFeature("InternalImportsByDefault") // SE-0409, Swift 6.0,  SwiftPM 6.0+
    static let memberImportVisibility: Self = .enableUpcomingFeature("MemberImportVisibility") // SE-0444, Swift 6.1,  SwiftPM 6.1+
    static let inferIsolatedConformances: Self = .enableUpcomingFeature("InferIsolatedConformances") // SE-0470, Swift 6.2,  SwiftPM 6.2+
    static let nonisolatedNonsendingByDefault: Self = .enableUpcomingFeature("NonisolatedNonsendingByDefault") // SE-0461, Swift 6.2,  SwiftPM 6.2+
    static let immutableWeakCaptures: Self = .enableUpcomingFeature("ImmutableWeakCaptures") // SE-0481, Swift 6.2,  SwiftPM 6.2+
}

// MARK: - Upcoming features

// Every Swift target adopts three upcoming features that Swift 7 turns on
// (proposal swift6-mode-and-upcoming-features, shared with the other MachO
// packages). The loop runs before the Tuist block so a target Tuist reshapes
// already carries them. The other three settings above stay unused: they
// change run-time behavior or every import, and were measured and declined.
let upcomingFeatureSettings: [SwiftSetting] = [
    .existentialAny,
    .memberImportVisibility,
    .inferIsolatedConformances,
]

for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatureSettings
}

// MARK: - Tuist development workspace

// MachOSwiftSection's Tuist development workspace (its Documentations/Internal/TuistDevelopment.md)
// maps this package's tests with Tuist, which rejects shapes SwiftPM accepts: a test that depends on
// an executable target or on a macro target (Tuist builds a macro as a plugin, so `@testable import`
// of it finds no module), and a test that depends on a target no product contains. Only while Tuist
// resolves the packages, with TUIST_MAPS_LOCAL_PACKAGE_TESTS=1, the first kinds are left out — the
// macro expansion tests then run under `swift test` only — and the last kind gets a library product
// of its own. Nothing changes without the variable.
if Context.environment["TUIST_MAPS_LOCAL_PACKAGE_TESTS"] == "1" {
    let executableOrMacroTargetNames = Set(package.targets.filter { $0.type == .executable || $0.type == .macro }.map(\.name))
    func dependencyName(_ dependency: Target.Dependency) -> String? {
        switch dependency {
        case .targetItem(let name, _), .byNameItem(let name, _):
            return name
        default:
            return nil
        }
    }
    package.targets.removeAll { target in
        target.type == .test && target.dependencies.contains { dependency in
            dependencyName(dependency).map(executableOrMacroTargetNames.contains) ?? false
        }
    }
    let productTargetNames = Set(package.products.flatMap { product in (product as? Product.Library)?.targets ?? [] })
    let testDependencyNames = Set(package.targets.filter { $0.type == .test }.flatMap { $0.dependencies.compactMap(dependencyName) })
    package.products += package.targets
        .filter { target in target.type == .regular && testDependencyNames.contains(target.name) && !productTargetNames.contains(target.name) }
        .map { target in Product.library(name: target.name, targets: [target.name]) }
}
