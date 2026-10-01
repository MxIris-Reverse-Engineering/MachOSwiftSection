import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Utilities
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

extension Class: NamedDumpable {
    public func dumpName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedName(using: configuration.demangleResolver, configuration: configuration, in: context)
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await ClassDumper(self, using: configuration, in: machO).body
        }
    }

    /// The name a dump declares for this class when it has no specialized
    /// metadata — behind `dumpName(using:in:)` and `ClassDumper`'s unbound
    /// name alike.
    @SemanticStringBuilder
    package func dumpedName(using resolver: DemangleResolver, configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        if configuration.displayParentName {
            try await resolver.resolve(for: SymbolicDemangler.demangleContext(for: .type(.class(descriptor)), in: context)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .class, descriptor.name(in: context))
        }
    }
}
