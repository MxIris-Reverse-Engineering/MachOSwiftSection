import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import Dependencies
@_spi(Internals) import MachOSymbols
@testable import SwiftInspection

package protocol DumpableTests {
    var isEnabledSearchMetadata: Bool { get }
}

package struct DumpableTypeOptions: OptionSet {
    package let rawValue: Int

    package init(rawValue: Int) {
        self.rawValue = rawValue
    }

    package static let `enum` = DumpableTypeOptions(rawValue: 1 << 0)
    package static let `struct` = DumpableTypeOptions(rawValue: 1 << 1)
    package static let `class` = DumpableTypeOptions(rawValue: 1 << 2)
}

extension DumpableTests {
    package var isEnabledSearchMetadata: Bool { false }

    @MainActor
    package func dumpProtocols<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            try await Protocol(descriptor: protocolDescriptor, in: machO).dump(using: .demangleOptions(.test), in: machO).string.print()
        }
    }

    @MainActor
    package func dumpProtocolConformances<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            try await ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: .demangleOptions(.test), in: machO).string.print()
        }
    }

    @MainActor
    package func dumpTypes<MachO: MachOSwiftSectionRepresentableWithCache & MachOOffsetConverter>(for machO: MachO, isDetail: Bool = true, options: DumpableTypeOptions = [.enum, .struct, .class]) async throws {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        var metadataFinder: MetadataFinder<MachO>?
        if isEnabledSearchMetadata {
            metadataFinder = MetadataFinder(machO: machO)
        }
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .enum(let enumDescriptor):
                guard options.contains(.enum) else { continue }
                do {
                    if isDetail {
                        let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                        try await enumType.dump(using: .demangleOptions(.test), in: machO).string.print()
                    } else {
                        print(enumDescriptor)
                    }
                } catch {
                    error.print()
                }
            case .struct(let structDescriptor):
                guard options.contains(.struct) else { continue }
                do {
                    if isDetail {
                        let structType = try Struct(descriptor: structDescriptor, in: machO)
                        try await structType.dump(using: .demangleOptions(.test), in: machO).string.print()
                    } else {
                        print(structDescriptor)
                    }
                    if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                        try metadata.fieldOffsets(for: structDescriptor, in: machO).print()
                    }
                } catch {
                    error.print()
                }
            case .class(let classDescriptor):
                guard options.contains(.class) else { continue }
                do {
                    if isDetail {
                        let classType = try Class(descriptor: classDescriptor, in: machO)
                        try await classType.dump(using: .demangleOptions(.test), in: machO).string.print()
                    } else {
                        print(classDescriptor)
                    }
                    if let metadata = try metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                        try metadata.fieldOffsets(for: classDescriptor, in: machO).print()
                    }
                } catch {
                    error.print()
                }
            }
        }
    }

    @MainActor
    package func dumpOpaqueTypes<MachO: MachOSwiftSectionRepresentableWithCache & MachOOffsetConverter>(for machO: MachO) async throws {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore
        let symbols = symbolIndexStore.symbols(of: .opaqueTypeDescriptor, in: machO)
        for symbol in symbols where symbol.offset != 0 {
            var offset = symbol.offset

            if let cache = machO.cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
            }
            let opaqueTypeDescriptor = try machO.readWrapperElement(offset: offset) as OpaqueTypeDescriptor
            let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
            for underlyingTypeArgumentMangledName in opaqueType.underlyingTypeArgumentMangledNames {
                try MetadataReader.demangleType(for: underlyingTypeArgumentMangledName, in: machO).print(using: .interface).print()
            }
            "-----".print()
        }
    }

    @MainActor
    package func dumpAssociatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try await AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: .demangleOptions(.test), in: machO).string.print()
        }
    }

    @MainActor
    package func dumpBuiltinTypes<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let descriptors = try machO.swift.builtinTypeDescriptors
        for descriptor in descriptors {
            try print(BuiltinType(descriptor: descriptor, in: machO))
        }
    }
}
