import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) import SwiftInterface
@_spi(Support) import SwiftPrinting
import SwiftDeclarationRendering
import SwiftObjCInterop
import Semantic
@testable import SwiftSectionTestingSupport

/// The Objective-C declarations as Swift imports them (evolution proposal
/// `objc-imported-declarations`), over the shared `@objc @implementation`
/// fixture: a class declared and implemented in Objective-C, named by the
/// importer's rules; an `@objc @implementation` class whose members come from
/// its Swift implementation; a Swift class registered with the runtime; an
/// `@objc` protocol; and the separately shipped dylib's category on a class
/// of another image.
///
/// The linker merges every category of a class the image defines into the
/// class's own lists, so the fixture itself lists no category: the members
/// of `@objc(Extras) @implementation extension Widget` and of the Swift
/// extensions with `@objc` members are the classes' methods.
@Suite(.serialized, ExclusiveImageAccess(ObjCImplementationFixture.moduleName))
struct ObjCImportedDefinitionTests {
    private func builder(of machOFile: MachOFile, printMemberAddress: Bool = false, marksCommentStructure: Bool = false) async throws -> SwiftInterfaceBuilder<MachOFile> {
        var configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(dependencySearchPaths: try ObjCImplementationFixture.dependencySearchPaths())
        )
        configuration.printConfiguration.printMemberAddress = printMemberAddress
        configuration.printConfiguration.marksCommentStructure = marksCommentStructure
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return builder
    }

    private func fixtureBuilder() async throws -> SwiftInterfaceBuilder<MachOFile> {
        try await builder(of: ObjCImplementationFixture.machOFile(.full))
    }

    @Test func aClassDeclaredInObjectiveCTakesTheImportersNames() async throws {
        let builder = try await fixtureBuilder()
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "ClangWidget"))
        #expect(!definition.isSwiftClass)
        #expect(definition.swiftClassDefinition == nil)
        // `extension ClangWidget { @objc public func swiftAdded() -> Int }`.
        #expect(!definition.swiftExtensions.isEmpty)

        let printed = try await builder.printer.printObjCImportedClassDefinition(definition).string
        #expect(printed.contains("class ClangWidget: __C.NSObject {"), "\(printed)")
        #expect(printed.contains("Swift names follow the ClangImporter's rules"), "\(printed)")
        // Unknown nullability is `!`; a `copy` `NSString` is a plain `String`.
        #expect(printed.contains("var label: Swift.String!"), "\(printed)")
        #expect(!printed.contains("@NSCopying"), "\(printed)")
        #expect(printed.contains("var tally: Swift.Int"), "\(printed)")
        #expect(printed.contains("func bump()"), "\(printed)")
        #expect(printed.contains("class func pingCount() -> Swift.Int"), "\(printed)")
        // The accessors are the properties, not methods of their own.
        #expect(!printed.contains("func setLabel"), "\(printed)")
        // The method the Swift extension adds, merged into the class's lists.
        #expect(printed.contains("swiftAdded() -> Swift.Int"), "\(printed)")
    }

    @Test func anImplementationClassTakesItsMembersFromSwift() async throws {
        let builder = try await fixtureBuilder()
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "Widget"))
        #expect(!definition.swiftExtensions.isEmpty)

        let printed = try await builder.printer.printObjCImportedClassDefinition(definition).string
        #expect(printed.contains("class Widget: __C.NSObject {"), "\(printed)")
        // The Swift members' own types: non-optional, which no method list
        // records — the rules would print `String!`.
        #expect(printed.contains("title: Swift.String"), "\(printed)")
        #expect(!printed.contains("title: Swift.String!"), "\(printed)")
        #expect(printed.contains("init(title: Swift.String)"), "\(printed)")
        #expect(printed.contains("func refresh()"), "\(printed)")
        // `@objc(Extras) @implementation extension Widget`, merged into the
        // class's lists.
        #expect(printed.contains("describe() -> Swift.String"), "\(printed)")
        #expect(!printed.contains("describe() -> Swift.String!"), "\(printed)")
    }

    /// An `@objc @implementation` class shaped like an OS framework's
    /// (evolution proposal `swift-first-imported-declarations`): optimized
    /// and stripped, so the thunks carry no symbol and call no Swift member,
    /// and the joined tiers tie almost nothing. It prints as its Swift side:
    /// the Swift members, the header's refined property as the Swift members
    /// implementing and replacing it, and what the Swift side lacks from the
    /// Objective-C side.
    @Test func anOptimizedStrippedImplementationClassPrintsAsItsSwiftSide() async throws {
        let builder = try await builder(of: ObjCImplementationFixture.machOFile(.optimizedStripped))
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "ScenePresentationWidget"))
        let printed = try await builder.printer.printObjCImportedClassDefinition(definition).string
        #expect(printed.contains("class ScenePresentationWidget: __C.NSObject {"), "\(printed)")
        // The Swift name the header's `NS_SWIFT_NAME` gives it, which the
        // importer's rules miss — not `isHostingSceneLayer(_:)`.
        #expect(printed.contains("func isHosting(sceneLayer: __C.FXSceneLayer) -> Swift.Bool"), "\(printed)")
        #expect(!printed.contains("isHostingSceneLayer"), "\(printed)")
        // `layerFilter`: the `__` member implementing it, and the Swift-only
        // member the header leaves the plain name to.
        #expect(printed.contains("var __layerFilter: __C.PresentationFilter"), "\(printed)")
        #expect(printed.contains("var layerFilter: ObjCImplementationFixture.PresentationFilterValue"), "\(printed)")
        #expect(!printed.contains("var layerFilter: __C.PresentationFilter!"), "\(printed)")
        // `settings`: the Swift-only member, and the Objective-C property its
        // implementation left no symbol of, under the name Swift gives it.
        #expect(printed.contains("var settings: ObjCImplementationFixture.PresentationSettingsValue"), "\(printed)")
        #expect(printed.contains("// NS_REFINED_FOR_SWIFT: var __settings: __C.PresentationSettings! { get set }\n"), "\(printed)")
        #expect(!printed.contains("var settings: __C.PresentationSettings!"), "\(printed)")
        // A stored property whose setter left no symbol is settable when
        // Objective-C has a setter, and `weak` as Objective-C says.
        #expect(printed.contains("weak var scene: __C.NSObject?"), "\(printed)")
        // A stored property no symbol names: the Objective-C property
        // synthesized on it, not a comment about its ivar.
        #expect(printed.contains("var observers: Any"), "\(printed)")
        #expect(!printed.contains("stored property observers"), "\(printed)")
    }

    /// A property the header refines for Swift whose `__` declaration the
    /// image keeps no symbol of is worded right above the Swift property that
    /// took its plain name — before that property's own comments — not among
    /// the Objective-C methods no Swift member answers to (evolution proposal
    /// `swift-first-imported-declarations`).
    @Test(arguments: [false, true])
    func aRefinedPropertysCommentSitsAboveTheSwiftPropertyTakingItsName(printMemberAddress: Bool) async throws {
        let builder = try await builder(of: ObjCImplementationFixture.machOFile(.optimizedStripped), printMemberAddress: printMemberAddress)
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "ScenePresentationWidget"))
        let printed = try await builder.printer.printObjCImportedClassDefinition(definition).string
        let lines = printed.components(separatedBy: "\n")
        let commentIndices = lines.indices.filter { lines[$0].contains("NS_REFINED_FOR_SWIFT") }
        #expect(commentIndices.count == 1, "\(printed)")
        let commentIndex = try #require(commentIndices.first, "\(printed)")
        let comment = lines[commentIndex]
        #expect(comment.trimmingCharacters(in: .whitespaces) == "// NS_REFINED_FOR_SWIFT: var __settings: __C.PresentationSettings! { get set }", "\(printed)")
        // The Swift property's own rows follow: its address comments, when
        // printed, then its declaration, all at the comment's indentation.
        let isComment = { (line: String) in line.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let declarationIndex = try #require(lines[(commentIndex + 1)...].firstIndex { !isComment($0) }, "\(printed)")
        let addressRows = lines[(commentIndex + 1) ..< declarationIndex]
        #expect(lines[declarationIndex].contains("var settings: ObjCImplementationFixture.PresentationSettingsValue"), "\(printed)")
        #expect(addressRows.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("// Address") }, "\(printed)")
        #expect(addressRows.isEmpty != printMemberAddress, "\(printed)")
        let indentation = { (line: String) in line.prefix { $0 == " " }.count }
        #expect((addressRows + [lines[declarationIndex]]).allSatisfy { indentation($0) == indentation(comment) }, "\(printed)")
        // It was the only Objective-C member no Swift member answers to, so
        // the group of those, and its note, are gone.
        #expect(!printed.contains("no Swift member answers to"), "\(printed)")
    }

    /// The declaration in that comment is marked by its parts — the
    /// property's name and type — for a host to color as it colors a field
    /// tree's rows; the punctuation inside the declaration plays no role, so
    /// a host hiding separators keeps it (evolution proposal
    /// `swift-first-imported-declarations`).
    @Test func aRefinedPropertysCommentMarksTheDeclarationsNameAndType() async throws {
        let marked = try await builder(of: ObjCImplementationFixture.machOFile(.optimizedStripped), marksCommentStructure: true)
        let definition = try #require(marked.indexer.objcImportedClassDefinition(named: "ScenePresentationWidget"))
        let markedPrint = try await marked.printer.printObjCImportedClassDefinition(definition).frozen()
        let separated = markedPrint.separatingAnnotationRegions()
        let utf8 = Array(separated.text.string.utf8)
        func text(utf8Offset: UInt32, utf8Length: UInt32) -> String {
            String(decoding: utf8[Int(utf8Offset) ..< Int(utf8Offset) + Int(utf8Length)], as: UTF8.self)
        }
        let annotations = separated.annotations
        let regionIndex = try #require(annotations.regions.indices.first { annotations.regions[$0].kind == .refinedForSwiftMember }, "\(separated.text.string)")
        let region = annotations.regions[regionIndex]
        #expect(text(utf8Offset: region.utf8Offset, utf8Length: region.utf8Length) == "// NS_REFINED_FOR_SWIFT: var __settings: __C.PresentationSettings! { get set }")
        let segments = annotations.segments(inRegionAt: regionIndex).map { ($0.role.rawValue, text(utf8Offset: $0.utf8Offset, utf8Length: $0.utf8Length)) }
        #expect(segments.map(\.0) == ["marker", "label", "separator", "name", "type"], "\(segments)")
        #expect(segments.map(\.1) == ["// ", "NS_REFINED_FOR_SWIFT", ": ", "__settings", "__C.PresentationSettings!"], "\(segments)")

        let unmarked = try await builder(of: ObjCImplementationFixture.machOFile(.optimizedStripped))
        let unmarkedDefinition = try #require(unmarked.indexer.objcImportedClassDefinition(named: "ScenePresentationWidget"))
        let unmarkedPrint = try await unmarked.printer.printObjCImportedClassDefinition(unmarkedDefinition).frozen()
        let violation = CommentStructureContract.violation(marked: markedPrint, unmarked: unmarkedPrint)
        #expect(violation == nil, "\(violation ?? "")")
    }

    /// What a host puts back on the header: the members it marks
    /// `NS_REFINED_FOR_SWIFT`, keyed as API notes key them (evolution
    /// proposal `swift-first-imported-declarations`).
    @Test func theRefinedMembersOfAnImplementationClass() async throws {
        let builder = try await builder(of: ObjCImplementationFixture.machOFile(.optimizedStripped))
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "ScenePresentationWidget"))
        let refinedMembers = try builder.printer.objcMembersRefinedForSwift(in: definition)
        #expect(Set(refinedMembers) == [
            ObjCRefinedForSwiftMember(member: .property(name: "layerFilter", isClassProperty: false), evidence: .prefixedSwiftMember),
            ObjCRefinedForSwiftMember(member: .property(name: "settings", isClassProperty: false), evidence: .nameTakenBySwiftDeclaration),
        ])
        // A Swift extension of a class Objective-C implements refines nothing
        // the fixture's header declares.
        let clangWidget = try #require(builder.indexer.objcImportedClassDefinition(named: "ClangWidget"))
        #expect(try builder.printer.objcMembersRefinedForSwift(in: clangWidget).isEmpty)
    }

    /// The classes a host asks for refined members of: the ones the image's
    /// Swift code extends, its `@objc @implementation` classes included —
    /// not a Swift class's own extension, nor a class Swift only uses.
    @Test func theClassesSwiftExtends() async throws {
        let builder = try await fixtureBuilder()
        let classNames = builder.indexer.objcClassRuntimeNamesExtendedInSwift
        #expect(classNames.isSuperset(of: ["Widget", "DerivedImplementationWidget", "ClangWidget", "ScenePresentationWidget"]), "\(classNames)")
        #expect(!classNames.contains("PresentationFilter"), "\(classNames)")
        #expect(!classNames.contains { $0.contains("SwiftDerivedWidget") }, "\(classNames)")
    }

    /// The Swift interface of the implementation itself: a stored property
    /// whose setter left no symbol, of a settable `weak` Objective-C property
    /// (evolution proposal `swift-first-imported-declarations`). It used to
    /// print `let scene`.
    @Test func aStoredPropertyIsAsSettableAndWeakAsItsObjectiveCProperty() async throws {
        let builder = try await builder(of: ObjCImplementationFixture.machOFile(.optimizedStripped))
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "ScenePresentationWidget"))
        let implementation = try #require(definition.swiftExtensions.first { $0.objcImplementation != nil })
        let printed = try await builder.printer.printExtensionDefinition(implementation).string
        #expect(printed.contains("weak var scene: __C.NSObject?"), "\(printed)")
        #expect(!printed.contains("let scene"), "\(printed)")
    }

    @Test func aSwiftClassPrintsAsItself() async throws {
        let builder = try await fixtureBuilder()
        let runtimeName = try #require(builder.indexer.objcImportedClassRuntimeNames.first { $0.hasSuffix("SwiftDerivedWidget") })
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: runtimeName))
        #expect(definition.isSwiftClass)
        #expect(definition.swiftClassDefinition != nil)

        let printed = try await builder.printer.printObjCImportedClassDefinition(definition).string
        #expect(printed.contains("class SwiftDerivedWidget: __C.ClangWidget, ObjCImplementationFixture.WidgetObserving {"), "\(printed)")
        #expect(printed.contains("@objc(pokeUsingForce:) func poke(force: Swift.Int)"), "\(printed)")
        // An extension in the class's own module mangles its members as the
        // class's, so `extension SwiftDerivedWidget { @objc public func
        // fromExtension() }` is the class's member.
        #expect(printed.contains("fromExtension()"), "\(printed)")
        // Every Objective-C method is a member of the Swift class: no
        // extension of the rest follows.
        #expect(!printed.contains("no member of the Swift class answers to"), "\(printed)")
    }

    /// `@objc public protocol WidgetObserving`, read from its record the way
    /// the importer reads a header: its names are the importer's, whatever
    /// the Swift source called them (`widgetWillPing()` was renamed
    /// `@objc(widgetWillPingSoon)`).
    @Test func aProtocolTakesTheImportersNames() async throws {
        let builder = try await fixtureBuilder()
        let definition = try #require(builder.indexer.objcImportedProtocolDefinition(named: "_TtP25ObjCImplementationFixture15WidgetObserving_"))
        let printed = try await builder.printer.printObjCImportedProtocolDefinition(definition).string
        #expect(printed.contains("protocol WidgetObserving"), "\(printed)")
        #expect(printed.contains("func widgetDidPing(_: __C.ClangWidget!)"), "\(printed)")
        #expect(printed.contains("optional func widgetWillPingSoon()"), "\(printed)")
    }

    /// `@interface NSObject (SeparatelyShipped)`, implemented in the
    /// separately shipped dylib: a category on a class of another image
    /// stays a category.
    @Test func aCategoryOnAClassOfAnotherImage() async throws {
        let categoriesLibrary: MachOFile
        switch try MachOKit.loadFromFile(url: ObjCImplementationFixture.categoriesLibraryURL()) {
        case .machO(let machOFile):
            categoriesLibrary = machOFile
        case .fat(let fatFile):
            categoriesLibrary = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        let builder = try await builder(of: categoriesLibrary)
        #expect(builder.indexer.objcImportedCategoryUniqueNames == ["NSObject(SeparatelyShipped)"])
        let definition = try #require(builder.indexer.objcImportedCategoryDefinition(uniqueName: "NSObject(SeparatelyShipped)"))
        #expect(definition.categoryName == "SeparatelyShipped")
        #expect(definition.swiftExtensions.isEmpty)

        let printed = try await builder.printer.printObjCImportedCategoryDefinition(definition).string
        #expect(printed.contains("extension __C.NSObject {"), "\(printed)")
        #expect(printed.contains("The Objective-C category NSObject(SeparatelyShipped)."), "\(printed)")
        // `noteValueForKeyPath:ofObject:` is `noteValue(forKeyPath:of:)` in
        // the SDK: `Object` restates the type of an `id` argument.
        #expect(printed.contains("func noteValue(forKeyPath: Any!, of: Any!)"), "\(printed)")
    }
}
