/// Something a request says about its own progress, as opposed to the
/// product it produces.
///
/// `message` is the line exactly as `swift-section` prints it, so a host that
/// shows diagnostics shows the same words the command line does. Some of
/// those words name command-line options — they were written for the command
/// line first.
public struct SwiftSectionDiagnostic: Sendable, Hashable {
    public enum Severity: Sendable, Hashable, CaseIterable {
        /// A step is starting or has finished ("Indexing old binary…").
        case progress
        /// The request goes on, but with less than was asked for.
        case warning
        /// A fact about the result worth knowing ("no classes found in …").
        case note
        /// One declaration could not be produced; the rest of the product
        /// still is.
        case error
    }

    public var severity: Severity
    public var message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}
