import Foundation

/// Where a request's product goes.
public enum ProductDestination: Sendable, Hashable {
    /// To the request's ``SwiftSectionOutput``, one piece at a time.
    case output
    /// Into the file at `path`, written once the product is complete. The
    /// output then receives diagnostics only.
    ///
    /// A path rather than a `URL` because the diagnostics that announce the
    /// write repeat it exactly as the caller spelled it; a `URL` normalizes a
    /// trailing slash away and expands a tilde.
    case file(path: String)
}

extension ProductDestination {
    /// Writes `text` to the file, or hands it to `output` as one piece.
    ///
    /// The two differ by a trailing newline — the output's pieces are printed
    /// with one, the file gets `text` as is — which is how every command has
    /// written its reports, kept byte for byte.
    func deliver(
        _ text: String,
        to output: some SwiftSectionOutput,
        announcingFileWith fileWrittenMessage: ((String) -> String)? = nil
    ) throws {
        switch self {
        case .output:
            output.write(.text(text))
        case .file(let path):
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            if let fileWrittenMessage {
                output.reportProgress(fileWrittenMessage(path))
            }
        }
    }
}
