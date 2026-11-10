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
/// importer's rules; an `@objc @implementation` class and category whose
/// members come from their Swift implementations; a category Swift wrote on
/// the Objective-C class; and a Swift class registered with the runtime.
@Suite(.serialized, ExclusiveImageAccess(ObjCImplementationFixture.moduleName))
struct ObjCImportedDefinitionTests {
    private func builder() async throws -> SwiftInterfaceBuilder<MachOFile> {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(dependencySearchPaths: try ObjCImplementationFixture.dependencySearchPaths())
        )
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return builder
    }

    @Test func aClassDeclaredInObjectiveCTakesTheImportersNames() async throws {
        let builder = try await builder()
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "ClangWidget"))
        #expect(!definition.isSwiftClass)
        #expect(definition.swiftClassDefinition == nil)
        #expect(definition.implementationExtensions.isEmpty)

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
    }

    @Test func anImplementationClassTakesItsMembersFromSwift() async throws {
        let builder = try await builder()
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: "Widget"))
        #expect(!definition.implementationExtensions.isEmpty)

        let printed = try await builder.printer.printObjCImportedClassDefinition(definition).string
        #expect(printed.contains("class Widget: __C.NSObject {"), "\(printed)")
        // The Swift members' own types: non-optional, which no method list records.
        #expect(printed.contains("title: Swift.String"), "\(printed)")
        #expect(!printed.contains("title: Swift.String!"), "\(printed)")
        #expect(printed.contains("init(title: Swift.String)"), "\(printed)")
        #expect(printed.contains("func refresh()"), "\(printed)")
    }

    @Test func aCategoryTakesItsMembersFromTheSwiftExtensionImplementingIt() async throws {
        let builder = try await builder()

        // `@objc(Extras) @implementation extension Widget`.
        let extras = try #require(builder.indexer.objcImportedCategoryDefinition(uniqueName: "Widget(Extras)"), "\(builder.indexer.objcImportedCategoryUniqueNames)")
        #expect(extras.categoryName == "Extras")
        let printedExtras = try await builder.printer.printObjCImportedCategoryDefinition(extras).string
        #expect(printedExtras.contains("The Objective-C category Widget(Extras)."), "\(printedExtras)")
        #expect(printedExtras.contains("describe() -> Swift.String"), "\(printedExtras)")
        #expect(!printedExtras.contains("describe() -> Swift.String!"), "\(printedExtras)")

        // `extension ClangWidget { @objc public func swiftAdded() -> Int }`.
        let uniqueName = try #require(builder.indexer.objcImportedCategoryUniqueNames.first { $0.hasPrefix("ClangWidget(") })
        let swiftCategory = try #require(builder.indexer.objcImportedCategoryDefinition(uniqueName: uniqueName))
        let printedSwiftCategory = try await builder.printer.printObjCImportedCategoryDefinition(swiftCategory).string
        #expect(printedSwiftCategory.contains("swiftAdded() -> Swift.Int"), "\(printedSwiftCategory)")
    }

    @Test func aSwiftClassPrintsAsItself() async throws {
        let builder = try await builder()
        let runtimeName = try #require(builder.indexer.objcImportedClassRuntimeNames.first { $0.hasSuffix("PlainSwiftSibling") })
        let definition = try #require(builder.indexer.objcImportedClassDefinition(named: runtimeName))
        #expect(definition.isSwiftClass)
        #expect(definition.swiftClassDefinition != nil)

        let printed = try await builder.printer.printObjCImportedClassDefinition(definition).string
        #expect(printed.contains("class PlainSwiftSibling"), "\(printed)")
        #expect(printed.contains("poke()"), "\(printed)")
        // Every Objective-C method is a member of the Swift class: no
        // extension of the rest follows.
        #expect(!printed.contains("no member of the Swift class answers to"), "\(printed)")
    }

    /// `@objc public protocol WidgetObserving`, read from its record the way
    /// the importer reads a header: its names are the importer's, whatever
    /// the Swift source called them (`widgetWillPing()` was renamed
    /// `@objc(widgetWillPingSoon)`).
    @Test func aProtocolTakesTheImportersNames() async throws {
        let builder = try await builder()
        let definition = try #require(builder.indexer.objcImportedProtocolDefinition(named: "_TtP25ObjCImplementationFixture15WidgetObserving_"))
        let printed = try await builder.printer.printObjCImportedProtocolDefinition(definition).string
        #expect(printed.contains("protocol WidgetObserving"), "\(printed)")
        #expect(printed.contains("func widgetDidPing(_: __C.ClangWidget!)"), "\(printed)")
        #expect(printed.contains("optional func widgetWillPingSoon()"), "\(printed)")
    }
}
