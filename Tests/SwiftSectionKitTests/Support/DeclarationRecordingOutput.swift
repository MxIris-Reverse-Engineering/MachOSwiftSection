import Foundation
import SwiftSectionKit

/// A `SwiftSectionOutput` that also takes the declarations `dump` and
/// `objc dump` name, keeping every product piece beside the declaration it
/// came with, in order.
///
/// `RecordingOutput` stays the output that only implements `write(_:)`, so
/// the suites using it go on exercising the default `write(_:declaring:)`.
///
/// `@unchecked Sendable`: every access goes through `lock`.
final class DeclarationRecordingOutput: SwiftSectionOutput, @unchecked Sendable {
    struct Piece {
        var product: SwiftSectionProduct
        /// `nil` for a piece handed over through `write(_:)`.
        var declaration: DumpedDeclaration?

        /// The rendered text of a `.declarations` piece, `nil` for any other.
        var declarationText: String? {
            if case .declarations(let semanticString) = product { semanticString.string } else { nil }
        }
    }

    private let lock = NSLock()
    private var recordedPieces: [Piece] = []
    private var recordedDiagnostics: [SwiftSectionDiagnostic] = []

    func write(_ product: SwiftSectionProduct) {
        lock.withLock { recordedPieces.append(Piece(product: product, declaration: nil)) }
    }

    func write(_ product: SwiftSectionProduct, declaring declaration: DumpedDeclaration) {
        lock.withLock { recordedPieces.append(Piece(product: product, declaration: declaration)) }
    }

    func report(_ diagnostic: SwiftSectionDiagnostic) {
        lock.withLock { recordedDiagnostics.append(diagnostic) }
    }

    var pieces: [Piece] {
        lock.withLock { recordedPieces }
    }

    /// The `.declarations` pieces, in order.
    var declarationPieces: [Piece] {
        pieces.filter { $0.declarationText != nil }
    }

    var diagnostics: [SwiftSectionDiagnostic] {
        lock.withLock { recordedDiagnostics }
    }

    /// The declaration the first `.declarations` piece starting with `prefix`
    /// came with — `nil` when no piece starts so, or the piece came without one.
    func declaration(ofPieceStartingWith prefix: String) -> DumpedDeclaration? {
        declarationPieces.first { $0.declarationText?.hasPrefix(prefix) == true }?.declaration
    }
}
