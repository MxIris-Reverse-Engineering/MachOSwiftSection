import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName<MachO: MachOFieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
    func dumpProtocolName<MachO: MachOFieldLayoutRenderable>(using configuration: DumperConfiguration, in machO: MachO) async throws -> SemanticString
}
