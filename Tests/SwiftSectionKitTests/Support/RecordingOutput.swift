import Foundation
import SwiftDeclaration
import SwiftSectionKit

/// A `SwiftSectionOutput` that keeps everything it is handed, in order.
///
/// `@unchecked Sendable`: every access goes through `lock`.
final class RecordingOutput: SwiftSectionOutput, @unchecked Sendable {
    enum Event {
        case product(SwiftSectionProduct)
        case diagnostic(SwiftSectionDiagnostic)
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []
    private var recordedIndexingLabels: [String?] = []

    func write(_ product: SwiftSectionProduct) {
        lock.withLock { recordedEvents.append(.product(product)) }
    }

    func report(_ diagnostic: SwiftSectionDiagnostic) {
        lock.withLock { recordedEvents.append(.diagnostic(diagnostic)) }
    }

    func indexEventHandlers(forInputLabeled label: String?) -> [any SwiftIndexEvents.Handler] {
        lock.withLock { recordedIndexingLabels.append(label) }
        return []
    }

    var events: [Event] {
        lock.withLock { recordedEvents }
    }

    var products: [SwiftSectionProduct] {
        events.compactMap { event in
            if case .product(let product) = event { product } else { nil }
        }
    }

    var diagnostics: [SwiftSectionDiagnostic] {
        events.compactMap { event in
            if case .diagnostic(let diagnostic) = event { diagnostic } else { nil }
        }
    }

    func messages(of severity: SwiftSectionDiagnostic.Severity) -> [String] {
        diagnostics.filter { $0.severity == severity }.map(\.message)
    }

    /// The labels the request asked indexing-event handlers for, in order.
    var indexingLabels: [String?] {
        lock.withLock { recordedIndexingLabels }
    }

    /// The product as a terminal without colors shows it: every piece
    /// followed by a newline.
    var printedProduct: String {
        products.map { product in
            switch product {
            case .declarations(let semanticString):
                semanticString.string + "\n"
            case .text(let text):
                text + "\n"
            case .annotatedInterface(let text, _):
                text + "\n"
            case .data(let data):
                String(decoding: data, as: UTF8.self) + "\n"
            }
        }.joined()
    }
}

extension SwiftSectionEnvironment {
    /// A fixed generator and a fixed date, so that two runs stamp the same
    /// bytes.
    static let testing = SwiftSectionEnvironment(
        generator: GeneratorIdentity(name: "swift-section-kit-tests", version: "9.9.9"),
        currentDate: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
}
