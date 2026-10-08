import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

extension Enum: NamedDumpable {
    public func dumpName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedName(using: configuration.demangleResolver, configuration: configuration, in: context)
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await EnumDumper(self, using: configuration, in: machO).body
        }
    }

    /// The name a dump declares for this enum when it has no specialized
    /// metadata — behind `dumpName(using:in:)` and `EnumDumper`'s unbound
    /// name alike.
    @SemanticStringBuilder
    package func dumpedName(using resolver: DemangleResolver, configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        if configuration.displayParentName {
            try await resolver.resolve(for: SymbolicDemangler.demangleContext(for: .type(.enum(descriptor)), in: context)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .enum, descriptor.name(in: context))
        }
    }
}
