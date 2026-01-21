import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities
import Dependencies
import OrderedCollections
@_spi(Internals) import MachOSymbols

package struct ExtensionDumped: Sendable {}

package struct ExtensionDumper<MachO: MachOSwiftSectionRepresentableWithCache>: Dumper {
    package let dumped: ExtensionDumped

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: ExtensionDumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    package var declaration: SemanticString {
        get async throws {}
    }

    package var body: SemanticString {
        get async throws {}
    }
}

package struct GlobalDumper<MachO: MachOSwiftSectionRepresentableWithCache>: Dumper {
    package let dumped: ExtensionDumped

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: ExtensionDumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    package var declaration: SemanticString {
        get async throws {}
    }

    package var body: SemanticString {
        get async throws {}
    }
}
