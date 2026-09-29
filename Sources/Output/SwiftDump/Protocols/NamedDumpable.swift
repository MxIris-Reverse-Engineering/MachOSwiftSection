import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public protocol NamedDumpable: Dumpable {
    func dumpName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString
}
