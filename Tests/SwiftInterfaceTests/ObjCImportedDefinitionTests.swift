import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) import SwiftInterface
@_spi(Support) import SwiftPrinting
import SwiftObjCInterop
@testable import MachOTestingSupport

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
    private func builder(of machOFile: MachOFile) async throws -> SwiftInterfaceBuilder<MachOFile> {
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(dependencySearchPaths: try ObjCImplementationFixture.dependencySearchPaths())
        )
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
