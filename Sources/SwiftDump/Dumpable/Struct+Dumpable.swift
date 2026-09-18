import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
import SwiftDeclarationRendering

extension Struct: NamedDumpable {
    public func dumpName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await StructDumper(self, using: configuration, in: machO).name
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await StructDumper(self, using: configuration, in: machO).body
        }
    }
}
