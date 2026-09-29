import Foundation

/// Writes one line to stderr.
///
/// Progress, warnings and diagnostics all go here so that a redirected stdout
/// stays a pure product: `swift-section objc dump … > Header.h` must not pick up a
/// progress line. Shared because every command needs it, and four hand-rolled
/// copies of this one line had already accumulated.
func writeStandardErrorLine(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
