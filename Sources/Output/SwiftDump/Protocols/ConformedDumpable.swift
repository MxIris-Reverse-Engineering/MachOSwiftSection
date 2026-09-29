import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString
    func dumpProtocolName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString
}
