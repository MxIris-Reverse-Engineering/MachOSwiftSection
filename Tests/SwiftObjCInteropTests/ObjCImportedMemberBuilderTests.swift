import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOFixtureSupport
@_spi(Internals) import Demangling
@testable import MachOSwiftSection
@_spi(Internals) @testable import SwiftInspection
@_spi(Internals) @testable import SwiftObjCInterop

/// `ObjCImportedContainerIndex` and `ObjCImportedMemberBuilder` (evolution
/// proposal `objc-imported-declarations`): an Objective-C class of AppKit,
/// loaded into the test process, read from its method and property lists and
/// built into the members Swift imports.
@Suite
struct ObjCImportedMemberBuilderTests {
    private static func appKit() throws -> MachOImage {
        _ = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW)
        return try #require(MachOImage(named: .AppKit))
    }

    private static func members(ofClassNamed className: String, in machO: MachOImage) throws -> [ObjCImportedMember] {
        let record = try #require(ObjCImportedContainerIndex.shared.classRecord(named: className, in: machO))
        let classNode = ObjCRuntimeNames.classNode(forRuntimeName: className, in: machO)
        return ObjCImportedMemberBuilder.members(of: record, contextNode: classNode, contextTypeName: className, in: machO)
    }

    private static func printed(_ member: ObjCImportedMember) -> String {
        member.node.print(using: .interface)
    }

    @Test func readsAClassFromItsLists() throws {
        let appKit = try Self.appKit()
        let record = try #require(ObjCImportedContainerIndex.shared.classRecord(named: "NSColor", in: appKit))
        #expect(record.kind == .class)
        #expect(record.uniqueName == "NSColor")
        #expect(record.superclassRuntimeName == "NSObject")
        #expect(!record.isSwiftClass)
        #expect(record.protocolRuntimeNames.contains("NSCopying"))
        #expect(record.classMethods.contains { $0.selector == "colorWithRed:green:blue:alpha:" })
        #expect(record.classProperties.contains { $0.name == "blackColor" })
        #expect(record.instanceProperties.contains { $0.name == "CGColor" })
        #expect(ObjCImportedContainerIndex.shared.classRuntimeNames(in: appKit).contains("NSColor"))
    }

    @Test func readsTheImageCategories() throws {
        let appKit = try Self.appKit()
        let uniqueNames = ObjCImportedContainerIndex.shared.categoryUniqueNames(in: appKit)
        #expect(!uniqueNames.isEmpty)
        for uniqueName in uniqueNames {
            let record = try #require(ObjCImportedContainerIndex.shared.categoryRecord(uniqueName: uniqueName, in: appKit))
            guard case .category(let name) = record.kind else {
                Issue.record("\(uniqueName) reads as a class")
                continue
            }
            #expect(uniqueName == "\(record.classRuntimeName)(\(name))")
            #expect(!record.isSwiftClass)
        }
    }

    @Test func buildsTheMembersSwiftImports() throws {
        let appKit = try Self.appKit()
        let members = try Self.members(ofClassNamed: "NSColor", in: appKit)

        // A factory method restating the class name is an initializer.
        let factory = try #require(members.first { $0.selector == "colorWithRed:green:blue:alpha:" })
        #expect(factory.kind == .factoryInitializer)
        #expect(!factory.isClassMember)
        #expect(Self.printed(factory).contains("init(red: Swift.Double, green: Swift.Double, blue: Swift.Double, alpha: Swift.Double)"), "\(Self.printed(factory))")

        // A class property of the class's own type drops the type's name.
        let black = try #require(members.first { $0.selector == "blackColor" && $0.isClassMember })
        #expect(black.kind == .property)
        #expect(!black.isSettable)
        #expect(Self.printed(black).contains("black"), "\(Self.printed(black))")
        #expect(!Self.printed(black).contains("blackColor"), "\(Self.printed(black))")

        // A property is listed once, where its getter is, never as methods.
        let cgColor = members.filter { $0.selector == "CGColor" }
        #expect(cgColor.map(\.kind) == [.property])
        #expect(cgColor.first.map(Self.printed)?.contains("cgColor") == true)

        // What Swift never sees is left out.
        #expect(!members.contains { $0.selector == ".cxx_destruct" || $0.selector == "dealloc" })
    }

    @Test func objectPropertiesCarryTheirOwnership() throws {
        let appKit = try Self.appKit()
        let members = try Self.members(ofClassNamed: "NSWindow", in: appKit)
        let title = try #require(members.first { $0.selector == "title" && !$0.isClassMember })
        #expect(title.kind == .property)
        #expect(title.ownership == .copy)
        #expect(title.setterSelector == "setTitle:")
        // A non-object property has none.
        let level = try #require(members.first { $0.selector == "level" && !$0.isClassMember })
        #expect(level.ownership == nil)
    }
}
