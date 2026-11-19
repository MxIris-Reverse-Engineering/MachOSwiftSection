import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public protocol ConformedDumpable: Dumpable {
    /// The conforming type's name as a dump prints it. Naming only reads, so
    /// it takes a `ReadingContext`; the full dump still needs the Mach-O.
    func dumpTypeName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString
    /// The conformed protocol's name as a dump prints it.
    func dumpProtocolName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString
}
