import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
@testable import MachOTestingSupport

/// `dump` lists a property's SE-0400 init accessor among its type's variable
/// symbols, with the address and export status every member symbol gets
/// (evolution proposal `init-accessor-recovery`).
@Suite
struct InitAccessorDumpTests {
    private typealias Property = InitAccessorFixture.Property

    private func typeDumps(_ variant: InitAccessorFixture.Variant) async throws -> [String: String] {
        let machOFile = try await InitAccessorFixture.machOFile(variant)
        var dumps: [String: String] = [:]
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            switch typeContextDescriptor {
            case .struct(let structDescriptor):
                let name = try structDescriptor.name(in: machOFile.context)
                dumps[name] = try await Struct(descriptor: structDescriptor, in: machOFile.context).dump(using: .demangleOptions(.interface), in: machOFile).string
            case .class(let classDescriptor):
                let name = try classDescriptor.name(in: machOFile.context)
                dumps[name] = try await Class(descriptor: classDescriptor, in: machOFile.context).dump(using: .demangleOptions(.interface), in: machOFile).string
            default:
                continue
            }
        }
        return dumps
    }

    /// The start of the line naming `property`'s init accessor symbol.
    private func initAccessorSymbolPrefix(of property: Property) -> String {
        "\(InitAccessorFixture.moduleName).\(property.typeName).\(property.name).init : "
    }

    @Test(arguments: [InitAccessorFixture.Variant.debug, .release])
    func everyInitAccessorIsListed(variant: InitAccessorFixture.Variant) async throws {
        let dumps = try await typeDumps(variant)
        for property in InitAccessorFixture.propertiesWithInitAccessors {
            let dump = try #require(dumps[property.typeName], "no type \(property.typeName)")
            #expect(dump.contains(initAccessorSymbolPrefix(of: property)), "\(property) not in:\n\(dump)")
        }
        let angle = try #require(dumps["Angle"])
        #expect(angle.contains("InitAccessorFixture.Angle.radians.init : Swift.Double"), "\(angle)")
    }

    @Test(arguments: [InitAccessorFixture.Variant.releaseDeadStripped, .releaseStripped])
    func aStrippedImageListsOnlyTheExportedOnes(variant: InitAccessorFixture.Variant) async throws {
        let dumps = try await typeDumps(variant)
        for property in InitAccessorFixture.propertiesWithInitAccessors {
            let dump = try #require(dumps[property.typeName], "no type \(property.typeName)")
            #expect(dump.contains(initAccessorSymbolPrefix(of: property)) == InitAccessorFixture.propertiesWithExportedInitAccessors.contains(property), "\(property) in:\n\(dump)")
        }
    }

    /// The function SwiftUICore keeps under a stored property's init
    /// accessor name is a member symbol like any other.
    @Test(arguments: InitAccessorFixture.Variant.allCases)
    func theStoredPropertysInitAccessorSymbolIsListed(variant: InitAccessorFixture.Variant) async throws {
        let property = InitAccessorFixture.storedPropertyWithInitAccessorSymbol
        let dump = try #require(try await typeDumps(variant)[property.typeName])
        #expect(dump.contains(initAccessorSymbolPrefix(of: property) + "Swift.Int"), "\(dump)")
    }
}
