import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling

public enum DemangleResolver: Sendable {
    case options(DemangleOptions)
    case builder(@Sendable (Node) async throws -> SemanticString)

    public static func using(options: DemangleOptions) -> DemangleResolver {
        .options(options)
    }

    public static func using(@SemanticStringBuilder builder: @Sendable @escaping (Node) async throws -> SemanticString) -> DemangleResolver {
        .builder(builder)
    }

    public func resolve(for node: Node) async throws -> SemanticString {
        switch self {
        case .options(let options):
            #if DEBUG
            return await MainActor.run {
                return node.printSemantic(using: options)
            }
            #else
            return node.printSemantic(using: options)
            #endif
        case .builder(let builder):
            return try await builder(node)
        }
    }

    public func modify(_ modifier: (DemangleResolver) -> DemangleResolver) -> DemangleResolver {
        modifier(self)
    }
}
