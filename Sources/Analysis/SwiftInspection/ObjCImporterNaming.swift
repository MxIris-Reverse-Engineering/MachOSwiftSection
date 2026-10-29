/// The Swift importer's names for the methods of an Objective-C protocol,
/// ported for the requirements of an `@objc` protocol declared in Swift
/// (evolution proposal `swift-declared-objc-protocols`). The binary keeps no
/// Swift name for such a requirement, only its selector and type encodings;
/// the name the importer would give the same Objective-C declaration is what
/// the interface prints, with `@objc(selector)` pinning the selector.
///
/// Ported from the Swift repository: `omitNeedlessWords` and what it calls
/// in `lib/Basic/StringExtras.cpp` (word splitting, parts of speech,
/// splitting the base name at its last preposition, dropping words a
/// parameter's type makes redundant), and from
/// `lib/ClangImporter/ImportName.cpp` the parts it hands over to: the
/// initializer family, the subscript accessors, the error convention.
/// Left out: what needs a header the binary does not keep — nullability,
/// default arguments, `NS_SWIFT_NAME` — and the `async` import, which the
/// proposal keeps as a completion handler.
///
/// One step is the library's own, after the importer's: Swift inserts `With`
/// before a first argument label that starts with no preposition
/// (`hangPoints(input:)` → `hangPointsWithInput:`), so a first label
/// starting with `with` and going on drops it (`hangPoints(withInput:)` →
/// `hangPoints(input:)`).
package enum ObjCImporterNaming {
    /// The importer's name for one method.
    package struct ImportedName: Sendable, Hashable {
        package enum Kind: Sendable, Hashable {
            case method
            case initializer
            case subscriptGetter
            case subscriptSetter
        }

        /// How a method following the error convention imports.
        package enum ErrorConvention: Sendable, Hashable {
            /// `- (BOOL)…error:`: `throws`, returning nothing.
            case booleanResult
            /// `- (id)…error:`: `throws`, returning the object non-optional.
            case nonNilResult
        }

        package let kind: Kind
        /// `init` for an initializer, `subscript` for a subscript accessor.
        package let baseName: String
        /// One label per Swift parameter; empty for an unlabeled one.
        package let argumentLabels: [String]
        /// For each Swift parameter, the index of the Objective-C parameter
        /// it imports: the error parameter has none.
        package let parameterIndices: [Int]
        package let errorConvention: ErrorConvention?
    }

    /// The name the importer gives the method `selector` of a protocol whose
    /// name is `contextTypeName`.
    ///
    /// - Parameters:
    ///   - methodType: the method's extended type encoding, read; the plain
    ///     one when the record carries no extended one.
    ///   - propertyNames: the protocol's property names, which keep a type
    ///     name in a selector from being dropped as redundant.
    ///   - undoesSwiftInsertedWith: whether to take the library's own step
    ///     after the importer's; `false` gives the importer's name exactly.
    package static func importedName(
        selector: String,
        isClassMethod: Bool,
        methodType: ObjCMethodTypeEncoding,
        contextTypeName: String,
        propertyNames: Set<String> = [],
        undoesSwiftInsertedWith: Bool = true
    ) -> ImportedName {
        let pieces = selectorPieces(selector)
        let parameterTypes = methodType.parameterTypes

        if !isClassMethod, let subscriptKind = subscriptKind(of: selector) {
            return ImportedName(kind: subscriptKind, baseName: "subscript", argumentLabels: Array(repeating: "", count: parameterTypes.count), parameterIndices: Array(parameterTypes.indices), errorConvention: nil)
        }

        var baseName = pieces.first ?? selector
        // A selector without a colon takes no argument.
        var argumentNames: [String] = selector.hasSuffix(":") ? [""] + pieces.dropFirst() : []
        var parameterIndices = Array(0 ..< argumentNames.count)
        let isInitializer = !isClassMethod && isInitializerFamily(baseName) && isObject(methodType.returnType)

        if isInitializer {
            baseName = "init"
            let initializerPrefixLength = 4
            var argumentName = String((pieces.first ?? "").dropFirst(initializerPrefixLength))
            var droppedWith = false
            if argumentName.hasPrefix("With") {
                argumentName = String(argumentName.dropFirst(4))
                droppedWith = true
            }
            argumentName = toLowercaseWord(argumentName)
            if droppedWith, isSwiftReservedName(argumentName) {
                argumentName = "with" + String((pieces.first ?? "").dropFirst(initializerPrefixLength + 4))
            }
            if argumentNames.isEmpty {
                if !argumentName.isEmpty {
                    argumentNames.append(argumentName)
                }
            } else {
                argumentNames[0] = argumentName
            }
        }

        // The error convention: a trailing `NSError **`, past any trailing
        // blocks, on a method returning `BOOL` or an object.
        var errorConvention: ImportedName.ErrorConvention?
        if argumentNames.count == parameterTypes.count {
            var index = parameterTypes.count
            while index > 0 {
                index -= 1
                if case .block = parameterTypes[index] { continue }
                guard isErrorOutParameter(parameterTypes[index]) else { break }
                switch methodType.returnType {
                case .bool: errorConvention = .booleanResult
                case .object, .objectClass: errorConvention = .nonNilResult
                default: break
                }
                guard errorConvention != nil else { break }
                // Never the first parameter of an initializer.
                if !(isInitializer && index == 0) {
                    if index == 0, argumentNames[0].isEmpty {
                        for suffix in ["AndReturnError", "WithError"] where baseName.hasSuffix(suffix) {
                            let strippedBaseName = String(baseName.dropLast(suffix.count))
                            if !strippedBaseName.isEmpty, !isSwiftReservedName(strippedBaseName) {
                                baseName = strippedBaseName
                            }
                            break
                        }
                    }
                    argumentNames.remove(at: index)
                    parameterIndices.remove(at: index)
                }
                break
            }
        }

        let omissionParameterTypes = parameterIndices.map { omissionTypeName(of: parameterTypes[$0]) }
        let contextType = OmissionTypeName(name: contextTypeName)
        // An initializer returns `instancetype`: the context type.
        let resultTypeName = isInitializer ? contextType : omissionTypeName(of: methodType.returnType)
        omitNeedlessWords(
            baseName: &baseName,
            argumentNames: &argumentNames,
            resultType: resultTypeName,
            contextType: contextType,
            parameterTypes: omissionParameterTypes,
            allPropertyNames: propertyNames
        )

        // The library's own step: undo the `With` Swift inserts before a
        // first label that starts with no preposition.
        if undoesSwiftInsertedWith, !isInitializer, let firstLabel = argumentNames.first {
            let words = Words(firstLabel)
            if words.count > 1, words.word(0) == "with" {
                argumentNames[0] = toLowercaseInitialisms(toLowercaseWord(words.rest(1)))
            }
        }

        return ImportedName(kind: isInitializer ? .initializer : .method, baseName: baseName, argumentLabels: argumentNames, parameterIndices: parameterIndices, errorConvention: errorConvention)
    }

    // MARK: - Selectors

    static func selectorPieces(_ selector: String) -> [String] {
        guard selector.hasSuffix(":") else { return [selector] }
        return selector.dropLast().split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    }

    private static func subscriptKind(of selector: String) -> ImportedName.Kind? {
        switch selector {
        case "objectAtIndexedSubscript:", "objectForKeyedSubscript:": .subscriptGetter
        case "setObject:atIndexedSubscript:", "setObject:forKeyedSubscript:": .subscriptSetter
        default: nil
        }
    }

    /// The `init` method family: `init` alone, or followed by an uppercase
    /// letter (`initWithFrame:`), never by a lowercase one (`initialize`).
    private static func isInitializerFamily(_ firstPiece: String) -> Bool {
        guard firstPiece.hasPrefix("init") else { return false }
        let rest = firstPiece.utf8.dropFirst(4)
        guard let next = rest.first else { return true }
        return !isLowercase(next)
    }

    private static func isObject(_ type: ObjCEncodedType) -> Bool {
        if case .object = type { return true }
        return false
    }

    /// `NSError **`, which an encoding spells `^@`.
    private static func isErrorOutParameter(_ type: ObjCEncodedType) -> Bool {
        if case .pointer(.object, _) = type { return true }
        return false
    }

    // MARK: - Omission type names

    /// How a type takes part in omitting needless words
    /// (`swift::OmissionTypeName`).
    struct OmissionTypeName: Equatable {
        var name: String
        var collectionElement: String = ""
        var isBoolean = false
        var isFunction = false

        var isEmpty: Bool {
            name.isEmpty
        }
    }

    /// The importer's name for a type in this role
    /// (`getClangTypeNameForOmission`), from what an encoding keeps of it: a
    /// Swift class or protocol goes by the Swift name a generated header
    /// gives it, `NSInteger` and `NSUInteger` by their typedef names — which
    /// is what Swift's `Int` and `UInt` are exported as.
    static func omissionTypeName(of type: ObjCEncodedType) -> OmissionTypeName {
        switch type {
        case .void: return OmissionTypeName(name: "Void")
        case .bool: return OmissionTypeName(name: "Bool", isBoolean: true)
        case .character: return OmissionTypeName(name: "Int8")
        case .unsignedCharacter: return OmissionTypeName(name: "UInt8")
        case .short: return OmissionTypeName(name: "Int16")
        case .unsignedShort: return OmissionTypeName(name: "UInt16")
        case .int, .long: return OmissionTypeName(name: "Int32")
        case .unsignedInt, .unsignedLong: return OmissionTypeName(name: "UInt32")
        case .longLong: return OmissionTypeName(name: "NSInteger")
        case .unsignedLongLong: return OmissionTypeName(name: "NSUInteger")
        case .float: return OmissionTypeName(name: "Float")
        case .double: return OmissionTypeName(name: "Double")
        case .selector: return OmissionTypeName(name: "Selector")
        case .objectClass: return OmissionTypeName(name: "Class")
        case .block: return OmissionTypeName(name: "Block", isFunction: true)
        // `^?`: a function pointer.
        case .pointer(.unknown, _): return OmissionTypeName(name: "Function", isFunction: true)
        case .pointer(let pointee, _): return omissionTypeName(of: pointee)
        case .structure(let name), .union(let name):
            // The tag of `struct _NSRange` is what the encoding keeps; the
            // importer goes by the typedef, `NSRange`.
            guard let name else { return OmissionTypeName(name: "") }
            return OmissionTypeName(name: name.hasPrefix("_") ? String(name.dropFirst()) : name)
        case .array(_, let element):
            return OmissionTypeName(name: "Array", collectionElement: omissionTypeName(of: element).name)
        case .object(let className, let protocolNames):
            // `id<Proto>` and `NSObject<Proto>` go by the protocol.
            if protocolNames.count == 1, className == nil || className == "NSObject" {
                return OmissionTypeName(name: swiftName(ofProtocolRuntimeName: protocolNames[0]))
            }
            guard let className else {
                return OmissionTypeName(name: protocolNames.isEmpty ? "Object" : "")
            }
            let name = swiftName(ofClassRuntimeName: className)
            let lastWord = Words(name).lastWord
            guard lastWord == "Array" || lastWord == "Set" else { return OmissionTypeName(name: name) }
            // Foundation's collections are generic, and with no type
            // arguments the element is `Object`; another collection's
            // element is the class name before its last word.
            if name.hasPrefix("NS") {
                return OmissionTypeName(name: name, collectionElement: "Object")
            }
            return OmissionTypeName(name: name, collectionElement: String(name.dropLast(lastWord.count)))
        case .characterString, .longDouble, .bitField, .unknown:
            return OmissionTypeName(name: "")
        }
    }

    /// `DVTTeamCredentialComponents` for `_TtC13DVTFoundation27DVTTeamCredentialComponents`.
    private static func swiftName(ofClassRuntimeName runtimeName: String) -> String {
        guard runtimeName.hasPrefix("_Tt"), let qualifiedName = NodeTypeNaming.swiftClassQualifiedName(fromRuntimeName: runtimeName) else { return runtimeName }
        return qualifiedName.split(separator: ".").last.map(String.init) ?? runtimeName
    }

    private static func swiftName(ofProtocolRuntimeName runtimeName: String) -> String {
        guard let qualifiedName = SwiftDeclaredObjCProtocolIndex.qualifiedName(ofDefaultRuntimeName: runtimeName) else { return runtimeName }
        return qualifiedName.split(separator: ".").last.map(String.init) ?? runtimeName
    }

    // MARK: - omitNeedlessWords

    enum NameRole {
        case baseName
        case firstParameter
        case subsequentParameter
        case property
        case partial
    }

    /// `swift::omitNeedlessWords`, for a method that is neither a property
    /// accessor nor imported as `async`, and whose parameters take no
    /// default arguments (inferring those needs nullability).
    static func omitNeedlessWords(
        baseName: inout String,
        argumentNames: inout [String],
        resultType: OmissionTypeName,
        contextType: OmissionTypeName,
        parameterTypes: [OmissionTypeName],
        allPropertyNames: Set<String>?
    ) {
        defer {
            baseName = toLowercaseInitialisms(baseName)
            argumentNames = argumentNames.map(toLowercaseInitialisms)
        }

        // A result matching the context drops the context's name from the
        // front of the base name.
        let resultTypeMatchesContext = resultType == contextType
        if resultTypeMatchesContext {
            baseName = omitNeedlessWordsFromPrefix(baseName, type: contextType)
        }

        baseName = omitSelfTypeFromBaseName(baseName, typeName: contextType, allPropertyNames: allPropertyNames)

        if parameterTypes.isEmpty {
            if resultTypeMatchesContext {
                baseName = omitTrailingTypeName(baseName, typeName: resultType, role: .property, allPropertyNames: allPropertyNames)
            }
            return
        }

        if Words(baseName).firstWord == "set" {
            baseName = omitTrailingTypeName(baseName, typeName: contextType, role: .property, allPropertyNames: allPropertyNames)
        }

        if !argumentNames.isEmpty {
            splitBaseName(&baseName, argumentName: &argumentNames[0], parameterType: parameterTypes[0])
        }

        for index in argumentNames.indices where index < parameterTypes.count {
            let role: NameRole = index > 0 ? .subsequentParameter
                : argumentNames[0].isEmpty ? .baseName
                : baseName == "init" ? .subsequentParameter
                : .firstParameter
            let name = role == .baseName ? baseName : argumentNames[index]
            let newName = omitTrailingTypeName(name, typeName: parameterTypes[index], role: role, allPropertyNames: role == .baseName ? allPropertyNames : nil)
            guard newName != name else { continue }
            if role == .baseName {
                baseName = newName
            } else {
                argumentNames[index] = newName
            }
        }
    }

    // MARK: Splitting the base name

    /// `splitBaseName`. The importer also leaves an action method (a
    /// parameter named `sender`) unsplit; a binary keeps no parameter names.
    static func splitBaseName(_ baseName: inout String, argumentName: inout String, parameterType: OmissionTypeName) {
        guard argumentName.isEmpty else { return }
        let words = Words(baseName)
        if parameterType.isBoolean, words.lastWord == "Animated" {
            baseName = String(baseName.dropLast("Animated".count))
            argumentName = "animated"
            return
        }
        if words.firstWord == "set" {
            return
        }
        splitBaseNameAfterLastPreposition(&baseName, argumentName: &argumentName, parameterType: parameterType)
    }

    private static func splitBaseNameAfterLastPreposition(_ baseName: inout String, argumentName: inout String, parameterType: OmissionTypeName) {
        let words = Words(baseName)
        guard var prepositionIndex = lastPrepositionIndex(in: words, from: words.count - 1) else { return }
        var preposition = words.word(prepositionIndex)

        if prepositionIndex > 0, wordConflictsBeforePreposition(words.word(prepositionIndex - 1), preposition: preposition) {
            return
        }
        if prepositionIndex + 1 < words.count, wordConflictsAfterPreposition(words.word(prepositionIndex + 1), preposition: preposition) {
            return
        }

        let prepositionEnd = words.end(of: prepositionIndex)
        if prepositionIndex > 0, priorWordExtendsPreposition(words.word(prepositionIndex - 1), preposition: preposition) {
            prepositionIndex -= 1
            preposition = words.slice(from: words.start(of: prepositionIndex), to: prepositionEnd)
        }
        let prepositionStart = words.start(of: prepositionIndex)

        let beforePreposition = words.slice(from: 0, to: prepositionStart)
        let afterPreposition = words.slice(from: prepositionEnd, to: words.length)
        let dropsPreposition = isVacuousPreposition(beforePreposition, preposition: preposition, afterPreposition: afterPreposition, parameterType: parameterType)
        let placesPrepositionOnArgumentLabel = !(afterPreposition == "X" || afterPreposition == "Y" || afterPreposition == "Z")

        var startOfArgumentLabel = placesPrepositionOnArgumentLabel ? prepositionStart : prepositionEnd
        var endOfBaseName = startOfArgumentLabel
        if dropsPreposition {
            if placesPrepositionOnArgumentLabel {
                startOfArgumentLabel += preposition.utf8.count
            } else {
                endOfBaseName -= preposition.utf8.count
            }
        }
        guard endOfBaseName > 0 else { return }

        // A base name that would be a keyword or a vacuous word needs more
        // than one word after it — two for a vacuous one.
        let newBaseName = words.slice(from: 0, to: endOfBaseName)
        let newWords = Words(newBaseName)
        let firstWord = newWords.firstWord
        let isVacuous = isVacuousName(firstWord)
        if !canBeMemberName(firstWord) || isVacuous {
            if newWords.count == 1 { return }
            if newWords.count == 2, isVacuous { return }
        }

        argumentName = words.slice(from: startOfArgumentLabel, to: words.length)
        baseName = newBaseName
    }

    /// `findLastPreposition`: the last preposition, except that an `of`
    /// defers to an earlier preposition other than `of` and `for`.
    private static func lastPrepositionIndex(in words: Words, from start: Int, isRecursive: Bool = false) -> Int? {
        guard start >= 0 else { return nil }
        guard let index = stride(from: start, through: 0, by: -1).first(where: { partOfSpeech(words.word($0)) == .preposition }) else { return nil }
        if !isRecursive, sameWordIgnoringFirstCase(words.word(index), "of"),
           let previous = lastPrepositionIndex(in: words, from: index - 1, isRecursive: true),
           !sameWordIgnoringFirstCase(words.word(previous), "of"), !sameWordIgnoringFirstCase(words.word(previous), "for") {
            return previous
        }
        return index
    }

    private static func wordConflictsBeforePreposition(_ word: String, preposition: String) -> Bool {
        sameWordIgnoringFirstCase(preposition, "in") && sameWordIgnoringFirstCase(word, "plug")
    }

    private static func wordConflictsAfterPreposition(_ word: String, preposition: String) -> Bool {
        if sameWordIgnoringFirstCase(preposition, "with"), sameWordIgnoringFirstCase(word, "error") || sameWordIgnoringFirstCase(word, "no") {
            return true
        }
        if sameWordIgnoringFirstCase(preposition, "to"), sameWordIgnoringFirstCase(word, "visible") || sameWordIgnoringFirstCase(word, "backing") {
            return true
        }
        if sameWordIgnoringFirstCase(preposition, "from"), sameWordIgnoringFirstCase(word, "backing") {
            return true
        }
        return false
    }

    private static func priorWordExtendsPreposition(_ preceding: String, preposition: String) -> Bool {
        let extendedPrepositions: [(String, String)] = [
            ("compatible", "with"), ("best", "matching"), ("according", "to"), ("bound", "by"), ("separated", "by"),
        ]
        return extendedPrepositions.contains { sameWordIgnoringFirstCase(preceding, $0.0) && sameWordIgnoringFirstCase(preposition, $0.1) }
    }

    /// A `with` or `using` before a block parameter says nothing; one before
    /// `Zone` does.
    private static func isVacuousPreposition(_ beforePreposition: String, preposition: String, afterPreposition: String, parameterType: OmissionTypeName) -> Bool {
        guard sameWordIgnoringFirstCase(preposition, "with") || sameWordIgnoringFirstCase(preposition, "using") else { return false }
        if sameWordIgnoringFirstCase(preposition, "with"), sameWordIgnoringFirstCase(Words(afterPreposition).firstWord, "zone") {
            return false
        }
        return parameterType.isFunction
    }

    // MARK: Dropping redundant type names

    static func omitTrailingTypeName(_ name: String, typeName: OmissionTypeName, role: NameRole, allPropertyNames: Set<String>?) -> String {
        guard !name.isEmpty, !typeName.isEmpty else { return name }
        let words = Words(name)
        let matchIndex = matchTypeNameFromBack(words, typeName: typeName, allPropertyNames: allPropertyNames)
        if matchIndex == words.count {
            return name
        }
        if matchIndex == 0 {
            return role == .partial || role == .firstParameter ? "" : name
        }
        if matchIndex + 1 == words.count, words.word(matchIndex) == "Error" {
            return name
        }

        let previousWord = words.word(matchIndex - 1)
        switch role {
        case .property:
            break
        case .firstParameter, .partial, .subsequentParameter:
            if partOfSpeech(previousWord) == .unknown {
                return name
            }
        case .baseName:
            switch partOfSpeech(previousWord) {
            case .preposition:
                if matchIndex - 1 == 0 {
                    return name
                }
            case .verb, .gerund:
                if textMatchesPropertyName(words.rest(matchIndex), allPropertyNames: allPropertyNames) {
                    return name
                }
            case .unknown:
                return name
            }
        }

        let newName = words.prior(matchIndex)
        if role == .baseName || role == .property {
            if !canBeMemberName(newName) || isVacuousName(newName) {
                return name
            }
        }
        return newName
    }

    /// The index of the first word of `words` matching the end of
    /// `typeName`, `words.count` when none does
    /// (`matchTypeNameFromBackWithSpecialCases`).
    static func matchTypeNameFromBack(_ words: Words, typeName originalTypeName: OmissionTypeName, allPropertyNames: Set<String>?) -> Int {
        var typeName = originalTypeName
        var typeWords = Words(typeName.name)
        // Each index is one past the word compared next.
        var nameIndex = words.count
        var typeIndex = typeWords.count

        while nameIndex > 0, typeIndex > 0 {
            let nameWord = words.word(nameIndex - 1)
            let typeWord = typeWords.word(typeIndex - 1)
            if matchNameWordToTypeWord(nameWord, typeWord) {
                nameIndex -= 1
                typeIndex -= 1
                continue
            }

            // "Indexes" and "Indices" in the name match "IndexSet".
            if matchNameWordToTypeWord(nameWord, "Indexes") || matchNameWordToTypeWord(nameWord, "Indices"), typeWord == "Set",
               typeIndex >= 2, matchNameWordToTypeWord("Index", typeWords.word(typeIndex - 2)) {
                nameIndex -= 1
                typeIndex -= 2
                continue
            }

            // "Index" in the name matches "Int" or "Integer".
            if matchNameWordToTypeWord(nameWord, "Index"), matchNameWordToTypeWord("Int", typeWord) || matchNameWordToTypeWord("Integer", typeWord) {
                nameIndex -= 1
                typeIndex -= 1
                continue
            }

            // "ObjectValue" in the name matches "Object".
            if matchNameWordToTypeWord("Object", typeWord), matchNameWordToTypeWord(nameWord, "Value"),
               nameIndex >= 2, matchNameWordToTypeWord(words.word(nameIndex - 2), "Object") {
                nameIndex -= 2
                typeIndex -= 1
                continue
            }

            // A plural of the collection's element.
            if !typeName.collectionElement.isEmpty, nameWord.utf8.count > 2, nameWord.hasSuffix("s") {
                let shortened = String(words.prior(nameIndex).dropLast())
                let newShortened = omitTrailingTypeName(shortened, typeName: OmissionTypeName(name: typeName.collectionElement), role: .partial, allPropertyNames: allPropertyNames)
                if shortened != newShortened, let newIndex = words.index(startingAt: newShortened.utf8.count) {
                    nameIndex = newIndex
                    continue
                }
            }

            // A droppable suffix of the type, before any word matched.
            if nameIndex == words.count, let withoutSuffix = skipTypeSuffix(typeName.name) {
                typeName.name = withoutSuffix
                typeWords = Words(withoutSuffix)
                typeIndex = typeWords.count
                continue
            }
            break
        }
        return nameIndex
    }

    /// `omitSelfTypeFromBaseName`: the context type's name, wherever it sits
    /// in the base name after a verb (`dismissViewControllerAnimated` in a
    /// view controller gives `dismissAnimated`).
    static func omitSelfTypeFromBaseName(_ name: String, typeName originalTypeName: OmissionTypeName, allPropertyNames: Set<String>?) -> String {
        guard !name.isEmpty, !originalTypeName.isEmpty else { return name }
        var typeName = originalTypeName
        typeName.collectionElement = ""
        let words = Words(name)

        var matchingRange: (start: Int, end: Int)?
        var wordIndex = words.count - 1
        while wordIndex >= 0 {
            let prefixWords = Words(words.prior(wordIndex + 1))
            let matchIndex = matchTypeNameFromBack(prefixWords, typeName: typeName, allPropertyNames: allPropertyNames)
            let matchStart = words.index(startingAt: prefixWords.start(of: matchIndex)) ?? (wordIndex + 1)
            if matchStart != wordIndex + 1 {
                matchingRange = (matchStart, wordIndex + 1)
                break
            }
            while let withoutSuffix = skipTypeSuffix(typeName.name) {
                typeName.name = withoutSuffix
            }
            wordIndex -= 1
        }

        guard let range = matchingRange, range.start != 0 else { return name }
        if range.end == words.count, range.start + 1 == words.count, words.word(range.start) == "Error" {
            return name
        }
        guard partOfSpeech(words.word(range.start - 1)) == .verb else { return name }

        // The importer measures the removed text from the match's start with
        // the match's end as a length; ported as it is.
        let removedStart = words.start(of: range.start)
        let removedText = words.slice(from: removedStart, to: min(words.length, removedStart + words.start(of: range.end)))
        if textMatchesPropertyName(removedText, allPropertyNames: allPropertyNames) {
            return name
        }

        let newName = words.prior(range.start) + words.rest(range.end)
        guard canBeMemberName(newName), !isVacuousName(newName) else { return name }
        return newName
    }

    /// `omitNeedlessWordsFromPrefix`: the type's name at the front of the
    /// name, when what follows starts with a preposition.
    static func omitNeedlessWordsFromPrefix(_ name: String, type: OmissionTypeName) -> String {
        guard !type.isEmpty else { return name }
        let newName = matchLeadingTypeName(name, typeName: type)
        guard newName != name else { return name }
        let newWords = Words(newName)
        let firstWord = newWords.firstWord
        guard partOfSpeech(firstWord) == .preposition, newName.utf8.count > firstWord.utf8.count else { return name }
        // "By" followed by a gerund goes too.
        if firstWord == "By", newWords.count > 1, newWords.word(1).hasSuffix("ing") {
            return newWords.rest(1)
        }
        return newName
    }

    private static func matchLeadingTypeName(_ name: String, typeName: OmissionTypeName) -> String {
        let nameWords = Words(name)
        let typeWords = Words(typeName.name)
        guard nameWords.count > 0, typeWords.count > 0 else { return name }
        // The last word of the type name matching the name's first word.
        guard let typeStart = stride(from: typeWords.count - 1, through: 0, by: -1).first(where: { matchNameWordToTypeWord(nameWords.word(0), typeWords.word($0)) }) else { return name }
        // From there to the end of the type name, word by word.
        var nameIndex = 1
        var typeIndex = typeStart + 1
        while typeIndex < typeWords.count, nameIndex < nameWords.count, matchNameWordToTypeWord(typeWords.word(typeIndex), nameWords.word(nameIndex)) {
            typeIndex += 1
            nameIndex += 1
        }
        guard typeIndex == typeWords.count else { return name }
        return nameWords.rest(nameIndex)
    }

    /// `matchNameWordToTypeWord`, as the importer writes it.
    static func matchNameWordToTypeWord(_ nameWord: String, _ typeWord: String) -> Bool {
        let name = Array(nameWord.utf8)
        let type = Array(typeWord.utf8)
        if name.count > type.count { return false }
        if name.count < type.count {
            // A suffix of the type, past an acronym prefix (`NS` in `NSURL`).
            if typeWord.lowercased().hasSuffix(nameWord.lowercased()), !isLowercase(type[type.count - name.count]) {
                for index in 0 ..< name.count where isLowercase(type[index]) || type[index] == UInt8(ascii: "_") {
                    return false
                }
                return true
            }
            // A prefix of the type, followed by digits only.
            if typeWord.lowercased().hasPrefix(nameWord.lowercased()) {
                return type[name.count...].allSatisfy(isDigit)
            }
            return false
        }
        return nameWord.lowercased() == typeWord.lowercased()
    }

    /// `skipTypeSuffix`: `Type`, `Ref`, `Mask`, a dimension (`3D`), `_t`.
    static func skipTypeSuffix(_ typeName: String) -> String? {
        guard !typeName.isEmpty else { return nil }
        let lastWord = Words(typeName).lastWord
        let length = typeName.utf8.count
        if lastWord == "Type", length > 4 { return String(typeName.dropLast(4)) }
        if lastWord == "Ref", length > 3 { return String(typeName.dropLast(3)) }
        if lastWord == "Mask", length > 4 { return String(typeName.dropLast(4)) }
        let bytes = Array(typeName.utf8)
        if bytes.last == UInt8(ascii: "D"), length > 1 {
            var firstDigit = length - 1
            while firstDigit > 0, isDigit(bytes[firstDigit - 1]) {
                firstDigit -= 1
            }
            if firstDigit < length - 1 {
                return String(decoding: bytes[..<firstDigit], as: UTF8.self)
            }
        }
        if length > 2, typeName.hasSuffix("_t") { return String(typeName.dropLast(2)) }
        return nil
    }

    private static func textMatchesPropertyName(_ text: String, allPropertyNames: Set<String>?) -> Bool {
        guard let allPropertyNames, !text.isEmpty else { return false }
        let name = toLowercaseWord(text)
        if allPropertyNames.contains(name) { return true }
        if name.hasSuffix("y") {
            return allPropertyNames.contains(String(name.dropLast()) + "ies")
        }
        return allPropertyNames.contains(name + "s") || allPropertyNames.contains(name + "es")
    }

    // MARK: - Words

    /// The importer's camel-case words (`camel_case::WordIterator`): a run
    /// of capitals is one word (an acronym) up to the capital that starts the
    /// next word, a plural `s` after an acronym belongs to it, and `_` is a
    /// word of its own.
    struct Words {
        let bytes: [UInt8]
        /// The start of every word, then the end of the string.
        let boundaries: [Int]

        init(_ string: String) {
            self.bytes = Array(string.utf8)
            var boundaries = [0]
            var position = 0
            while position < bytes.count {
                position = Self.nextPosition(in: bytes, from: position)
                boundaries.append(position)
            }
            self.boundaries = bytes.isEmpty ? [0] : boundaries
        }

        var count: Int {
            boundaries.count - 1
        }

        var length: Int {
            bytes.count
        }

        func start(of index: Int) -> Int {
            boundaries[index]
        }

        func end(of index: Int) -> Int {
            boundaries[index + 1]
        }

        func word(_ index: Int) -> String {
            slice(from: boundaries[index], to: boundaries[index + 1])
        }

        /// The text before word `index`.
        func prior(_ index: Int) -> String {
            slice(from: 0, to: boundaries[index])
        }

        /// The text from word `index` on.
        func rest(_ index: Int) -> String {
            slice(from: boundaries[index], to: bytes.count)
        }

        func slice(from start: Int, to end: Int) -> String {
            String(decoding: bytes[start ..< end], as: UTF8.self)
        }

        /// The word starting at byte offset `position`.
        func index(startingAt position: Int) -> Int? {
            boundaries.firstIndex(of: position)
        }

        var firstWord: String {
            count > 0 ? word(0) : ""
        }

        var lastWord: String {
            count > 0 ? word(count - 1) : ""
        }

        private static func nextPosition(in bytes: [UInt8], from position: Int) -> Int {
            let count = bytes.count
            var index = position
            if bytes[index] == UInt8(ascii: "_") {
                return index + 1
            }
            while index < count, isUppercase(bytes[index]) {
                index += 1
            }
            if index - position > 1 {
                // An acronym ends before its last capital when a lowercase
                // word follows (`URLLoader`), after it otherwise (`UTF8`),
                // and takes a plural suffix along (`URLs`, but not `Is`).
                var endOfNext = index
                while endOfNext < count, isLowercase(bytes[endOfNext]) {
                    endOfNext += 1
                }
                let followingLowercase = String(decoding: bytes[index ..< endOfNext], as: UTF8.self)
                let lastCapitalAndFollowing = String(decoding: bytes[(index - 1) ..< endOfNext], as: UTF8.self)
                if index == count || (isPluralSuffix(followingLowercase) && lastCapitalAndFollowing != "Is") {
                    return endOfNext
                } else if isLowercase(bytes[index]) {
                    return index - 1
                } else {
                    return index
                }
            }
            while index < count, !isUppercase(bytes[index]), bytes[index] != UInt8(ascii: "_") {
                index += 1
            }
            return index
        }

        private static func isPluralSuffix(_ word: String) -> Bool {
            word == "s" || word == "es" || word == "ies"
        }
    }

    // MARK: - Parts of speech

    enum PartOfSpeech {
        case unknown
        case preposition
        case verb
        case gerund
    }

    /// `getPartOfSpeech`, from the importer's word lists.
    static func partOfSpeech(_ word: String) -> PartOfSpeech {
        let lowercased = word.lowercased()
        if ObjCMemberShape.prepositions.contains(lowercased) { return .preposition }
        if verbs.contains(lowercased) { return .verb }

        // A gerund ends in "ing" after a verb: `sorting`, `making`, `running`.
        if lowercased.hasSuffix("ing"), lowercased.count > 4 {
            let possibleVerb = String(lowercased.dropLast(3))
            if partOfSpeech(possibleVerb) == .verb { return .gerund }
            if !possibleVerb.hasSuffix("e"), partOfSpeech(possibleVerb + "e") == .verb { return .gerund }
            let characters = Array(possibleVerb)
            if characters.count >= 2, characters[characters.count - 1] == characters[characters.count - 2], partOfSpeech(String(possibleVerb.dropLast())) == .verb {
                return .gerund
            }
        }
        // "auto", "re" and "de" prefix verbs.
        for prefix in ["auto", "re", "de"] where lowercased.hasPrefix(prefix) && lowercased.count > prefix.count {
            if partOfSpeech(String(lowercased.dropFirst(prefix.count))) == .verb { return .verb }
        }
        return .unknown
    }

    // MARK: - Small rules

    private static func isVacuousName(_ name: String) -> Bool {
        ["get", "for", "set", "using", "with"].contains { sameWordIgnoringFirstCase(name, $0) }
    }

    private static func canBeMemberName(_ identifier: String) -> Bool {
        !["init", "Protocol", "self", "Type"].contains(identifier)
    }

    /// An identifier the lexer reads as a keyword.
    private static func isSwiftReservedName(_ name: String) -> Bool {
        swiftKeywords.contains(name)
    }

    private static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init", "inout",
        "internal", "let", "operator", "precedencegroup", "private", "protocol", "public", "rethrows", "static",
        "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue", "default", "defer", "do",
        "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw", "switch", "where", "while",
        "Any", "as", "false", "is", "nil", "self", "Self", "super", "throws", "true", "try", "_",
    ]

    private static func sameWordIgnoringFirstCase(_ word: String, _ other: String) -> Bool {
        guard word.utf8.count == other.utf8.count, let first = word.first, let otherFirst = other.first else { return false }
        return first.lowercased() == otherFirst.lowercased() && word.dropFirst() == other.dropFirst()
    }

    /// `camel_case::toLowercaseWord`: the first letter lowercased, unless
    /// it starts an acronym.
    static func toLowercaseWord(_ string: String) -> String {
        let bytes = Array(string.utf8)
        guard let first = bytes.first, isUppercase(first) else { return string }
        if bytes.count > 1, isUppercase(bytes[1]) { return string }
        return String(decoding: [first + 32] + bytes.dropFirst(), as: UTF8.self)
    }

    /// `camel_case::toLowercaseInitialisms`: a leading acronym lowercased
    /// (`URLForResource` → `urlForResource`, `UTF8String` → `utf8String`).
    static func toLowercaseInitialisms(_ string: String) -> String {
        let bytes = Array(string.utf8)
        guard let first = bytes.first, isUppercase(first) else { return string }
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if index < bytes.count - 1, !isUppercase(bytes[index + 1]) {
                let restWord = Words(String(decoding: bytes[(index + 1)...], as: UTF8.self)).firstWord
                if index == 0 || !isLetter(bytes[index + 1]) || ["s", "es", "ies"].contains(restWord) {
                    result.append(lowercased(bytes[index]))
                    index += 1
                }
                result.append(contentsOf: bytes[index...])
                return String(decoding: result, as: UTF8.self)
            }
            result.append(lowercased(bytes[index]))
            index += 1
        }
        return String(decoding: result, as: UTF8.self)
    }

    // MARK: - ASCII classes, as clang's CharInfo has them

    private static func isUppercase(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")
    }

    private static func isLowercase(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        isUppercase(byte) || isLowercase(byte)
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        isUppercase(byte) ? byte + 32 : byte
    }
}
