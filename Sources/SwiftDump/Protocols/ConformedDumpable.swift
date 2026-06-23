import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
    func dumpProtocolName<MachO: FieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
}
