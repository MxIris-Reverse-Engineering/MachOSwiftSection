import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Demangling
import Utilities
import SwiftDeclarationRendering
import OrderedCollections

extension ProtocolConformance: ConformedDumpable {
    public func dumpTypeName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedTypeName(isFull: false, resolver: configuration.demangleResolver, in: context)
    }

    public func dumpProtocolName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedProtocolName(using: configuration.demangleResolver, in: context)
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await ProtocolConformanceDumper(self, using: configuration, in: machO).body
        }
    }

    /// The conforming type's name as a dump prints it, in the interface-type
    /// spelling; the full form keeps the resolver's own options. Behind
    /// `dumpTypeName(using:in:)` and `ProtocolConformanceDumper` alike.
    @SemanticStringBuilder
    package func dumpedTypeName(isFull: Bool, resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        try typeNode(in: context)?.printSemantic(using: isFull ? resolver.options ?? .interfaceType : .interfaceType).replacingTypeNameOrOtherToTypeDeclaration()
    }

    /// The conformed protocol's name as a dump prints it. Behind
    /// `dumpProtocolName(using:in:)` and `ProtocolConformanceDumper` alike.
    @SemanticStringBuilder
    package func dumpedProtocolName(using resolver: DemangleResolver, in context: some ReadingContext) async throws -> SemanticString {
        try await protocolNode(in: context).asyncMap { try await resolver.resolve(for: $0) }
    }
}
