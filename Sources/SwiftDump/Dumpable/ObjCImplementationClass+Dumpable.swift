import Foundation
import MachOKit
import MachOSwiftSection
import MachOFoundation
import Semantic
import Utilities
import SwiftDeclarationRendering
@_spi(Internals) import SwiftInspection

/// A class implemented through `@objc @implementation` (evolution proposal
/// `objc-implementation-class-recognition`), as the `dump` path's top-level
/// unit. It has no `__swift5_*` presence at all — the class object is pure
/// ObjC — so it is not a `TopLevelType`; the facts come from the ObjC
/// classlist joined with the symbol table.
public struct ObjCImplementationClass: Sendable {
    public let facts: ObjCImplementationClassFacts

    /// Offset of the class object in the image, the `--preferred-binary-order` key.
    public var offset: Int { facts.classObjectOffset }

    public init(facts: ObjCImplementationClassFacts) {
        self.facts = facts
    }

    /// Every recognized class of the image, in `__objc_classlist` order.
    public static func all(in machO: some MachORepresentableWithCache) -> [ObjCImplementationClass] {
        ObjCImplementationClasses.all(in: machO).map { ObjCImplementationClass(facts: $0) }
    }
}

extension ObjCImplementationClass: NamedDumpable {
    public func dumpName(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await ObjCImplementationClassDumper(self, using: configuration, in: machO).name
    }

    public func dump(using configuration: DumperConfiguration, in machO: some MachOFieldLayoutRenderable) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await ObjCImplementationClassDumper(self, using: configuration, in: machO).body
        }
    }
}
