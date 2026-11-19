import Demangling

extension DemangleOptions {
    /// The options that change nothing but how a name is spelled, the way a
    /// `.swiftinterface` spells it: SE-0491 module selectors (`Swift::Int`) and
    /// the SE-0335 `any` keyword on existentials. A print carries the ones it
    /// uses into every name it has another printer spell — the upstream
    /// `NodePrinter` a node is delegated to, an opaque type resolver — so one
    /// declaration never mixes two spellings.
    public static let interfaceSpellingOptions: DemangleOptions = [.useModuleSelectors, .useExistentialAny]
}

extension SwiftDeclarationPrintConfiguration {
    /// The ``DemangleOptions/interfaceSpellingOptions`` this configuration
    /// turns on.
    var spellingOptions: DemangleOptions {
        var options: DemangleOptions = []
        if usesModuleSelectors {
            options.insert(.useModuleSelectors)
        }
        if usesExistentialAny {
            options.insert(.useExistentialAny)
        }
        return options
    }
}

extension NodePrintable {
    /// The ``DemangleOptions/interfaceSpellingOptions`` this printer uses,
    /// fixed when it was created.
    var spellingOptions: DemangleOptions {
        var options: DemangleOptions = []
        if context.usesModuleSelectors {
            options.insert(.useModuleSelectors)
        }
        if context.usesExistentialAny {
            options.insert(.useExistentialAny)
        }
        return options
    }
}
