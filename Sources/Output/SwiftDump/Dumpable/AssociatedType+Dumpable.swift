import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

extension AssociatedType: ConformedDumpable {
    public func dumpTypeName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedTypeName(using: configuration.demangleResolver, in: context)
    }

    public func dumpProtocolName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedProtocolName(using: configuration.demangleResolver, in: context)
    }

    /// The conforming type's name as a dump prints it. Behind
    /// `dumpTypeName(using:in:)` and `AssociatedTypeDumper` alike.
    package func dumpedTypeName(using resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        try await resolver.resolve(for: SymbolicDemangler.demangleType(for: conformingTypeName, in: context)).replacingTypeNameOrOtherToTypeDeclaration()
    }

    /// The protocol's name as a dump prints it. Behind
    /// `dumpProtocolName(using:in:)` and `AssociatedTypeDumper` alike.
    package func dumpedProtocolName(using resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        try await resolver.resolve(for: SymbolicDemangler.demangleType(for: protocolTypeName, in: context))
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await AssociatedTypeDumper(self, using: configuration, in: machO).body
        }
    }
}
