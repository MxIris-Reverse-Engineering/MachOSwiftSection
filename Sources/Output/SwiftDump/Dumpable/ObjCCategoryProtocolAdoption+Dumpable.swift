import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

/// The Objective-C protocols one of the image's categories lists, as a
/// `dump` unit beside the conformance records (evolution proposal
/// `swift-declared-objc-protocols`): an extension of another module's class
/// that adopts them, which no conformance record names.
extension ObjCCategoryProtocolAdoption: NamedDumpable {
    /// The extended class's name.
    package func dumpName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await configuration.demangleResolver.resolve(for: Node.createTransient(kind: .type, child: classNode()))
    }

    /// `extension NSView: P, Q {}`, then the category's offset and the
    /// protocols a Swift conformance implies — the interface leaves those
    /// out.
    package func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await dumpedDeclaration(using: configuration, in: machO)
        }
    }

    @SemanticStringBuilder
    private func dumpedDeclaration(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        let resolver = configuration.demangleResolver
        Keyword(.extension)
        Space()
        try await dumpName(using: configuration, in: machO.context)
        for (offset, runtimeName) in protocolRuntimeNames.offsetEnumerated() {
            Standard(offset.isStart ? ":" : ",")
            Space()
            try await resolver.resolve(for: Node.createTransient(kind: .type, child: ObjCRuntimeNames.protocolNode(forRuntimeName: runtimeName, in: machO)))
        }
        Space()
        Standard("{}")
        Space()
        let implied = protocolRuntimeNames.filter(impliedProtocolRuntimeNames.contains)
        if implied.isEmpty {
            Comment("ObjC category at 0x\(String(offset, radix: 16))")
        } else {
            Comment("ObjC category at 0x\(String(offset, radix: 16)); implied by a Swift conformance: \(implied.joined(separator: ", "))")
        }
    }

    /// The extended class: a Swift class by its mangled runtime name, any
    /// other in `__C`.
    private func classNode() -> Node {
        if classRuntimeName.hasPrefix("_Tt") || classRuntimeName.hasPrefix("$s"),
           let classNode = (try? demangleAsNodeTransient(classRuntimeName))?.first(of: .class) {
            return classNode
        }
        return Node.createTransient(kind: .class, children: [
            Node.createTransient(kind: .module, text: objcModule),
            Node.createTransient(kind: .identifier, text: classRuntimeName),
        ])
    }
}
