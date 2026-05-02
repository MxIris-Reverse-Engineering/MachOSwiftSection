import Foundation
import MachOExtensions
import MachOFoundation
@testable import MachOSwiftSection

/// Centralizes the "pick (main + variants) fixture entities for each descriptor type"
/// logic, ensuring Suites and their corresponding BaselineGenerators look at the
/// same set of entities.
///
/// Both target descriptors have unique `name(in:)` values within the
/// `SymbolTestsCore` fixture, so a parent-chain disambiguator is unnecessary.
package enum BaselineFixturePicker {
    /// Picks the concrete (non-generic) struct `Structs.StructTest` from the
    /// `SymbolTestsCore` fixture.
    package static func struct_StructTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "StructTest"
            })
        )
    }

    /// Picks the generic struct
    /// `GenericFieldLayout.GenericStructNonRequirement<A>` from the
    /// `SymbolTestsCore` fixture. Exercises generic context paths.
    package static func struct_GenericStructNonRequirement(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: { descriptor in
                try descriptor.name(in: machO) == "GenericStructNonRequirement"
            })
        )
    }
}
