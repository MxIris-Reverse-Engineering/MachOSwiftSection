import Demangling
import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public typealias DemangleOptions = Demangling.DemangleOptions

public protocol Dumpable: Sendable {
    func dump<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
}
