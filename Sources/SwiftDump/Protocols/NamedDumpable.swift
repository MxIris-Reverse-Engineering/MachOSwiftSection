import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public protocol NamedDumpable: Dumpable {
    func dumpName<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
}
