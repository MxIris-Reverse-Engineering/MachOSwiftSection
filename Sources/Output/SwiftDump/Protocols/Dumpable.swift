import Demangling
import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public typealias DemangleOptions = Demangling.DemangleOptions

public protocol Dumpable: Sendable {
    func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString
}
