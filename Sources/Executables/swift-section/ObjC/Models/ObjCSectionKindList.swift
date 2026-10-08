import ArgumentParser
import Foundation
import SwiftSectionKit

/// A comma-separated list of ``ObjCDeclarationKind``, as in `--sections classes,protocols`.
///
/// Deliberately a single value rather than an array option. `dump` also takes
/// the binary as a positional argument, and an array option — `.upToNextOption`
/// or repeating — makes `--sections classes protocols <path>` swallow the path
/// as one more kind. That was the previous spelling, and it left no correct way
/// to write the two together except putting the path first.
///
/// The comma form also matches `evolution --labels 17.0,18.0,26.0`, the CLI's
/// other multi-value option.
struct ObjCSectionKindList: ExpressibleByArgument, Equatable, Sendable {
    let kinds: [ObjCDeclarationKind]

    init?(argument: String) {
        // Empty subsequences are kept so that a stray comma (`classes,`) fails
        // the kind lookup below instead of being silently dropped.
        let spelledKinds = argument
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var resolvedKinds: [ObjCDeclarationKind] = []
        for spelledKind in spelledKinds {
            guard let kind = ObjCDeclarationKind(rawValue: spelledKind) else { return nil }
            // A repeated kind would dump the same declarations twice.
            if !resolvedKinds.contains(kind) {
                resolvedKinds.append(kind)
            }
        }
        guard !resolvedKinds.isEmpty else { return nil }
        self.kinds = resolvedKinds
    }

    /// Drives both shell completion and the "Please provide one of …" hint in
    /// the parse error. A single kind is itself a valid value, so listing the
    /// kinds is accurate as far as it goes.
    static var allValueStrings: [String] {
        ObjCDeclarationKind.allCases.map(\.rawValue)
    }
}
