import Foundation
import ObjectiveC
import ArgumentParser
import SwiftObjCInterop

/// Step 1 of proposal `objc-imported-declarations`: how often the ported
/// ClangImporter naming (`ObjCImporterNaming`), fed only what the Objective-C
/// runtime keeps, reproduces the Swift names the SDK's own importer gives.
///
/// The SDK side is the symbol graph `swift-symbolgraph-extract` writes for the
/// framework's module: every imported Objective-C member in it carries its
/// Clang USR, which names its container and selector
/// (`c:objc(cs)NSView(im)convertPoint:fromView:`), and its Swift name
/// (`convert(_:from:)`). The runtime side is the framework loaded into this
/// process, read through the runtime's own lists, which send no message and so
/// run no class's `+initialize`.
///
/// Every method is named three ways:
/// - **plain**: from its runtime type encoding, where every object is a bare `@`;
/// - **adopted protocols**: from the extended encoding of a protocol the class
///   adopts that declares the same selector, when there is one — the second
///   source of types the proposal plans (a protocol's own members always have
///   their extended encoding here);
/// - **SDK types**: the plain encoding with each bare `@` replaced by the class
///   or protocol the SDK declares there — the ceiling of what type information
///   can buy.
///
/// A mismatch is tagged with what the SDK says about it: an API notes
/// `SwiftName`, an `NS_SWIFT_NAME` in a header (a text search, so only a hint),
/// a class method the SDK imports as an initializer, a property name the
/// importer shortens.
///
/// A throwaway measurement on a probe branch, not part of the library.
@main
struct ObjCImporterNamingProbe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "objc-importer-naming-probe",
        abstract: "Compares ObjCImporterNaming's names from runtime metadata with the SDK's Swift names."
    )

    @Option(help: "The framework binary to load, such as /System/Library/Frameworks/AppKit.framework/AppKit.")
    var frameworkPath: String

    @Option(name: .customLong("symbol-graph-path"), help: "A symbol graph swift-symbolgraph-extract wrote for the framework's module (repeatable: the module's own and its extension graphs).")
    var symbolGraphPaths: [String]

    @Option(help: "The module's API notes in the SDK (<Module>.apinotes).")
    var apiNotesPath: String?

    @Option(help: "The module's Headers directory in the SDK, searched for NS_SWIFT_NAME.")
    var headersPath: String?

    @Option(help: "Where to write every compared member as tab-separated values.")
    var reportPath: String

    @Option(help: "Unexplained mismatches printed per category.")
    var exampleCount: Int = 12

    func run() throws {
        guard dlopen(frameworkPath, RTLD_NOW) != nil else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown error"
            throw ValidationError("Cannot load \(frameworkPath): \(reason)")
        }
        let symbolGraph = try SDKSymbolGraph(paths: symbolGraphPaths)
        let apiNotes = try apiNotesPath.map { try APINotesSwiftNames(path: $0) } ?? APINotesSwiftNames()
        let headers = try headersPath.map { try HeaderSwiftNames(directoryPath: $0) } ?? HeaderSwiftNames()
        let runtime = RuntimeCatalog()

        var comparisons: [Comparison] = []
        var membersMissingAtRuntime = 0
        for (key, members) in symbolGraph.members.sorted(by: { $0.key.description < $1.key.description }) {
            guard var comparison = Self.compare(key, members, runtime: runtime) else {
                membersMissingAtRuntime += 1
                continue
            }
            comparison.tags = Self.tags(for: comparison, apiNotes: apiNotes, headers: headers)
            comparisons.append(comparison)
        }

        let report = Report(comparisons: comparisons, membersMissingAtRuntime: membersMissingAtRuntime, exampleCount: exampleCount)
        report.printSummary()
        try report.writeTable(to: reportPath)
        print("")
        print("Every compared member: \(reportPath)")
    }

    // MARK: - Comparing one member

    private static func compare(_ key: MemberKey, _ members: [SDKMember], runtime: RuntimeCatalog) -> Comparison? {
        let category = Category(key: key, members: members)
        let sdkNames = members.map(\.title)
        switch key.memberKind {
        case .instanceMethod, .classMethod:
            let isClassMember = key.memberKind == .classMethod
            let encodings: MethodEncodings? = switch key.containerKind {
            case .class: runtime.classMethodEncodings(className: key.containerName, selector: key.memberName, isClassMember: isClassMember)
            case .protocol: runtime.protocolMethodEncodings(protocolName: key.containerName, selector: key.memberName, isClassMember: isClassMember)
            }
            guard let encodings else { return nil }
            let propertyNames = key.containerKind == .class
                ? runtime.allPropertyNames(className: key.containerName, forInstance: !isClassMember)
                : []
            func name(from encoding: String?) -> String? {
                Naming.methodName(selector: key.memberName, isClassMethod: isClassMember, encoding: encoding, contextTypeName: key.containerName, propertyNames: propertyNames)
            }
            let sdkTypesNames = members.compactMap { name(from: Naming.encoding(encodings.plain, typedAs: $0)) }
            return Comparison(
                key: key,
                category: category,
                sdkNames: sdkNames,
                plainEncoding: encodings.plain,
                extendedEncoding: encodings.extended,
                plainName: name(from: encodings.plain),
                adoptedProtocolsName: name(from: encodings.extended ?? encodings.plain),
                sdkTypesName: sdkTypesNames.first(where: sdkNames.contains) ?? sdkTypesNames.first
            )
        case .instanceProperty, .classProperty:
            let isClassMember = key.memberKind == .classProperty
            let attributes: String? = switch key.containerKind {
            case .class: runtime.classPropertyAttributes(className: key.containerName, propertyName: key.memberName, isClassMember: isClassMember)
            case .protocol: runtime.protocolPropertyAttributes(protocolName: key.containerName, propertyName: key.memberName, isClassMember: isClassMember)
            }
            guard let attributes else { return nil }
            let derivedName = Naming.propertyName(key.memberName, attributes: attributes)
            return Comparison(
                key: key,
                category: category,
                sdkNames: sdkNames,
                plainEncoding: attributes,
                extendedEncoding: nil,
                plainName: derivedName,
                adoptedProtocolsName: derivedName,
                sdkTypesName: derivedName
            )
        }
    }

    private static func tags(for comparison: Comparison, apiNotes: APINotesSwiftNames, headers: HeaderSwiftNames) -> [Tag] {
        guard !comparison.matches(comparison.adoptedProtocolsName) else { return [] }
        var tags: [Tag] = []
        if apiNotes.hasSwiftName(for: comparison.key) {
            tags.append(.apiNotesSwiftName)
        }
        if headers.mentionsSwiftName(for: comparison.key) {
            tags.append(.headerSwiftName)
        }
        if comparison.key.memberKind == .classMethod, comparison.category == .initializers {
            tags.append(.factoryInitializer)
        }
        if comparison.category == .properties || comparison.category == .protocolProperties,
           let derivedName = comparison.plainName,
           comparison.sdkNames.contains(where: { derivedName.count > $0.count && derivedName.lowercased().hasPrefix($0.lowercased()) }) {
            tags.append(.propertyNameShortened)
        }
        if comparison.matches(comparison.sdkTypesName) {
            tags.append(.fixedBySDKTypes)
        }
        return tags
    }
}

// MARK: - Members and their keys

/// What a Clang USR says about an imported Objective-C member:
/// `c:objc(cs)NSView(im)convertPoint:fromView:` is the instance method
/// `convertPoint:fromView:` of the class `NSView`.
struct MemberKey: Hashable, CustomStringConvertible {
    enum ContainerKind: String {
        case `class`
        case `protocol`
    }

    enum MemberKind: String {
        case instanceMethod
        case classMethod
        case instanceProperty
        case classProperty
    }

    let containerKind: ContainerKind
    let containerName: String
    let memberKind: MemberKind
    /// A method's selector or a property's name.
    let memberName: String

    init(containerKind: ContainerKind, containerName: String, memberKind: MemberKind, memberName: String) {
        self.containerKind = containerKind
        self.containerName = containerName
        self.memberKind = memberKind
        self.memberName = memberName
    }

    init?(usr: String) {
        let prefix = "c:objc("
        guard usr.hasPrefix(prefix) else { return nil }
        var rest = usr.dropFirst(prefix.count)
        guard let containerKindEnd = rest.firstIndex(of: ")") else { return nil }
        let containerKindCode = rest[..<containerKindEnd]
        rest = rest[rest.index(after: containerKindEnd)...]
        // A USR naming the container alone has no member part.
        guard let memberStart = rest.firstIndex(of: "(") else { return nil }
        let containerName = String(rest[..<memberStart])
        rest = rest[rest.index(after: memberStart)...]
        guard let memberKindEnd = rest.firstIndex(of: ")") else { return nil }
        let memberKindCode = rest[..<memberKindEnd]
        let memberName = String(rest[rest.index(after: memberKindEnd)...])
        guard !containerName.isEmpty, !memberName.isEmpty else { return nil }

        switch containerKindCode {
        case "cs": self.containerKind = .class
        case "pl": self.containerKind = .protocol
        default: return nil
        }
        switch memberKindCode {
        case "im": self.memberKind = .instanceMethod
        case "cm": self.memberKind = .classMethod
        case "py": self.memberKind = .instanceProperty
        case "cpy": self.memberKind = .classProperty
        default: return nil
        }
        self.containerName = containerName
        self.memberName = memberName
    }

    var isMethod: Bool {
        memberKind == .instanceMethod || memberKind == .classMethod
    }

    var description: String {
        let marker = switch memberKind {
        case .instanceMethod: "-"
        case .classMethod: "+"
        case .instanceProperty: "@property"
        case .classProperty: "@property (class)"
        }
        return "\(containerName) \(marker) \(memberName)"
    }
}

/// One Swift declaration the SDK imports a member as. A member can have two —
/// a method with a completion handler is also imported as `async`.
struct SDKMember {
    /// The Swift name: `convert(_:from:)`, `init(frame:)`, `isHidden`.
    let title: String
    /// `swift.method`, `swift.init`, `swift.property`, …
    let kindIdentifier: String
    /// The Objective-C object type behind each Swift parameter, when it is one.
    let parameterTypes: [SDKObjectType?]
    let returnType: SDKObjectType?

    init(symbol: SymbolGraphFile.Symbol) {
        self.title = symbol.names.title
        self.kindIdentifier = symbol.kind.identifier
        let signature = symbol.functionSignature
        self.parameterTypes = (signature?.parameters ?? []).map { parameter in
            SDKObjectType(parameterFragments: parameter.declarationFragments ?? [])
        }
        self.returnType = signature?.returns.flatMap { SDKObjectType(typeFragments: $0) }
    }
}

/// The Objective-C object type a Swift type in the SDK stands for: a class
/// (Foundation's bridged value types by the class they bridge, a typedef by
/// its own name, which is what the importer goes by), or a protocol.
enum SDKObjectType {
    case `class`(String)
    case `protocol`(String)

    /// The Objective-C class each of Foundation's and the standard library's
    /// bridged types imports from.
    private static let bridgedClassNames: [String: String] = [
        "String": "NSString",
        "URL": "NSURL",
        "Data": "NSData",
        "Date": "NSDate",
        "UUID": "NSUUID",
        "IndexSet": "NSIndexSet",
        "IndexPath": "NSIndexPath",
        "Locale": "NSLocale",
        "TimeZone": "NSTimeZone",
        "Calendar": "NSCalendar",
        "CharacterSet": "NSCharacterSet",
        "Notification": "NSNotification",
        "DateComponents": "NSDateComponents",
        "DateInterval": "NSDateInterval",
        "URLComponents": "NSURLComponents",
        "URLRequest": "NSURLRequest",
        "AffineTransform": "NSAffineTransform",
        "PersonNameComponents": "NSPersonNameComponents",
        "Error": "NSError",
        "Set": "NSSet",
    ]

    /// A parameter's fragments: its name, `: `, then its type.
    init?(parameterFragments fragments: [SymbolGraphFile.Fragment]) {
        guard let colonIndex = fragments.firstIndex(where: { $0.kind == "text" && $0.spelling.contains(":") }) else { return nil }
        // Text after the colon in the same fragment (`: [`) belongs to the type.
        let colonFragment = fragments[colonIndex]
        let textAfterColon = colonFragment.spelling.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? ""
        var typeFragments = Array(fragments[(colonIndex + 1)...])
        if !textAfterColon.trimmingCharacters(in: .whitespaces).isEmpty {
            typeFragments.insert(SymbolGraphFile.Fragment(kind: "text", spelling: textAfterColon, preciseIdentifier: nil), at: 0)
        }
        self.init(typeFragments: typeFragments)
    }

    init?(typeFragments fragments: [SymbolGraphFile.Fragment]) {
        let text = fragments.map(\.spelling).joined().trimmingCharacters(in: .whitespaces)
        // `[Element]` and `[Key : Value]` import from NSArray and NSDictionary.
        if text.hasPrefix("[") {
            self = .class(text.contains(" : ") ? "NSDictionary" : "NSArray")
            return
        }
        guard let identifier = fragments.first(where: { $0.kind == "typeIdentifier" }) else { return nil }
        if let precise = identifier.preciseIdentifier {
            if precise.hasPrefix("c:objc(cs)") {
                self = .class(String(precise.dropFirst("c:objc(cs)".count)))
                return
            }
            if precise.hasPrefix("c:objc(pl)") {
                self = .protocol(String(precise.dropFirst("c:objc(pl)".count)))
                return
            }
            if precise.hasPrefix("c:@T@") {
                self = .class(String(precise.dropFirst("c:@T@".count)))
                return
            }
        }
        guard let className = Self.bridgedClassNames[identifier.spelling] else { return nil }
        self = .class(className)
    }

    var encodedType: ObjCEncodedType {
        switch self {
        case .class(let name): .object(className: name, protocolNames: [])
        case .protocol(let name): .object(className: nil, protocolNames: [name])
        }
    }
}

/// The members of one or more symbol graphs that are imported Objective-C
/// members, by what their USR names.
struct SDKSymbolGraph {
    let members: [MemberKey: [SDKMember]]

    init(paths: [String]) throws {
        var members: [MemberKey: [SDKMember]] = [:]
        let decoder = JSONDecoder()
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path) else {
                throw ValidationError("Cannot read the symbol graph \(path)")
            }
            let graph = try decoder.decode(SymbolGraphFile.self, from: data)
            for symbol in graph.symbols {
                guard let key = MemberKey(usr: symbol.identifier.precise) else { continue }
                members[key, default: []].append(SDKMember(symbol: symbol))
            }
        }
        self.members = members
    }
}

/// The parts of a symbol graph file the probe reads.
struct SymbolGraphFile: Decodable {
    struct Symbol: Decodable {
        struct Kind: Decodable {
            let identifier: String
        }

        struct Identifier: Decodable {
            let precise: String
        }

        struct Names: Decodable {
            let title: String
        }

        struct FunctionSignature: Decodable {
            struct Parameter: Decodable {
                let declarationFragments: [Fragment]?
            }

            let parameters: [Parameter]?
            let returns: [Fragment]?
        }

        let kind: Kind
        let identifier: Identifier
        let names: Names
        let functionSignature: FunctionSignature?
    }

    struct Fragment: Decodable {
        let kind: String
        let spelling: String
        let preciseIdentifier: String?
    }

    let symbols: [Symbol]
}

// MARK: - The runtime side

/// A method's type encodings at runtime: the plain one every method list
/// keeps, and an extended one (class names, block signatures) when a protocol
/// record supplies it.
struct MethodEncodings {
    let plain: String
    let extended: String?
}

/// Reads the loaded classes and protocols through the runtime's lists only:
/// `class_copyMethodList` and friends realize a class but send it no message,
/// so no `+initialize` and no `+resolveInstanceMethod:` runs.
final class RuntimeCatalog {
    private typealias ProtocolMethodTypeEncodingFunction = @convention(c) (Protocol, Selector, ObjCBool, ObjCBool) -> UnsafePointer<CChar>?

    /// libobjc's `_protocol_getMethodTypeEncoding`: a protocol method's
    /// extended encoding, searched through the protocols it incorporates.
    private let protocolMethodTypeEncoding: ProtocolMethodTypeEncodingFunction?

    private var methodTables: [ObjectIdentifier: [String: String]] = [:]
    private var propertyTables: [ObjectIdentifier: [String: String]] = [:]
    private var adoptedProtocolLists: [ObjectIdentifier: [Protocol]] = [:]
    private var propertyNameSets: [String: Set<String>] = [:]

    init() {
        // `RTLD_DEFAULT`, which Swift does not import.
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        protocolMethodTypeEncoding = dlsym(defaultHandle, "_protocol_getMethodTypeEncoding").map {
            unsafeBitCast($0, to: ProtocolMethodTypeEncodingFunction.self)
        }
    }

    /// The encodings of the method a message `selector` to the class reaches:
    /// the class's own method lists, then its superclasses', as a send
    /// searches them; the extended encoding comes from a protocol the class or
    /// a superclass adopts that declares the selector.
    func classMethodEncodings(className: String, selector: String, isClassMember: Bool) -> MethodEncodings? {
        guard let runtimeClass = NSClassFromString(className) else { return nil }
        var current: AnyClass? = isClassMember ? object_getClass(runtimeClass) : runtimeClass
        while let owner = current {
            if let plain = methodTable(of: owner)[selector] {
                return MethodEncodings(plain: plain, extended: adoptedProtocolEncoding(of: runtimeClass, selector: selector, isClassMember: isClassMember))
            }
            current = class_getSuperclass(owner)
        }
        return nil
    }

    func protocolMethodEncodings(protocolName: String, selector: String, isClassMember: Bool) -> MethodEncodings? {
        guard let runtimeProtocol = objc_getProtocol(protocolName) else { return nil }
        let selectorValue = NSSelectorFromString(selector)
        for isRequired in [true, false] {
            let description = protocol_getMethodDescription(runtimeProtocol, selectorValue, isRequired, !isClassMember)
            guard description.name != nil, let types = description.types else { continue }
            let extended = protocolMethodTypeEncoding?(runtimeProtocol, selectorValue, ObjCBool(isRequired), ObjCBool(!isClassMember)).map { String(cString: $0) }
            return MethodEncodings(plain: String(cString: types), extended: extended)
        }
        return nil
    }

    func classPropertyAttributes(className: String, propertyName: String, isClassMember: Bool) -> String? {
        guard let runtimeClass = NSClassFromString(className) else { return nil }
        var current: AnyClass? = isClassMember ? object_getClass(runtimeClass) : runtimeClass
        while let owner = current {
            if let attributes = propertyTable(of: owner)[propertyName] {
                return attributes
            }
            current = class_getSuperclass(owner)
        }
        return nil
    }

    func protocolPropertyAttributes(protocolName: String, propertyName: String, isClassMember: Bool) -> String? {
        guard let runtimeProtocol = objc_getProtocol(protocolName) else { return nil }
        for isRequired in [true, false] {
            if let property = protocol_getProperty(runtimeProtocol, propertyName, isRequired, !isClassMember),
               let attributes = property_getAttributes(property) {
                return String(cString: attributes)
            }
        }
        return nil
    }

    /// The names the importer keeps a selector's words from being dropped
    /// for (`NameImporter::getAllPropertyNames`): for instance members, the
    /// class's and its superclasses' instance property names; for both, the
    /// selectors of their argument-less methods that return something.
    func allPropertyNames(className: String, forInstance: Bool) -> Set<String> {
        let cacheKey = className + (forInstance ? " instance" : " class")
        if let names = propertyNameSets[cacheKey] {
            return names
        }
        var names: Set<String> = []
        var current: AnyClass? = NSClassFromString(className)
        while let runtimeClass = current {
            if forInstance {
                names.formUnion(propertyTable(of: runtimeClass).keys)
            }
            let owner: AnyClass? = forInstance ? runtimeClass : object_getClass(runtimeClass)
            if let owner {
                for (selector, encoding) in methodTable(of: owner) where !selector.contains(":") && !encoding.hasPrefix("v") {
                    names.insert(selector)
                }
            }
            current = class_getSuperclass(runtimeClass)
        }
        propertyNameSets[cacheKey] = names
        return names
    }

    private func adoptedProtocolEncoding(of runtimeClass: AnyClass, selector: String, isClassMember: Bool) -> String? {
        guard let protocolMethodTypeEncoding else { return nil }
        let selectorValue = NSSelectorFromString(selector)
        for adoptedProtocol in adoptedProtocols(of: runtimeClass) {
            for isRequired in [true, false] {
                if let encoding = protocolMethodTypeEncoding(adoptedProtocol, selectorValue, ObjCBool(isRequired), ObjCBool(!isClassMember)) {
                    return String(cString: encoding)
                }
            }
        }
        return nil
    }

    /// The protocols the class and its superclasses adopt directly; the
    /// encoding lookup itself searches the ones they incorporate. The lists
    /// the runtime hands out are not freed: there is one per class, and the
    /// process is short-lived.
    private func adoptedProtocols(of runtimeClass: AnyClass) -> [Protocol] {
        let identifier = ObjectIdentifier(runtimeClass)
        if let protocols = adoptedProtocolLists[identifier] {
            return protocols
        }
        var protocols: [Protocol] = []
        var current: AnyClass? = runtimeClass
        while let owner = current {
            var count: UInt32 = 0
            if let list = class_copyProtocolList(owner, &count) {
                for index in 0 ..< Int(count) {
                    protocols.append(list[index])
                }
            }
            current = class_getSuperclass(owner)
        }
        adoptedProtocolLists[identifier] = protocols
        return protocols
    }

    /// The class's own methods — its metaclass's for class methods — by selector.
    private func methodTable(of owner: AnyClass) -> [String: String] {
        let identifier = ObjectIdentifier(owner)
        if let table = methodTables[identifier] {
            return table
        }
        var table: [String: String] = [:]
        var count: UInt32 = 0
        if let list = class_copyMethodList(owner, &count) {
            for index in 0 ..< Int(count) {
                let method = list[index]
                if let encoding = method_getTypeEncoding(method) {
                    table[NSStringFromSelector(method_getName(method))] = String(cString: encoding)
                }
            }
            free(list)
        }
        methodTables[identifier] = table
        return table
    }

    /// The class's own properties — its metaclass's for class properties — by name.
    private func propertyTable(of owner: AnyClass) -> [String: String] {
        let identifier = ObjectIdentifier(owner)
        if let table = propertyTables[identifier] {
            return table
        }
        var table: [String: String] = [:]
        var count: UInt32 = 0
        if let list = class_copyPropertyList(owner, &count) {
            for index in 0 ..< Int(count) {
                let property = list[index]
                if let attributes = property_getAttributes(property) {
                    table[String(cString: property_getName(property))] = String(cString: attributes)
                }
            }
            free(list)
        }
        propertyTables[identifier] = table
        return table
    }
}

// MARK: - Naming

enum Naming {
    /// The name `ObjCImporterNaming` gives the method, spelled as a symbol
    /// graph titles it: `convert(_:from:)`, `init(frame:)`, `subscript(_:)`.
    /// `nil` when the encoding does not parse.
    static func methodName(selector: String, isClassMethod: Bool, encoding: String?, contextTypeName: String, propertyNames: Set<String>) -> String? {
        guard let encoding, let methodType = ObjCTypeEncodingParser.methodType(from: encoding) else { return nil }
        let importedName = ObjCImporterNaming.importedName(
            selector: selector,
            isClassMethod: isClassMethod,
            methodType: methodType,
            contextTypeName: contextTypeName,
            propertyNames: propertyNames,
            // That step undoes a `With` Swift inserts into a selector it
            // derives itself; these selectors were written in Objective-C.
            undoesSwiftInsertedWith: false
        )
        let labels = importedName.argumentLabels.map { ($0.isEmpty ? "_" : $0) + ":" }.joined()
        switch importedName.kind {
        case .method:
            return "\(importedName.baseName)(\(labels))"
        case .initializer:
            return "init(\(labels))"
        case .subscriptGetter, .subscriptSetter:
            return "subscript(\(labels))"
        }
    }

    /// The importer's name for a property, as far as the port goes: a `BOOL`
    /// property with a custom getter goes by the getter (`isHidden`). The
    /// importer also shortens property names, which the port does not do yet.
    static func propertyName(_ name: String, attributes: String) -> String {
        let parts = attributes.split(separator: ",")
        let isBoolean = parts.first == "TB" || parts.first == "Tc"
        guard isBoolean, let getter = parts.first(where: { $0.hasPrefix("G") }) else { return name }
        return String(getter.dropFirst())
    }

    /// `plainEncoding` with every bare `@` the SDK declares as a class or a
    /// protocol replaced by it; `nil` when the encoding does not parse.
    static func encoding(_ plainEncoding: String, typedAs member: SDKMember) -> String? {
        guard let methodType = ObjCTypeEncodingParser.methodType(from: plainEncoding) else { return nil }
        var parameterTypes = methodType.parameterTypes
        // The error convention takes the `NSError **` out of the Swift
        // parameters; the others line up in order.
        var objcParameterIndices = Array(parameterTypes.indices)
        if member.parameterTypes.count < parameterTypes.count,
           let errorIndex = objcParameterIndices.last(where: { isErrorOutParameter(parameterTypes[$0]) }) {
            objcParameterIndices.removeAll { $0 == errorIndex }
        }
        for (swiftIndex, objcIndex) in zip(member.parameterTypes.indices, objcParameterIndices) {
            guard isBareObject(parameterTypes[objcIndex]), let sdkType = member.parameterTypes[swiftIndex] else { continue }
            parameterTypes[objcIndex] = sdkType.encodedType
        }
        var returnType = methodType.returnType
        if isBareObject(returnType), let sdkType = member.returnType {
            returnType = sdkType.encodedType
        }
        return encode(returnType) + "@:" + parameterTypes.map(encode).joined()
    }

    private static func isBareObject(_ type: ObjCEncodedType) -> Bool {
        guard case .object(let className, let protocolNames) = type else { return false }
        return className == nil && protocolNames.isEmpty
    }

    private static func isErrorOutParameter(_ type: ObjCEncodedType) -> Bool {
        if case .pointer(.object, _) = type {
            return true
        }
        return false
    }

    /// An encoding `ObjCTypeEncodingParser` reads back as `type`; field lists
    /// and offsets, which naming never looks at, are left out.
    private static func encode(_ type: ObjCEncodedType) -> String {
        switch type {
        case .void: return "v"
        case .bool: return "B"
        case .character: return "c"
        case .unsignedCharacter: return "C"
        case .short: return "s"
        case .unsignedShort: return "S"
        case .int: return "i"
        case .unsignedInt: return "I"
        case .long: return "l"
        case .unsignedLong: return "L"
        case .longLong: return "q"
        case .unsignedLongLong: return "Q"
        case .float: return "f"
        case .double: return "d"
        case .longDouble: return "D"
        case .characterString: return "*"
        case .selector: return ":"
        case .objectClass: return "#"
        case .object(let className, let protocolNames):
            guard className != nil || !protocolNames.isEmpty else { return "@" }
            return "@\"" + (className ?? "") + protocolNames.map { "<\($0)>" }.joined() + "\""
        case .block(let signature):
            guard let signature else { return "@?" }
            return "@?<" + encode(signature.returnType) + "@?" + signature.parameterTypes.map(encode).joined() + ">"
        case .pointer(let pointee, let isConst):
            return (isConst ? "r" : "") + "^" + encode(pointee)
        case .structure(let name):
            return "{" + (name ?? "?") + "=}"
        case .union(let name):
            return "(" + (name ?? "?") + "=)"
        case .array(let count, let element):
            return "[\(count)" + encode(element) + "]"
        case .bitField(let width):
            return "b\(width)"
        case .unknown:
            return "?"
        }
    }
}

// MARK: - What the SDK says about a mismatch

/// The members an API notes file renames for Swift (`SwiftName`). Only the
/// current names are read: the `SwiftVersions` section keeps older ones.
struct APINotesSwiftNames {
    private let keys: Set<MemberKey>

    init() {
        self.keys = []
    }

    /// A line-by-line reading of the layout the SDK's API notes use: a
    /// container at column 0 under `Classes:` or `Protocols:`, its
    /// `Methods:` / `Properties:` lists at column 2, each entry's fields at
    /// column 4.
    init(path: String) throws {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var keys: Set<MemberKey> = []
        var section = ""
        var containerName: String?
        var listName = ""
        var entryName: String?
        var entryKind: String?
        var entryHasSwiftName = false

        func flushEntry() {
            defer {
                entryName = nil
                entryKind = nil
                entryHasSwiftName = false
            }
            guard entryHasSwiftName, let containerName, let entryName else { return }
            let containerKind: MemberKey.ContainerKind = section == "Protocols" ? .protocol : .class
            let memberKinds: [MemberKey.MemberKind]
            if listName == "Methods" {
                memberKinds = entryKind == "Class" ? [.classMethod] : [.instanceMethod]
            } else if listName == "Properties" {
                // A property entry without a kind applies to both.
                memberKinds = entryKind == "Class" ? [.classProperty] : entryKind == "Instance" ? [.instanceProperty] : [.instanceProperty, .classProperty]
            } else {
                memberKinds = []
            }
            for memberKind in memberKinds {
                keys.insert(MemberKey(containerKind: containerKind, containerName: containerName, memberKind: memberKind, memberName: entryName))
            }
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let indentation = line.prefix(while: { $0 == " " }).count
            let content = line.dropFirst(indentation)
            if indentation == 0, !content.hasPrefix("- ") {
                flushEntry()
                section = content.hasSuffix(":") ? String(content.dropLast()) : String(content)
                containerName = nil
                listName = ""
                continue
            }
            guard section == "Classes" || section == "Protocols" else { continue }
            if indentation == 0, let name = Self.value(of: "- Name:", in: content) {
                flushEntry()
                containerName = name
                listName = ""
            } else if indentation == 2, content == "Methods:" || content == "Properties:" {
                flushEntry()
                listName = String(content.dropLast())
            } else if indentation == 2, listName == "Methods", let selector = Self.value(of: "- Selector:", in: content) {
                flushEntry()
                entryName = selector
            } else if indentation == 2, listName == "Properties", let name = Self.value(of: "- Name:", in: content) {
                flushEntry()
                entryName = name
            } else if indentation == 4, entryName != nil {
                if let kind = Self.value(of: "MethodKind:", in: content) ?? Self.value(of: "PropertyKind:", in: content) {
                    entryKind = kind
                } else if Self.value(of: "SwiftName:", in: content) != nil {
                    entryHasSwiftName = true
                }
            }
        }
        flushEntry()
        self.keys = keys
    }

    func hasSwiftName(for key: MemberKey) -> Bool {
        keys.contains(key)
    }

    private static func value(of field: String, in content: Substring) -> String? {
        guard content.hasPrefix(field) else { return nil }
        let value = content.dropFirst(field.count).trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// The header declarations that carry `NS_SWIFT_NAME`, for a text search: a
/// declaration that mentions a member's selector or name and renames
/// something is a hint, not proof, that it renames that member.
struct HeaderSwiftNames {
    private let declarations: [String]

    init() {
        self.declarations = []
    }

    init(directoryPath: String) throws {
        var declarations: [String] = []
        for fileName in try FileManager.default.contentsOfDirectory(atPath: directoryPath) where fileName.hasSuffix(".h") {
            let filePath = (directoryPath as NSString).appendingPathComponent(fileName)
            // A header that is not UTF-8 is read as Latin-1 rather than skipped.
            guard let text = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? (try? String(contentsOfFile: filePath, encoding: .isoLatin1)) else { continue }
            for declaration in text.split(separator: ";") where declaration.contains("NS_SWIFT_NAME(") {
                declarations.append(String(declaration))
            }
        }
        self.declarations = declarations
    }

    func mentionsSwiftName(for key: MemberKey) -> Bool {
        if key.isMethod, key.memberName.contains(":") {
            let firstPiece = String(key.memberName.prefix(while: { $0 != ":" })) + ":"
            return declarations.contains { $0.contains(firstPiece) }
        }
        return declarations.contains { Self.contains(word: key.memberName, in: $0) }
    }

    private static func contains(word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart ..< text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !isIdentifierCharacter(before), !isIdentifierCharacter(after) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isIdentifierCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }
}

// MARK: - Results

enum Category: String, CaseIterable {
    case instanceMethods = "Instance methods"
    case classMethods = "Class methods"
    case initializers = "Initializers"
    case properties = "Properties"
    case protocolMethods = "Protocol methods"
    case protocolProperties = "Protocol properties"

    init(key: MemberKey, members: [SDKMember]) {
        let isInitializer = members.contains { $0.kindIdentifier == "swift.init" }
        switch (key.containerKind, key.memberKind) {
        case (.class, .instanceMethod): self = isInitializer ? .initializers : .instanceMethods
        case (.class, .classMethod): self = isInitializer ? .initializers : .classMethods
        case (.class, .instanceProperty), (.class, .classProperty): self = .properties
        case (.protocol, .instanceMethod), (.protocol, .classMethod): self = .protocolMethods
        case (.protocol, .instanceProperty), (.protocol, .classProperty): self = .protocolProperties
        }
    }
}

enum Tag: String, CaseIterable {
    case apiNotesSwiftName = "API notes SwiftName"
    case headerSwiftName = "NS_SWIFT_NAME in a header (text search)"
    case factoryInitializer = "Class method the SDK imports as an initializer"
    case propertyNameShortened = "Property name the importer shortens"
    case fixedBySDKTypes = "Right once the SDK's types replace @"
}

struct Comparison {
    let key: MemberKey
    let category: Category
    let sdkNames: [String]
    /// A method's runtime encoding, or a property's attribute string.
    let plainEncoding: String
    let extendedEncoding: String?
    let plainName: String?
    let adoptedProtocolsName: String?
    let sdkTypesName: String?
    var tags: [Tag] = []

    func matches(_ name: String?) -> Bool {
        name.map(sdkNames.contains) ?? false
    }

    /// Whether a name that does not match still has a matching base name,
    /// so only argument labels differ.
    func differsInLabelsOnly(_ name: String?) -> Bool {
        guard let name, !matches(name) else { return false }
        let baseName = name.prefix(while: { $0 != "(" })
        return sdkNames.contains { $0.prefix(while: { $0 != "(" }) == baseName }
    }
}

struct Report {
    let comparisons: [Comparison]
    let membersMissingAtRuntime: Int
    let exampleCount: Int

    func printSummary() {
        print("Compared \(comparisons.count) SDK members found at runtime; \(membersMissingAtRuntime) more have no runtime counterpart (another image, or declared only in a header).")
        print("")
        print(Self.row(["Category", "Compared", "Plain", "+ Adopted protocols", "SDK types (ceiling)"]))
        for category in Category.allCases {
            let rows = comparisons.filter { $0.category == category }
            guard !rows.isEmpty else { continue }
            print(Self.row([
                category.rawValue,
                "\(rows.count)",
                Self.share(rows.count(where: { $0.matches($0.plainName) }), of: rows.count),
                Self.share(rows.count(where: { $0.matches($0.adoptedProtocolsName) }), of: rows.count),
                Self.share(rows.count(where: { $0.matches($0.sdkTypesName) }), of: rows.count),
            ]))
        }
        print(Self.row([
            "All",
            "\(comparisons.count)",
            Self.share(comparisons.count(where: { $0.matches($0.plainName) }), of: comparisons.count),
            Self.share(comparisons.count(where: { $0.matches($0.adoptedProtocolsName) }), of: comparisons.count),
            Self.share(comparisons.count(where: { $0.matches($0.sdkTypesName) }), of: comparisons.count),
        ]))

        let mismatches = comparisons.filter { !$0.matches($0.adoptedProtocolsName) }
        print("")
        print("\(mismatches.count) mismatches after adopted protocols (\(mismatches.count(where: { $0.differsInLabelsOnly($0.adoptedProtocolsName) })) differ in labels only). What the SDK says about them — a member can carry several:")
        for tag in Tag.allCases {
            print("  \(Self.padded(tag.rawValue, to: 52)) \(mismatches.count(where: { $0.tags.contains(tag) }))")
        }
        let unexplained = mismatches.filter { $0.tags.isEmpty }
        print("  \(Self.padded("None of the above", to: 52)) \(unexplained.count)")

        print("")
        print("Examples of the unexplained, per category (SDK name ← derived name, selector, encoding):")
        for category in Category.allCases {
            let rows = unexplained.filter { $0.category == category }
            guard !rows.isEmpty else { continue }
            print("  \(category.rawValue) (\(rows.count)):")
            for comparison in rows.prefix(exampleCount) {
                let derivedName = comparison.adoptedProtocolsName ?? "<encoding did not parse>"
                print("    \(comparison.sdkNames.joined(separator: " | ")) ← \(derivedName)    \(comparison.key)    \(comparison.extendedEncoding ?? comparison.plainEncoding)")
            }
        }
    }

    func writeTable(to path: String) throws {
        var lines = [[
            "category", "container kind", "container", "member kind", "member", "plain encoding", "extended encoding",
            "SDK names", "plain", "adopted protocols", "SDK types", "plain matches", "adopted protocols match", "SDK types match", "tags",
        ].joined(separator: "\t")]
        for comparison in comparisons {
            let fields: [String] = [
                comparison.category.rawValue,
                comparison.key.containerKind.rawValue,
                comparison.key.containerName,
                comparison.key.memberKind.rawValue,
                comparison.key.memberName,
                comparison.plainEncoding,
                comparison.extendedEncoding ?? "",
                comparison.sdkNames.joined(separator: " | "),
                comparison.plainName ?? "",
                comparison.adoptedProtocolsName ?? "",
                comparison.sdkTypesName ?? "",
                "\(comparison.matches(comparison.plainName))",
                "\(comparison.matches(comparison.adoptedProtocolsName))",
                "\(comparison.matches(comparison.sdkTypesName))",
                comparison.tags.map(\.rawValue).joined(separator: "; "),
            ]
            lines.append(fields.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t"))
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func share(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "-" }
        return "\(count) (" + String(format: "%.1f", Double(count) * 100 / Double(total)) + " %)"
    }

    private static func row(_ cells: [String]) -> String {
        let widths = [22, 10, 18, 22, 22]
        return zip(cells, widths).map { padded($0, to: $1) }.joined(separator: " ")
    }

    private static func padded(_ text: String, to width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
