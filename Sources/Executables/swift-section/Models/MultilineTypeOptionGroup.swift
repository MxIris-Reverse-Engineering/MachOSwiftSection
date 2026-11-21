import ArgumentParser
import SwiftDeclarationRendering

/// `--multiline-types` and `--maximum-line-width`, on `dump` and `interface`
/// (evolution proposal `multiline-type-formatting`).
struct MultilineTypeOptionGroup: ParsableArguments, Sendable {
    @Flag(name: .customLong("multiline-types"), help: "Break a type that runs past the line width over several lines, at its brackets: each argument of a generic with two or more arguments on a line of its own, and a single-argument generic, a tuple, a parameter list or [...] sugar only when something inside it breaks. A type that fits stays on one line, and so does a line that is long for any other reason.")
    var multilineTypes: Bool = false

    @Option(name: .customLong("maximum-line-width"), help: ArgumentHelp("The widest a line may be, not counting its indentation, before --multiline-types breaks its types. (default: \(MultilineTypeFormatting().maximumLineWidth))", valueName: "columns"))
    var maximumLineWidth: Int?

    mutating func validate() throws {
        guard let maximumLineWidth else { return }
        guard multilineTypes else {
            throw ValidationError("--maximum-line-width needs --multiline-types.")
        }
        guard maximumLineWidth > 0 else {
            throw ValidationError("--maximum-line-width must be a positive number of columns, got \(maximumLineWidth).")
        }
    }

    /// The formatting these options ask for; `nil` without `--multiline-types`.
    var multilineTypeFormatting: MultilineTypeFormatting? {
        guard multilineTypes else { return nil }
        guard let maximumLineWidth else { return MultilineTypeFormatting() }
        return MultilineTypeFormatting(maximumLineWidth: maximumLineWidth)
    }
}
