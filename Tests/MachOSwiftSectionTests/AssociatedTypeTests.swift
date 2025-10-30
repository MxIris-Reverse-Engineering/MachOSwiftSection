import Foundation
import Testing
import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@_spi(Internals) @testable import MachOSymbols

final class AssociatedTypeTests: DyldCacheTests, @unchecked Sendable {
    @MainActor
    @Test
    func associatedTypes() throws {
        let machO = machOFileInMainCache

        for associatedType in try machO.swift.associatedTypes {
            let conformingTypeName = try MetadataReader.demangleType(for: associatedType.conformingTypeName, in: machO).print(using: .interfaceType)
            let protocolTypeName = try MetadataReader.demangleType(for: associatedType.protocolTypeName, in: machO).print(using: .interfaceType)
//            if conformingTypeName == "SwiftUI.LeadingTrailingLabeledContentStyle", protocolTypeName == "SwiftUI.LabeledContentStyle" {
            conformingTypeName.print()
            protocolTypeName.print()
                for record in associatedType.records {
                    let substitutedTypeName = try record.substitutedTypeName(in: machO)
                    try MetadataReader.demangleType(for: substitutedTypeName, in: machO).print().print()
//                    substitutedTypeName.startOffset.print()
                    
                }
                "----------------".print()
//            }
        }
    }
}
