import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

/// An `@objc` protocol declared in Swift (evolution proposal
/// `swift-declared-objc-protocols`), as the `dump` path's top-level unit. It
/// has no protocol descriptor, so it is no `Protocol`: what the image keeps
/// of it is a field descriptor naming it and an Objective-C protocol record.
extension SwiftDeclaredObjCProtocol: NamedDumpable {
    package func dumpName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString {
        try await dumpedName(using: configuration.demangleResolver, configuration: configuration)
    }

    package func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await SwiftDeclaredObjCProtocolDumper(self, using: configuration, in: machO).body
        }
    }

    /// The `Protocol` node of its Swift name.
    package func protocolNode() throws -> Node {
        guard let protocolNode = try demangleAsNodeTransient(mangledName).first(of: .protocol) else {
            throw SwiftDeclaredObjCProtocolDumpError.nameIsNoProtocol(mangledName: mangledName)
        }
        return protocolNode
    }

    /// The name a dump declares for this protocol — behind
    /// `dumpName(using:in:)` and `SwiftDeclaredObjCProtocolDumper`'s name
    /// alike.
    @SemanticStringBuilder
    package func dumpedName(using resolver: DemangleResolver, configuration: DumperConfiguration) async throws -> SemanticString {
        let protocolNode = try protocolNode()
        if configuration.displayParentName {
            try await resolver.resolve(for: Node.createTransient(kind: .type, child: protocolNode)).replacingTypeNameOrOtherToTypeDeclaration()
        } else if let leafNode = protocolNode.children.dropFirst().first, leafNode.kind == .privateDeclName {
            leafNode.printSemantic(using: [.showPrivateDiscriminators])
        } else {
            TypeDeclaration(kind: .protocol, protocolNode.children.dropFirst().first?.text ?? qualifiedName)
        }
    }

    /// Where it sits in the image, the `--preferred-binary-order` key: its
    /// field descriptor, or its record without one.
    package var offset: Int {
        switch evidence {
        case .fieldDescriptor(let offset): offset
        case .runtimeName: record?.offset ?? 0
        }
    }

    /// Every one the image declares, in field-descriptor order.
    package static func all(in machO: some MachOSwiftSectionRepresentableWithCache) -> [SwiftDeclaredObjCProtocol] {
        SwiftDeclaredObjCProtocolIndex.shared.protocols(in: machO)
    }
}

package enum SwiftDeclaredObjCProtocolDumpError: Swift.Error, CustomStringConvertible {
    case nameIsNoProtocol(mangledName: String)

    package var description: String {
        switch self {
        case .nameIsNoProtocol(let mangledName): "the name \(mangledName) of an @objc protocol's field descriptor names no protocol"
        }
    }
}

extension SwiftDeclaredObjCProtocol {
    /// The records Swift emitted that no protocol of the image claims: a
    /// renamed protocol of another module the image references — followed by
    /// its Swift name when an image of the dependency closure declares it —
    /// or one of its own renamed to a name other than its Swift name. `nil`
    /// when there are none.
    package static func unclaimedRecordsComment(using resolver: DemangleResolver, in machO: some MachOSwiftSectionRepresentableWithCache) async throws -> String? {
        let runtimeNames = SwiftDeclaredObjCProtocolIndex.shared.unclaimedSwiftEmittedRecords(in: machO).map(\.runtimeName)
        guard !runtimeNames.isEmpty else { return nil }
        var entries: [String] = []
        for runtimeName in runtimeNames {
            if let protocolNode = ObjCRuntimeNames.swiftProtocolNode(forRuntimeName: runtimeName, in: machO) {
                let swiftName = try await resolver.resolve(for: Node.createTransient(kind: .type, child: protocolNode)).string
                entries.append("\(runtimeName) → \(swiftName)")
            } else {
                entries.append(runtimeName)
            }
        }
        return "ObjC protocol records emitted by Swift that no protocol of this image claims — renamed protocols of other modules it references, with the Swift name where the dependency closure declares one, or its own renamed to a name other than their Swift names: \(entries.joined(separator: ", "))"
    }
}
