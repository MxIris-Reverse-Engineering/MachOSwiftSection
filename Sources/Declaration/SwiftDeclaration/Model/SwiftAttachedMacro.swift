import MachOSwiftSection
import SwiftInspection

/// A macro attached to a declaration in its source, recognized from what its
/// expansion left in the binary (evolution proposal
/// `observable-macro-folding`).
///
/// The compiler keeps no record of a macro, only of what it generated, so a
/// recognized macro is an inference from that output.
/// `ObservableMacroRecognition` says what the inference for `@Observable`
/// reads.
///
/// A struct with static members rather than an enum: the set of macros the
/// library recognizes grows, and a host's `switch` over it must not stop
/// compiling when it does.
public struct SwiftAttachedMacro: Hashable, Sendable {
    /// The macro's name as its attribute spells it: `Observable`.
    public let name: String

    /// The module that declares the macro: `Observation`.
    public let moduleName: String

    package init(name: String, moduleName: String) {
        self.name = name
        self.moduleName = moduleName
    }

    /// `@Observable`, from the Observation module: a class whose stored
    /// properties tell observers when they change.
    public static let observable = SwiftAttachedMacro(
        name: ObservableMacroRecognition.observableName,
        moduleName: ObservableMacroRecognition.observationModuleName
    )

    /// `@ObservationTracked`, from the Observation module: the macro
    /// `@Observable` attaches to each property it tracks, which writes the
    /// property's accessors and its storage. It appears in an expansion of
    /// `@Observable`, never on a type (evolution proposal
    /// `observable-nested-expansion`).
    public static let observationTracked = SwiftAttachedMacro(
        name: ObservableMacroRecognition.observationTrackedName,
        moduleName: ObservableMacroRecognition.observationModuleName
    )
}

extension SwiftAttachedMacro {
    /// The macros the source attached to the type `descriptor` describes, as
    /// far as their expansion shows.
    package static func macros(attachedTo descriptor: TypeContextDescriptorWrapper, in context: some ReadingContext) -> Set<SwiftAttachedMacro> {
        ObservableMacroRecognition.isObservableClass(descriptor, in: context) ? [.observable] : []
    }
}
