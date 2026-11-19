import MachOKit
import Semantic
import MachOSwiftSection
import SwiftDeclarationRendering

public protocol NamedDumpable: Dumpable {
    /// The declared name a dump prints for this entity. Naming only reads,
    /// so it takes a `ReadingContext`; the full dump still needs the Mach-O.
    func dumpName(using configuration: DumperConfiguration, in context: some ReadingContext) async throws -> SemanticString
}
