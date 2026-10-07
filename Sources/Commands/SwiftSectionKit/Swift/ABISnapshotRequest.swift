import Foundation
import MachODependencies
import SwiftDiffing

/// `swift-section snapshot`: index a binary's Swift ABI and persist it as a
/// baseline document — or relabel an existing document.
public struct ABISnapshotRequest: Sendable, Equatable {
    public var source: SnapshotSource
    public var binaryLoading: BinaryLoadingOptions
    /// Where the images a standalone binary links are looked for when a type
    /// must be read out of another image's accessor thunk. Named paths are
    /// consulted first; empty infers them from where the binary sits.
    public var dependencySearchPaths: [DependencySearchPath]
    /// A human-readable version label stored in the provenance (`17.0`).
    public var label: String?
    public var destination: ProductDestination

    public init(
        source: SnapshotSource,
        binaryLoading: BinaryLoadingOptions = .init(),
        dependencySearchPaths: [DependencySearchPath] = [],
        label: String? = nil,
        destination: ProductDestination = .output
    ) {
        self.source = source
        self.binaryLoading = binaryLoading
        self.dependencySearchPaths = dependencySearchPaths
        self.label = label
        self.destination = destination
    }

    /// Produces the document, delivers its JSON, and returns it.
    @discardableResult
    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws -> ABISnapshotDocument {
        let document = try await withAccessorThunkResolver(searchPaths: dependencySearchPaths) {
            try await ABISnapshotLoading.loadDocument(
                from: source,
                binaryLoading: binaryLoading,
                label: label,
                output: output,
                environment: environment
            )
        }
        let encoded = try document.encoded()
        switch destination {
        case .output:
            output.write(.data(encoded))
        case .file(let path):
            try encoded.write(to: URL(fileURLWithPath: path), options: .atomic)
            output.reportProgress("Snapshot written to \(path)")
        }
        return document
    }
}
