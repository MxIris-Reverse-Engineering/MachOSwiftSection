import Foundation
import SwiftDeclaration

/// Where a request's output goes. `swift-section` writes it to stdout and
/// stderr; a test records it.
///
/// Three channels, kept apart so that a host never has to pick a product out
/// of a stream of progress lines: the product itself, the diagnostics about
/// producing it, and the handlers that hear about indexing degradations.
///
/// A request that indexes several inputs side by side (`diff`, `evolution`)
/// calls this from several tasks at once, so an implementation must be safe to
/// call concurrently.
public protocol SwiftSectionOutput: Sendable {
    /// One piece of the product, in order. Printed, every piece is followed by
    /// a newline.
    func write(_ product: SwiftSectionProduct)

    /// One top-level declaration of a `dump` or `objc dump`, with what it
    /// declares; it takes that piece's place in the order of ``write(_:)``.
    /// A request writing to a file hands no piece over, so this is not called
    /// then either.
    ///
    /// The default hands `product` to ``write(_:)`` and drops `declaration`,
    /// so an output that only prints is unaffected.
    func write(_ product: SwiftSectionProduct, declaring declaration: DumpedDeclaration)

    /// A progress line, warning, note or per-declaration error.
    func report(_ diagnostic: SwiftSectionDiagnostic)

    /// The indexing-event handlers for one indexed input. `label` names the
    /// input when a request indexes several ("old", "new", a version label),
    /// and is `nil` for a single-input request.
    func indexEventHandlers(forInputLabeled label: String?) -> [any SwiftIndexEvents.Handler]
}

extension SwiftSectionOutput {
    /// The piece alone, as any other.
    public func write(_ product: SwiftSectionProduct, declaring declaration: DumpedDeclaration) {
        write(product)
    }

    /// No handler: indexing degradations fall to `SwiftIndexEvents.Dispatcher`'s
    /// os_log floor.
    public func indexEventHandlers(forInputLabeled label: String?) -> [any SwiftIndexEvents.Handler] {
        []
    }
}

extension SwiftSectionOutput {
    func reportProgress(_ message: String) {
        report(SwiftSectionDiagnostic(severity: .progress, message: message))
    }

    func reportWarning(_ message: String) {
        report(SwiftSectionDiagnostic(severity: .warning, message: message))
    }

    func reportNote(_ message: String) {
        report(SwiftSectionDiagnostic(severity: .note, message: message))
    }

    func reportError(_ message: String) {
        report(SwiftSectionDiagnostic(severity: .error, message: message))
    }
}
