import Foundation
import CrossReferenceAnalysis

/// What `refs` looks for.
public enum CrossReferenceSubject: Sendable, Hashable {
    /// Every send of the selector, `super` sends included.
    case selector(String)
    /// A symbol, with its leading underscore: a C function, a Swift mangled
    /// name, `_OBJC_CLASS_$_<class>` (the class) or
    /// `_OBJC_IVAR_$_<class>.<variable>` (the instance variable). A function
    /// none of the analyzed images defines is looked for as the imported
    /// symbol it is.
    case symbol(String)
    /// An Objective-C class by its runtime name: `NSWindow`,
    /// `_TtC7SwiftUI20FilePresenterWrapper`.
    case objectiveCClass(String)
    /// The function holding the unslid `address`, in the image `imageName`
    /// names — needed only when several of a set of standalone files hold a
    /// function there.
    case function(address: UInt64, imageName: String?)
    /// Loads of the instance variable's offset variable.
    case instanceVariable(className: String, name: String)
    /// A C string or constant `CFString` literal with these characters.
    case string(String)
    /// A Swift struct, enum or class by its mangling — `7SwiftUI4TextV` — or
    /// by a `$s…Mn`, `$s…Ma` or `$s…N` symbol of it (its descriptor, its
    /// metadata accessor, its metadata), defined in the image `imageName`
    /// names, or in whichever image exports its descriptor. A Swift class is
    /// also referenced as the Objective-C class it is.
    case swiftType(String, imageName: String?)
}

/// Which way `refs` follows a function.
public enum CrossReferenceDirection: Sendable, Hashable {
    /// What references the subject.
    case callers
    /// What the subject function references, in instruction order.
    case callees
}

public enum CrossReferenceOutputFormat: Sendable, Hashable {
    /// One reference, or one address, a line.
    case text
    /// One JSON document, whose addresses are hexadecimal strings.
    case json
}

/// `swift-section refs`: the code that references a selector, a symbol, a
/// class, a function, an instance variable, a string or a Swift type — or,
/// for a function, what it references — across a dyld shared cache or a set
/// of files.
///
/// The images that can reference the subject are found first, from their
/// symbol tables, selector references and linkage; only those are scanned,
/// concurrently.
public struct ReferencesRequest: Sendable, Equatable {
    public var input: CrossReferenceInput
    public var subject: CrossReferenceSubject
    public var direction: CrossReferenceDirection
    /// The images to look in, by path or file name; empty for every image.
    /// The subject itself is found in any image.
    public var imageNames: [String]
    /// At most this many references are reported, the first in image and
    /// address order; ``ReferencesResult/isTruncated`` says whether there
    /// were more.
    public var limit: Int?
    public var format: CrossReferenceOutputFormat

    public init(
        input: CrossReferenceInput,
        subject: CrossReferenceSubject,
        direction: CrossReferenceDirection = .callers,
        imageNames: [String] = [],
        limit: Int? = nil,
        format: CrossReferenceOutputFormat = .text
    ) {
        self.input = input
        self.subject = subject
        self.direction = direction
        self.imageNames = imageNames
        self.limit = limit
        self.format = format
    }

    /// Finds the references, delivers them, and returns them.
    @discardableResult
    public func run(output: some SwiftSectionOutput) async throws -> ReferencesResult {
        let analyzer = try input.makeAnalyzer()
        let scope = try analyzer.imageIndices(named: imageNames)
        let query = try ResolvedQuery(subject: subject, direction: direction, input: input, scope: scope, analyzer: analyzer)

        var references: [CodeReference]
        let scannedImageCount: Int
        switch query.search {
        case .callees(let function):
            references = analyzer.references(madeBy: function)
            scannedImageCount = 1
        case .callers(let keys, let candidates):
            references = await Self.references(to: keys, inImagesAt: candidates, analyzer: analyzer).filter(query.acceptsReference)
            scannedImageCount = candidates.count
        case .swiftTypes(let identities, let candidates):
            references = await Self.references(toSwiftTypes: identities, inImagesAt: candidates, analyzer: analyzer)
            scannedImageCount = candidates.count
        }
        let referenceCount = references.count
        let referencingImageCount = Set(references.map(\.function.imageIndex)).count
        let isTruncated = limit.map { referenceCount > $0 } ?? false
        if let limit, isTruncated { references = Array(references.prefix(limit)) }

        let naming = CrossReferenceTargetNaming(analyzer: analyzer)
        naming.prepareFunctions(at: references.map(\.function) + references.compactMap { reference in
            if case .function(let location) = reference.target { location } else { nil }
        })
        let rows = references.map { reference in
            ReferencesResult.Row(
                reference: reference,
                imagePath: analyzer.imagePaths[reference.function.imageIndex],
                functionName: naming.function(at: reference.function)?.name?.spelling
            )
        }
        let result = ReferencesResult(rows: rows, scannedImageCount: scannedImageCount, isTruncated: isTruncated)

        switch format {
        case .text:
            for row in rows {
                output.write(.text(Self.text(of: row, naming: naming)))
            }
        case .json:
            output.write(.data(try Self.document(of: result, query: query, input: input, analyzer: analyzer, naming: naming).encoded()))
        }
        let truncation = isTruncated ? ", the first \(rows.count) of \(referenceCount) reported" : ""
        output.reportNote(
            "\(Self.counted(referenceCount, "reference")) in \(Self.counted(referencingImageCount, "image")), "
                + "\(scannedImageCount) of \(Self.counted(analyzer.imageCount, "image")) scanned\(truncation)"
        )
        return result
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: - Scanning

    /// One serial queue for every request: work waited on synchronously
    /// goes to a serial queue, whose target always has a thread to give, and
    /// `concurrentPerform` started there still spreads over every core.
    private static let scanQueue = DispatchQueue(label: "com.machoswiftsection.swiftsectionkit.cross-references")

    /// The references to `keys` in each candidate image, concurrently, in
    /// candidate order.
    private static func references(to keys: Set<CodeReferenceTable.Key>, inImagesAt candidates: [Int], analyzer: CrossReferenceAnalyzer) async -> [CodeReference] {
        await withCheckedContinuation { continuation in
            scanQueue.async {
                let results = ImageResults(count: candidates.count)
                DispatchQueue.concurrentPerform(iterations: candidates.count) { position in
                    results.store(analyzer.references(to: keys, inImageAt: candidates[position]), at: position)
                }
                continuation.resume(returning: results.joined())
            }
        }
    }

    /// The references to any of `identities` in each candidate image,
    /// concurrently, in candidate order. A type defined by two variants of a
    /// framework has an identity each; a reference matching both is listed
    /// once.
    private static func references(toSwiftTypes identities: [SwiftTypeIdentity], inImagesAt candidates: [Int], analyzer: CrossReferenceAnalyzer) async -> [CodeReference] {
        await withCheckedContinuation { continuation in
            scanQueue.async {
                let results = ImageResults(count: candidates.count)
                DispatchQueue.concurrentPerform(iterations: candidates.count) { position in
                    var seen = Set<CodeReference>()
                    var references: [CodeReference] = []
                    for identity in identities {
                        for reference in analyzer.references(toSwiftType: identity, inImageAt: candidates[position]) where seen.insert(reference).inserted {
                            references.append(reference)
                        }
                    }
                    if identities.count > 1 {
                        references.sort { ($0.instructionAddress, $0.function.address) < ($1.instructionAddress, $1.function.address) }
                    }
                    results.store(references, at: position)
                }
                continuation.resume(returning: results.joined())
            }
        }
    }

    /// One slot an image, each written by one iteration alone.
    private final class ImageResults: @unchecked Sendable {
        private var slots: [[CodeReference]]
        private let lock = NSLock()

        init(count: Int) {
            slots = Array(repeating: [], count: count)
        }

        func store(_ references: [CodeReference], at position: Int) {
            lock.withLock { slots[position] = references }
        }

        func joined() -> [CodeReference] {
            lock.withLock { slots.flatMap(\.self) }
        }
    }

    // MARK: - Output

    private static func text(of row: ReferencesResult.Row, naming: CrossReferenceTargetNaming) -> String {
        let reference = row.reference
        let functionText = naming.functionText(at: reference.function, address: reference.instructionAddress)
        return [
            CrossReferenceFormatting.hexadecimal(reference.instructionAddress),
            CrossReferenceFormatting.imageName(ofPath: row.imagePath),
            functionText,
            CrossReferenceFormatting.name(of: reference.kind) + (reference.isRuntimeHelperCall ? " (runtime helper)" : ""),
            CrossReferenceFormatting.name(of: reference.route),
            naming.text(reference.target),
        ].joined(separator: "  ")
    }

    private static func document(
        of result: ReferencesResult,
        query: ResolvedQuery,
        input: CrossReferenceInput,
        analyzer: CrossReferenceAnalyzer,
        naming: CrossReferenceTargetNaming
    ) -> CrossReferenceJSONValue {
        var inputMembers = input.jsonDescription
        inputMembers["imageCount"] = .integer(analyzer.imageCount)
        return .object([
            "query": .object(query.jsonDescription),
            "input": .object(inputMembers),
            "scannedImageCount": .integer(result.scannedImageCount),
            "isTruncated": .bool(result.isTruncated),
            "references": .array(result.rows.map { row in
                .object([
                    "image": .string(row.imagePath),
                    "function": .object(["address": .address(row.reference.function.address), "name": .optionalString(row.functionName)]),
                    "site": .address(row.reference.instructionAddress),
                    "kind": .string(CrossReferenceFormatting.name(of: row.reference.kind)),
                    "route": .string(CrossReferenceFormatting.name(of: row.reference.route)),
                    "target": naming.json(row.reference.target),
                    "isRuntimeHelperCall": .bool(row.reference.isRuntimeHelperCall),
                ])
            }),
        ])
    }
}

/// What `refs` found.
public struct ReferencesResult: Sendable {
    public struct Row: Sendable, Hashable {
        public let reference: CodeReference
        /// The path of the image the referencing function lies in.
        public let imagePath: String
        /// The referencing function's name, when anything names it.
        public let functionName: String?
    }

    /// In image order, then in the order of the functions and their
    /// instructions.
    public let rows: [Row]
    /// How many images were scanned: the ones that could reference the
    /// subject.
    public let scannedImageCount: Int
    /// Whether ``ReferencesRequest/limit`` left references out.
    public let isTruncated: Bool
}

// MARK: - Resolving the subject

/// A subject, resolved against the analyzed images: what to scan for and
/// where, or the function whose callees are listed.
private struct ResolvedQuery {
    enum Search {
        case callers(keys: Set<CodeReferenceTable.Key>, candidates: [Int])
        case callees(CodeFunction)
        /// A Swift type's references, matched by the analyzer's type query
        /// rather than by table keys: they are filed by descriptor, and a
        /// mangled name may spell the type.
        case swiftTypes([SwiftTypeIdentity], candidates: [Int])
    }

    var search: Search
    /// Drops what the keys match beyond the subject: another class of the
    /// same name.
    var acceptsReference: (CodeReference) -> Bool = { _ in true }
    var jsonDescription: [String: CrossReferenceJSONValue]

    init(subject: CrossReferenceSubject, direction: CrossReferenceDirection, input: CrossReferenceInput, scope: [Int], analyzer: CrossReferenceAnalyzer) throws {
        if direction == .callees {
            guard case .function(let address, let imageName) = subject else { throw CrossReferenceRequestError.calleesRequireFunction }
            let function = try Self.function(at: address, imageName: imageName, input: input, analyzer: analyzer)
            search = .callees(function)
            jsonDescription = ["function": Self.functionJSON(function, analyzer: analyzer), "direction": .string("callees")]
            return
        }
        let allImages = 0 ..< analyzer.imageCount
        switch subject {
        case .selector(let selector):
            search = .callers(keys: [.selector(selector)], candidates: analyzer.imageIndices(referencingSelector: selector, among: scope))
            jsonDescription = ["selector": .string(selector)]
        case .symbol(let name):
            if let className = Self.suffix(of: name, after: "_OBJC_CLASS_$_") ?? Self.suffix(of: name, after: "_OBJC_METACLASS_$_") {
                self = try Self.objectiveCClass(className, scope: scope, analyzer: analyzer)
                jsonDescription = ["symbol": .string(name)]
                return
            }
            if let qualifiedName = Self.suffix(of: name, after: "_OBJC_IVAR_$_"), let dot = qualifiedName.lastIndex(of: ".") {
                self = try Self.instanceVariable(
                    className: String(qualifiedName[..<dot]),
                    name: String(qualifiedName[qualifiedName.index(after: dot)...]),
                    scope: scope,
                    analyzer: analyzer
                )
                jsonDescription = ["symbol": .string(name)]
                return
            }
            let locations = analyzer.locations(ofSymbolNamed: name, among: allImages)
            var keys: Set<CodeReferenceTable.Key> = [.importedSymbol(name)]
            var candidates = Set(analyzer.imageIndices(importing: name, among: scope))
            var functions: [CodeFunction] = []
            for location in locations {
                guard let function = analyzer.function(containing: location), function.location == location else { continue }
                functions.append(function)
                keys.insert(.function(location))
                let names = Self.symbolNames(of: function, adding: name)
                keys.formUnion(names.map { .importedSymbol($0) })
                candidates.formUnion(analyzer.imageIndices(callingFunctionAt: location, symbolNames: names, among: scope))
            }
            if functions.isEmpty, !locations.isEmpty { throw CrossReferenceRequestError.symbolIsNoFunction(name: name) }
            if locations.isEmpty, candidates.isEmpty { throw CrossReferenceRequestError.symbolNotFound(name: name) }
            search = .callers(keys: keys, candidates: candidates.sorted())
            jsonDescription = ["symbol": .string(name)]
        case .objectiveCClass(let name):
            self = try Self.objectiveCClass(name, scope: scope, analyzer: analyzer)
        case .function(let address, let imageName):
            let function = try Self.function(at: address, imageName: imageName, input: input, analyzer: analyzer)
            let names = Self.symbolNames(of: function, adding: nil)
            var keys: Set<CodeReferenceTable.Key> = [.function(function.location)]
            keys.formUnion(names.map { .importedSymbol($0) })
            search = .callers(keys: keys, candidates: analyzer.imageIndices(callingFunctionAt: function.location, symbolNames: names, among: scope))
            jsonDescription = ["function": Self.functionJSON(function, analyzer: analyzer), "direction": .string("callers")]
        case .instanceVariable(let className, let name):
            self = try Self.instanceVariable(className: className, name: name, scope: scope, analyzer: analyzer)
        case .string(let characters):
            // Any image can hold the literal; none is ruled out.
            search = .callers(keys: [.cString(characters), .constantString(characters)], candidates: scope)
            jsonDescription = ["string": .string(characters)]
        case .swiftType(let spelling, let imageName):
            let mangling = Self.swiftTypeMangling(spelledAs: spelling)
            let identities = try Self.swiftTypeIdentities(mangling: mangling, imageName: imageName, input: input, analyzer: analyzer)
            var candidates = Set<Int>()
            for identity in identities {
                candidates.formUnion(analyzer.imageIndices(referencingSwiftType: identity, among: scope))
            }
            search = .swiftTypes(identities, candidates: candidates.sorted())
            jsonDescription = ["swiftType": .string(mangling)]
        }
    }

    /// The nominal mangling `spelling` names: itself, or — for a symbol,
    /// `$s` first and `_` before it optionally — the symbol without its
    /// prefix and its descriptor (`Mn`), accessor (`Ma`) or metadata (`N`)
    /// suffix. A mangling on its own ends with its kind (`V`, `C`, `O`, `a`
    /// for a C type), never with one of those suffixes.
    static func swiftTypeMangling(spelledAs spelling: String) -> String {
        var mangling = Substring(spelling)
        if mangling.hasPrefix("_") { mangling = mangling.dropFirst() }
        guard mangling.hasPrefix("$s") else { return spelling }
        mangling = mangling.dropFirst(2)
        for suffix in ["Mn", "Ma", "N"] where mangling.hasSuffix(suffix) && mangling.count > suffix.count {
            return String(mangling.dropLast(suffix.count))
        }
        return String(mangling)
    }

    /// The Swift types with `mangling`: in the image `imageName` names, or
    /// wherever a `$s…Mn` symbol puts the descriptor, or — for a set of
    /// files, which are few — in whichever file defines one.
    private static func swiftTypeIdentities(mangling: String, imageName: String?, input: CrossReferenceInput, analyzer: CrossReferenceAnalyzer) throws -> [SwiftTypeIdentity] {
        let allImages = 0 ..< analyzer.imageCount
        let descriptors: [CodeLocation]
        if let imageName {
            descriptors = try analyzer.imageIndices(named: [imageName]).flatMap { analyzer.swiftTypeDescriptorLocations(withKey: mangling, inImageAt: $0) }
        } else {
            let exported = analyzer.locations(ofSymbolNamed: "_$s" + mangling + "Mn", among: allImages)
            if !exported.isEmpty {
                descriptors = exported
            } else if case .files = input {
                descriptors = allImages.flatMap { analyzer.swiftTypeDescriptorLocations(withKey: mangling, inImageAt: $0) }
            } else {
                throw CrossReferenceRequestError.swiftTypeNeedsImage(mangling: mangling)
            }
        }
        var identities: [SwiftTypeIdentity] = []
        for descriptor in descriptors {
            guard let identity = analyzer.swiftTypeIdentity(ofDescriptorAt: descriptor), !identities.contains(identity) else { continue }
            identities.append(identity)
        }
        guard !identities.isEmpty else { throw CrossReferenceRequestError.swiftTypeNotFound(mangling: mangling) }
        return identities
    }

    private init(search: Search, acceptsReference: @escaping (CodeReference) -> Bool, jsonDescription: [String: CrossReferenceJSONValue]) {
        self.search = search
        self.acceptsReference = acceptsReference
        self.jsonDescription = jsonDescription
    }

    private static func suffix(of name: String, after prefix: String) -> String? {
        name.hasPrefix(prefix) && name.count > prefix.count ? String(name.dropFirst(prefix.count)) : nil
    }

    /// Every name the function's image gives it, `name` first when given.
    private static func symbolNames(of function: CodeFunction, adding name: String?) -> [String] {
        var names: [String] = name.map { [$0] } ?? []
        if case .symbol(let symbol)? = function.name, !names.contains(symbol) { names.append(symbol) }
        for folded in function.foldedSymbolNames where !names.contains(folded) {
            names.append(folded)
        }
        return names
    }

    /// Where the class is defined: by its `_OBJC_CLASS_$_` symbol, or — for
    /// a class no symbol names, as most private classes in a shared cache —
    /// by the images' class lists.
    private static func classLocations(named name: String, analyzer: CrossReferenceAnalyzer) -> [CodeLocation] {
        let symbolLocations = analyzer.locations(ofSymbolNamed: "_OBJC_CLASS_$_" + name, among: 0 ..< analyzer.imageCount)
        if !symbolLocations.isEmpty { return symbolLocations }
        return (0 ..< analyzer.imageCount).flatMap { analyzer.objectiveCClassLocations(named: name, inImageAt: $0) }
    }

    private static func objectiveCClass(_ name: String, scope: [Int], analyzer: CrossReferenceAnalyzer) throws -> ResolvedQuery {
        let locations = classLocations(named: name, analyzer: analyzer)
        let importedNames = ["_OBJC_CLASS_$_" + name, "_OBJC_METACLASS_$_" + name]
        var candidates = Set(analyzer.imageIndices(importingAnyOf: importedNames, among: scope))
        for location in locations {
            candidates.formUnion(analyzer.imageIndices(referencingObjectiveCClassAt: location, among: scope))
        }
        if locations.isEmpty, candidates.isEmpty { throw CrossReferenceRequestError.classNotFound(name: name) }
        var keys: Set<CodeReferenceTable.Key> = [.objectiveCClass(name)]
        keys.formUnion(importedNames.map { .importedSymbol($0) })
        let classLocations = Set(locations)
        return ResolvedQuery(
            search: .callers(keys: keys, candidates: candidates.sorted()),
            acceptsReference: { reference in
                guard case .objectiveCClass(_, let location) = reference.target else { return true }
                return classLocations.isEmpty || classLocations.contains(location)
            },
            jsonDescription: ["class": .string(name)]
        )
    }

    private static func instanceVariable(className: String, name: String, scope: [Int], analyzer: CrossReferenceAnalyzer) throws -> ResolvedQuery {
        let definingImages = Set(classLocations(named: className, analyzer: analyzer).map(\.imageIndex))
        var candidates = Set(scope).intersection(definingImages)
        candidates.formUnion(analyzer.imageIndices(importing: "_OBJC_IVAR_$_\(className).\(name)", among: scope))
        if definingImages.isEmpty, candidates.isEmpty { throw CrossReferenceRequestError.classNotFound(name: className) }
        return ResolvedQuery(
            search: .callers(keys: [.instanceVariable(className: className, name: name)], candidates: candidates.sorted()),
            acceptsReference: { _ in true },
            jsonDescription: ["instanceVariable": .object(["class": .string(className), "name": .string(name)])]
        )
    }

    /// The function holding `address`. A shared cache's images share one
    /// address space; a set of files each have their own, so every file
    /// holding a function there is a candidate, and two are ambiguous.
    private static func function(at address: UInt64, imageName: String?, input: CrossReferenceInput, analyzer: CrossReferenceAnalyzer) throws -> CodeFunction {
        let imageIndices: [Int?]
        if let imageName {
            imageIndices = try analyzer.imageIndices(named: [imageName])
        } else if case .files = input {
            imageIndices = Array(0 ..< analyzer.imageCount)
        } else {
            imageIndices = [nil]
        }
        var functions: [CodeFunction] = []
        for imageIndex in imageIndices {
            guard case .function(let start, _, _) = analyzer.symbolication(of: address, inImageAt: imageIndex).meaning,
                  let function = analyzer.function(containing: start)
            else { continue }
            functions.append(function)
        }
        guard let function = functions.first else { throw CrossReferenceRequestError.noFunction(address: address) }
        guard functions.count == 1 else {
            throw CrossReferenceRequestError.ambiguousFunction(address: address, imagePaths: functions.map { analyzer.imagePaths[$0.location.imageIndex] })
        }
        return function
    }

    private static func functionJSON(_ function: CodeFunction, analyzer: CrossReferenceAnalyzer) -> CrossReferenceJSONValue {
        .object([
            "image": .string(analyzer.imagePaths[function.location.imageIndex]),
            "address": .address(function.location.address),
            "name": .optionalString(function.name?.spelling),
        ])
    }
}
