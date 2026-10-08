import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import OrderedCollections

extension MachOSwiftSection.`Protocol`: NamedDumpable {
    public func dumpName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedName(using: configuration.demangleResolver, configuration: configuration, in: context)
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await ProtocolDumper(self, using: configuration, in: machO).body
        }
    }

    /// The name a dump declares for this protocol — behind
    /// `dumpName(using:in:)` and `ProtocolDumper`'s name alike.
    @SemanticStringBuilder
    package func dumpedName(using resolver: DemangleResolver, configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        if configuration.displayParentName {
            try await resolver.resolve(for: SymbolicDemangler.demangleContext(for: .protocol(descriptor), in: context)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .protocol, descriptor.name(in: context))
        }
    }
}
