import Foundation
import MachOKit
import MachOKitExtensions
import Demangling
import FoundationToolbox
import MachOReading
import MachOSwiftSection
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches
@_spi(Internals) import MachOSymbols

/// Per-image index of the classes implemented through `@objc @implementation`
/// (evolution proposal `objc-implementation-class-recognition`), keyed by
/// bare ObjC class name.
///
/// Recognition joins the two sides the compiler leaves such a class on. The
/// ObjC side is the precondition: the class must be DEFINED by this image's
/// `__objc_classlist` with the Swift bit of its class data pointer clear — a
/// plain Swift extension of an imported class produces a category and never
/// satisfies it, and an ordinary Swift class with ObjC ancestry has the bit
/// set. Past that gate the Swift side decides the tier
/// (``ObjCImplementationClassFacts/Evidence``): an EXPORTED metadata accessor
/// `$sSo<Name>CMa` (the public unique accessor only the implementing module
/// emits — a hidden non-unique one appears in any image that needs an
/// imported class's metadata) or `…vpWvd` field-offset globals for the
/// class's extension members make it definitive; with both stripped away, an ivar
/// whose type encoding is `?` or empty — encodings clang never writes — makes
/// it an inference, rendered as such. A clang-compiled class with a Swift
/// extension in the same image passes the gate but hits none of the tiers
/// (its own IMPs are `-[C sel]`, its ivar encodings are complete).
///
/// Built once per image, lazily, through the shared-cache machinery; the
/// declaration indexer evicts it with the other per-image caches. This module
/// sits below the event layer, so anything skipped is reported through `#log`
/// and kept on ``skippedClasses(in:)`` for the indexer to surface as events.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "ObjCImplementationClassIndex")
package final class ObjCImplementationClassIndex: SharedCache<ObjCImplementationClassIndex.Storage>, @unchecked Sendable {
    package static let shared = ObjCImplementationClassIndex()

    private override init() {
        super.init()
    }

    package typealias SkippedClass = ObjCImplementationClasses.SkippedClass

    package final class Storage: @unchecked Sendable {
        /// Recognized classes in `__objc_classlist` order.
        let classes: [ObjCImplementationClassFacts]
        let classesByName: [String: ObjCImplementationClassFacts]
        /// Classes whose class data could not be read, so recognition could
        /// not even be attempted.
        let skippedClasses: [SkippedClass]

        init(classes: [ObjCImplementationClassFacts], skippedClasses: [SkippedClass]) {
            self.classes = classes
            var classesByName: [String: ObjCImplementationClassFacts] = [:]
            for facts in classes where classesByName[facts.className] == nil {
                classesByName[facts.className] = facts
            }
            self.classesByName = classesByName
            self.skippedClasses = skippedClasses
        }
    }

    override package func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        if let machOFile = machO as? MachOFile {
            return Self.build(in: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return Self.build(in: machOImage)
        }
        return nil
    }

    // MARK: - Queries

    package func facts(forClassNamed className: String, in machO: some MachORepresentableWithCache) -> ObjCImplementationClassFacts? {
        storage(in: machO)?.classesByName[className]
    }

    /// Every recognized class of the image, in `__objc_classlist` order.
    package func classes(in machO: some MachORepresentableWithCache) -> [ObjCImplementationClassFacts] {
        storage(in: machO)?.classes ?? []
    }

    package func skippedClasses(in machO: some MachORepresentableWithCache) -> [SkippedClass] {
        storage(in: machO)?.skippedClasses ?? []
    }

    /// The bare ObjC class name when `typeNode` (a `.type` node or the nominal
    /// node itself) names a class imported from ObjC — module `__C` — with no
    /// enclosing context, which is the only shape an `@implementation` can
    /// target. Anything else, including a nested type of such a class, is `nil`.
    package static func cImportedClassName(of typeNode: NodeReference) -> String? {
        var node = typeNode
        if node.kind == .type, let firstChild = node.children.first {
            node = firstChild
        }
        return cImportedClassName(ofClassNode: node)
    }

    private static func cImportedClassName(ofClassNode node: NodeReference) -> String? {
        guard node.kind == .class, node.children.count == 2 else { return nil }
        let moduleNode = node.children[0]
        let identifierNode = node.children[1]
        guard moduleNode.kind == .module, moduleNode.text == CImportedModuleNames.objectiveC,
              identifierNode.kind == .identifier, let className = identifierNode.text, !className.isEmpty
        else { return nil }
        return className
    }

    // MARK: - Build

    /// The Swift side of the join, collected once per image.
    private struct SwiftSideEvidence {
        struct FieldOffsetSymbol {
            let symbolName: String
            /// The global's VALUE — the ivar offset it holds — read from the
            /// image; `nil` when the read failed. The join key against the
            /// ObjC ivar list, whose entries point at this very global.
            let fieldOffsetValue: Int?
            let implementingModuleName: String?
            let propertyName: String
            let typeNode: NodeReference
        }

        var metadataAccessorSymbolNameByClassName: [String: String] = [:]
        var fieldOffsetSymbolsByClassName: [String: [FieldOffsetSymbol]] = [:]

        static func collect(in machO: some ObjCImplementationClassReading) -> SwiftSideEvidence {
            var evidence = SwiftSideEvidence()
            let symbolIndexStore = SymbolIndexStore.shared

            // `$sSo<Name>CMa`: global(typeMetadataAccessFunction(type(class(module, identifier)))).
            // Only an EXPORTED accessor counts. An imported ObjC class has
            // `PublicNonUnique` formal linkage, so any image that needs its
            // metadata (an `[X]`, a generic argument) emits a hidden
            // linkonce accessor of its own — SwiftUICore carries one for its
            // clang-implemented `DateFormattingContext`, and a dyld cache
            // keeps local symbols, so that accessor IS in the symbol table.
            // The `@implementation` in the class's own module is what gets
            // the public unique accessor that lands in the export trie.
            for symbol in symbolIndexStore.symbols(of: .typeMetadataAccessFunction, in: machO) {
                guard let accessorNode = symbol.demangledNode.children.first,
                      let typeNode = accessorNode.children.first,
                      let className = cImportedClassName(of: typeNode),
                      evidence.metadataAccessorSymbolNameByClassName[className] == nil,
                      symbolIndexStore.isExported(name: symbol.symbol.name, in: machO) == true
                else { continue }
                evidence.metadataAccessorSymbolNameByClassName[className] = symbol.symbol.name
            }

            // `…vpWvd`: global(fieldOffset(directness, variable(extension(module, class), identifier, type))).
            for symbol in symbolIndexStore.symbols(of: .fieldOffset, in: machO) {
                guard let fieldOffsetNode = symbol.demangledNode.children.first,
                      fieldOffsetNode.children.count == 2
                else { continue }
                let variableNode = fieldOffsetNode.children[1]
                guard variableNode.kind == .variable, variableNode.children.count == 3 else { continue }
                let contextNode = variableNode.children[0]
                let identifierNode = variableNode.children[1]
                let typeNode = variableNode.children[2]
                guard contextNode.kind == .extension, contextNode.children.count >= 2,
                      let className = cImportedClassName(ofClassNode: contextNode.children[1]),
                      identifierNode.kind == .identifier, let propertyName = identifierNode.text
                else { continue }
                let moduleNode = contextNode.children[0]
                let implementingModuleName = moduleNode.kind == .module ? moduleNode.text : nil
                // A direct field offset (`Wvd`) is a word-sized global holding
                // the offset; an indirect one (`Wvi`) holds an offset INTO the
                // metadata's field-offset vector, which an ObjC class has not
                // got — the compiler never emits one for an `@implementation`.
                let directnessNode = fieldOffsetNode.children[0]
                let isDirect = directnessNode.kind == .directness && directnessNode.index == 0
                // The symbol's value is the binary's claim; a negative one is
                // no offset, and the file reader traps converting it to
                // `UInt64` before `try?` can see a failure.
                let fieldOffsetValue: Int? = isDirect && symbol.offset >= 0 ? (try? machO.readElement(offset: symbol.offset) as UInt64).map { Int(truncatingIfNeeded: $0) } : nil
                evidence.fieldOffsetSymbolsByClassName[className, default: []].append(
                    FieldOffsetSymbol(symbolName: symbol.symbol.name, fieldOffsetValue: fieldOffsetValue, implementingModuleName: implementingModuleName, propertyName: propertyName, typeNode: typeNode)
                )
            }
            return evidence
        }
    }

    private static func build<MachO: ObjCImplementationClassReading>(in machO: MachO) -> Storage {
        guard let classObjects = machO.objcImplementationClassObjects() else {
            return Storage(classes: [], skippedClasses: [])
        }
        let swiftSide = SwiftSideEvidence.collect(in: machO)

        var classes: [ObjCImplementationClassFacts] = []
        var skippedClasses: [SkippedClass] = []

        for classObject in classObjects {
            // The gate: an ObjC class object this image defines, with no Swift
            // metadata behind its data pointer.
            guard !classObject.isSwift else { continue }
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject) else {
                skippedClasses.append(SkippedClass(className: "<class object at offset \(classObject.offset)>", reason: "class_ro_t unreadable"))
                #log(.error, "skipped a class object at offset \(classObject.offset, privacy: .public): class_ro_t unreadable")
                continue
            }
            guard !readOnlyData.isMetaClass else { continue }
            guard let className = machO.className(of: readOnlyData), !className.isEmpty else {
                skippedClasses.append(SkippedClass(className: "<class object at offset \(classObject.offset)>", reason: "class name unreadable"))
                #log(.error, "skipped a class object at offset \(classObject.offset, privacy: .public): class name unreadable")
                continue
            }

            let fieldOffsetSymbols = swiftSide.fieldOffsetSymbolsByClassName[className] ?? []
            let metadataAccessorSymbolName = swiftSide.metadataAccessorSymbolNameByClassName[className]
            var fieldOffsetSymbolsByValue: [Int: SwiftSideEvidence.FieldOffsetSymbol] = [:]
            var fieldOffsetSymbolsByPropertyName: [String: SwiftSideEvidence.FieldOffsetSymbol] = [:]
            for fieldOffsetSymbol in fieldOffsetSymbols {
                if let fieldOffsetValue = fieldOffsetSymbol.fieldOffsetValue {
                    fieldOffsetSymbolsByValue[fieldOffsetValue] = fieldOffsetSymbol
                }
                fieldOffsetSymbolsByPropertyName[fieldOffsetSymbol.propertyName] = fieldOffsetSymbol
            }

            let instanceVariables: [ObjCImplementationClassFacts.InstanceVariable] = machO.rawInstanceVariables(of: readOnlyData).map { rawInstanceVariable in
                // The ivar's offset entry points at the very global the `Wvd`
                // symbol names, so the offset VALUE is the join key; the name
                // is only a fallback (observed empty for a header-declared
                // property in an on-the-fly fixture).
                let joined = fieldOffsetSymbolsByValue[rawInstanceVariable.offset]
                    ?? (rawInstanceVariable.name.isEmpty ? nil : fieldOffsetSymbolsByPropertyName[rawInstanceVariable.name])
                return ObjCImplementationClassFacts.InstanceVariable(
                    name: rawInstanceVariable.name,
                    offset: rawInstanceVariable.offset,
                    size: rawInstanceVariable.size,
                    alignment: rawInstanceVariable.alignment,
                    typeEncoding: rawInstanceVariable.typeEncoding,
                    swiftFieldOffsetSymbolName: joined?.symbolName,
                    swiftPropertyName: joined?.propertyName,
                    swiftTypeNode: joined?.typeNode
                )
            }

            // Tiering — decided on the cheap facts (two dictionary probes and
            // the ivar list) BEFORE the method lists are read: most classes in
            // an image are clang classes that fail every tier, and reading
            // their method lists would make the index cost a class-dump.
            var reasons: [ObjCImplementationClassFacts.Evidence.Reason] = []
            if let metadataAccessorSymbolName {
                reasons.append(.metadataAccessorSymbol(name: metadataAccessorSymbolName))
            }
            if !fieldOffsetSymbols.isEmpty {
                reasons.append(.fieldOffsetSymbols(count: fieldOffsetSymbols.count))
            }
            let swiftStyleEncodedCount = instanceVariables.filter(\.hasSwiftStyleTypeEncoding).count
            guard !reasons.isEmpty || swiftStyleEncodedCount > 0 else { continue }

            let instanceMethods = machO.methods(of: readOnlyData).map { Self.method(from: $0, in: machO) }
            let classMethods: [ObjCImplementationClassFacts.Method] = {
                guard let metaClass = machO.metaClass(of: classObject),
                      let metaReadOnlyData = machO.instanceReadOnlyData(of: metaClass)
                else { return [] }
                return machO.methods(of: metaReadOnlyData).map { Self.method(from: $0, in: machO) }
            }()
            // Swift symbols at the class's own IMPs corroborate; they are not
            // consulted as a trigger, so a fully stripped image is judged on
            // the ivar encodings alone.
            let swiftImplementedMethodCount = (instanceMethods + classMethods).filter { !$0.implementationSymbolNames.isEmpty }.count
            if swiftImplementedMethodCount > 0 {
                reasons.append(.swiftSymbolsAtMethodImplementations(count: swiftImplementedMethodCount))
            }
            let evidence: ObjCImplementationClassFacts.Evidence = reasons.isEmpty
                ? .inferred(swiftStyleEncodedInstanceVariableCount: swiftStyleEncodedCount)
                : .definitive(reasons)

            let implementingModuleName = fieldOffsetSymbols.lazy.compactMap(\.implementingModuleName).first

            classes.append(ObjCImplementationClassFacts(
                className: className,
                superclassName: machO.superclassName(of: classObject),
                classObjectOffset: classObject.offset,
                readOnlyDataFlags: readOnlyData.layout.flags,
                instanceStart: Int(readOnlyData.layout.instanceStart),
                instanceSize: Int(readOnlyData.layout.instanceSize),
                evidence: evidence,
                implementingModuleName: implementingModuleName,
                instanceVariables: instanceVariables,
                instanceMethods: instanceMethods,
                classMethods: classMethods,
                properties: machO.properties(of: readOnlyData),
                protocolNames: machO.protocolNames(of: readOnlyData)
            ))
        }

        return Storage(classes: classes, skippedClasses: skippedClasses)
    }

    private static func method(from rawMethod: RawObjCMethod, in machO: some MachORepresentableWithCache) -> ObjCImplementationClassFacts.Method {
        let symbolNames: [String] = rawMethod.implementationOffset.flatMap { machO.symbols(offset: $0) }?.map(\.name).filter(\.isSwiftSymbol) ?? []
        return ObjCImplementationClassFacts.Method(selector: rawMethod.selector, typeEncoding: rawMethod.typeEncoding, implementationOffset: rawMethod.implementationOffset, implementationSymbolNames: symbolNames)
    }
}

/// The public face of ``ObjCImplementationClassIndex`` (whose shared-cache
/// base class is SPI): per-image lookup of `@objc @implementation` classes.
public enum ObjCImplementationClasses {
    public struct SkippedClass: Sendable {
        public let className: String
        public let reason: String
    }

    /// The facts for the ObjC class named `className`, or `nil` when the
    /// image does not implement a class of that name through
    /// `@objc @implementation`.
    public static func facts(forClassNamed className: String, in machO: some MachORepresentableWithCache) -> ObjCImplementationClassFacts? {
        ObjCImplementationClassIndex.shared.facts(forClassNamed: className, in: machO)
    }

    /// Every recognized class of the image, in `__objc_classlist` order.
    public static func all(in machO: some MachORepresentableWithCache) -> [ObjCImplementationClassFacts] {
        ObjCImplementationClassIndex.shared.classes(in: machO)
    }

    /// Classes whose class data could not be read at all.
    public static func skipped(in machO: some MachORepresentableWithCache) -> [SkippedClass] {
        ObjCImplementationClassIndex.shared.skippedClasses(in: machO)
    }

    /// Drops the image's index; the declaration indexer calls this alongside
    /// the other per-image cache evictions.
    public static func removeCache(for machO: some MachORepresentableWithCache) {
        ObjCImplementationClassIndex.shared.remove(for: machO)
    }

    /// The bare ObjC class name when `typeNode` names a class imported from
    /// ObjC (module `__C`) with no enclosing context — the only shape an
    /// `@implementation` can target.
    public static func cImportedClassName(of typeNode: NodeReference) -> String? {
        ObjCImplementationClassIndex.cImportedClassName(of: typeNode)
    }
}

// MARK: - Reader split

/// The ivar list entry before the Swift join.
struct RawObjCInstanceVariable {
    let name: String
    let offset: Int
    let size: Int
    let alignment: Int
    let typeEncoding: String
}

struct RawObjCMethod {
    let selector: String
    let typeEncoding: String
    let implementationOffset: Int?
}

/// The ObjC reads the index needs, spelled once per reader because the ObjC
/// section reader's accessors are concrete `MachOFile` / `MachOImage`
/// overloads (the same split `SwiftLayout.ObjCClassIndex` carries).
protocol ObjCImplementationClassReading: MachORepresentableWithCache, Readable {
    func objcImplementationClassObjects() -> [ObjCClass64]?
    func instanceReadOnlyData(of classObject: ObjCClass64) -> ObjCClassROData64?
    func className(of readOnlyData: ObjCClassROData64) -> String?
    func superclassName(of classObject: ObjCClass64) -> String?
    /// Where the superclass pointer leads (`ObjCClassMethodIndex`'s ancestor
    /// walk): another class object — possibly in another image of the same
    /// cache or process — the root, or a bind this reader cannot follow.
    func superclassLocation(of classObject: ObjCClass64) -> ObjCSuperclassLocation
    func metaClass(of classObject: ObjCClass64) -> ObjCClass64?
    func rawInstanceVariables(of readOnlyData: ObjCClassROData64) -> [RawObjCInstanceVariable]
    func methods(of readOnlyData: ObjCClassROData64) -> [RawObjCMethod]
    func properties(of readOnlyData: ObjCClassROData64) -> [ObjCImplementationClassFacts.Property]
    func protocolNames(of readOnlyData: ObjCClassROData64) -> [String]
    /// The selectors of the protocols the class adopts, inherited protocols
    /// included (`ObjCClassMethodIndex`'s witness test).
    func protocolSelectors(of readOnlyData: ObjCClassROData64) -> RawObjCProtocolSelectors
    /// `__objc_catlist`.
    func objcCategories() -> [ObjCCategory64]?
    /// The category's target class by name — readable even when the class
    /// pointer is a bind into another image (the bound symbol names it).
    func targetClassName(of category: ObjCCategory64) -> String?
    /// The category's target class object, paired with the reader for the
    /// image it lives in; `nil` when the pointer is a bind this reader cannot
    /// follow.
    func targetClass(of category: ObjCCategory64) -> (any ObjCImplementationClassReading, ObjCClass64)?
    func instanceMethods(of category: ObjCCategory64) -> [RawObjCMethod]
    func classMethods(of category: ObjCCategory64) -> [RawObjCMethod]
    func protocolSelectors(of category: ObjCCategory64) -> RawObjCProtocolSelectors
}

extension MachOFile: ObjCImplementationClassReading {
    func objcImplementationClassObjects() -> [ObjCClass64]? {
        objc.classes64
    }

    func instanceReadOnlyData(of classObject: ObjCClass64) -> ObjCClassROData64? {
        classObject.classROData(in: self)
    }

    func className(of readOnlyData: ObjCClassROData64) -> String? {
        readOnlyData.name(in: self)
    }

    func superclassName(of classObject: ObjCClass64) -> String? {
        classObject.superClassName(in: self)
    }

    /// On a file the reader follows a rebase into another image of the same
    /// dyld cache; a bind (a standalone file's dependency) resolves to
    /// nothing, and is told apart from a root class by the bound name.
    func superclassLocation(of classObject: ObjCClass64) -> ObjCSuperclassLocation {
        // Explicitly typed: `superClass(in:)` also has a deprecated overload
        // returning a bare `Self?`.
        let resolved: (MachOFile, ObjCClass64)? = classObject.superClass(in: self)
        if let (superclassMachO, superclassObject) = resolved {
            return .resolved(superclassMachO, superclassObject)
        }
        if let superclassName = classObject.superClassName(in: self), !superclassName.isEmpty {
            return .unresolvable(superclassName)
        }
        // A zero slot is a root class only when it is not a bind. The ObjC
        // reader names a chained-fixup bind but reads a legacy `LC_DYLD_INFO`
        // bind (pre-iOS 16 / macOS 12 deployment targets — the iOS 15.5
        // simulator runtime's frameworks) as an empty slot, which once made
        // every such chain look complete and every UIKit override an
        // `@objc(name)`; MachOKitExtensions resolves both formats.
        if !isLoadedFromDyldCache, let bindSymbolName = resolveBind(fileOffset: classObject.offset + Self.superclassFieldOffset) {
            return .unresolvable(bindSymbolName.replacingOccurrences(of: "_OBJC_CLASS_$_", with: ""))
        }
        // A Swift class is never an ObjC root class (its ObjC superclass is
        // `_SwiftObject` at the very least), so a superclass the reader can
        // neither follow nor name is unresolvable, not absent.
        if classObject.isSwift {
            return .unresolvable(nil)
        }
        return .root
    }

    private static let superclassFieldOffset = MemoryLayout<ObjCClass64.Layout>.offset(of: \.superclass) ?? MemoryLayout<UInt64>.size

    func metaClass(of classObject: ObjCClass64) -> ObjCClass64? {
        classObject.metaClass(in: self)?.1
    }

    func rawInstanceVariables(of readOnlyData: ObjCClassROData64) -> [RawObjCInstanceVariable] {
        guard let instanceVariables = readOnlyData.ivarList(in: self)?.ivars(in: self) else { return [] }
        return instanceVariables.map { instanceVariable in
            return RawObjCInstanceVariable(
                name: instanceVariable.name(in: self) ?? "",
                offset: Int(instanceVariable.offset(in: self) ?? 0),
                size: Int(instanceVariable.layout.size),
                alignment: Int(instanceVariable.alignment),
                typeEncoding: instanceVariable.type(in: self) ?? ""
            )
        }
    }

    func methods(of readOnlyData: ObjCClassROData64) -> [RawObjCMethod] {
        var methodLists: [(MachOFile, ObjCMethodList)] = []
        if let methodList = readOnlyData.methodList(in: self) {
            methodLists.append((self, methodList))
        } else if let relativeListList = readOnlyData.methodRelativeListList(in: self) {
            methodLists.append(contentsOf: relativeListList.lists(in: self))
        }
        var rawMethods: [RawObjCMethod] = []
        for (listMachO, methodList) in methodLists {
            guard !methodList.isListOfLists, let methods = methodList.methods(in: listMachO) else { continue }
            for method in methods {
                // On a file the reader hands back an offset already (from the
                // header, or from the main cache for a cache-resident image).
                rawMethods.append(RawObjCMethod(selector: method.name, typeEncoding: method.types, implementationOffset: method.imp == 0 ? nil : Int(method.imp)))
            }
        }
        return rawMethods
    }

    func properties(of readOnlyData: ObjCClassROData64) -> [ObjCImplementationClassFacts.Property] {
        guard let propertyList = readOnlyData.propertyList(in: self), !propertyList.isListOfLists else { return [] }
        return propertyList.properties(in: self).map { .init(name: $0.name, attributes: $0.attributes) }
    }

    func protocolNames(of readOnlyData: ObjCClassROData64) -> [String] {
        guard let protocolList = readOnlyData.protocolList(in: self), !protocolList.isListOfLists,
              let protocols = protocolList.protocols(in: self)
        else { return [] }
        return protocols.map { $1.mangledName(in: $0) }
    }

    func protocolSelectors(of readOnlyData: ObjCClassROData64) -> RawObjCProtocolSelectors {
        Self.protocolSelectors(of: readOnlyData.protocolList(in: self), in: self)
    }

    func objcCategories() -> [ObjCCategory64]? {
        objc.categories64
    }

    /// The ObjC reader names a chained-fixup bind but reads a legacy
    /// `LC_DYLD_INFO` bind (pre-macOS 12 / iOS 16 deployment targets) as an
    /// empty slot — the same gap `superclassLocation(of:)` closes for the
    /// superclass — so the bind stream is consulted for the name.
    func targetClassName(of category: ObjCCategory64) -> String? {
        if let name = category.className(in: self), !name.isEmpty {
            return name
        }
        guard !isLoadedFromDyldCache, let bindSymbolName = resolveBind(fileOffset: category.offset + Self.categoryClassFieldOffset) else { return nil }
        return bindSymbolName.replacingOccurrences(of: "_OBJC_CLASS_$_", with: "")
    }

    private static let categoryClassFieldOffset = MemoryLayout<ObjCCategory64.Layout>.offset(of: \.cls) ?? MemoryLayout<UInt64>.size

    /// A rebase into another image of the same cache resolves; a standalone
    /// file's bind does not.
    func targetClass(of category: ObjCCategory64) -> (any ObjCImplementationClassReading, ObjCClass64)? {
        let resolved: (MachOFile, ObjCClass64)? = category.class(in: self)
        guard let (classMachO, classObject) = resolved else { return nil }
        return (classMachO, classObject)
    }

    func instanceMethods(of category: ObjCCategory64) -> [RawObjCMethod] {
        rawMethods(of: category.instanceMethodList(in: self))
    }

    func classMethods(of category: ObjCCategory64) -> [RawObjCMethod] {
        rawMethods(of: category.classMethodList(in: self))
    }

    func protocolSelectors(of category: ObjCCategory64) -> RawObjCProtocolSelectors {
        Self.protocolSelectors(of: category.protocolList(in: self), in: self)
    }

    private func rawMethods(of methodList: ObjCMethodList?) -> [RawObjCMethod] {
        guard let methodList, !methodList.isListOfLists, let methods = methodList.methods(in: self) else { return [] }
        return methods.map { RawObjCMethod(selector: $0.name, typeEncoding: $0.types, implementationOffset: $0.imp == 0 ? nil : Int($0.imp)) }
    }

    /// Every protocol of `protocolList` and, recursively, of the protocols
    /// they inherit, each read in the image that defines it. A list or a
    /// protocol the reader cannot follow (a bind) marks the result incomplete
    /// rather than dropping silently.
    private static func protocolSelectors(of protocolList: ObjCProtocolList64?, in machO: MachOFile) -> RawObjCProtocolSelectors {
        var result = RawObjCProtocolSelectors(instanceSelectors: [], classSelectors: [], isComplete: true)
        guard let protocolList else { return result }
        var visited: Set<String> = []
        func visit(_ protocolList: ObjCProtocolList64, in machO: MachOFile) {
            guard !protocolList.isListOfLists, let protocols = protocolList.protocols(in: machO) else {
                result.isComplete = false
                return
            }
            for (protocolMachO, objcProtocol) in protocols {
                guard visited.insert(objcProtocol.mangledName(in: protocolMachO)).inserted else { continue }
                for methodList in [objcProtocol.instanceMethodList(in: protocolMachO), objcProtocol.optionalInstanceMethodList(in: protocolMachO)] {
                    guard let methodList, !methodList.isListOfLists, let methods = methodList.methods(in: protocolMachO) else { continue }
                    result.insert(instanceSelectors: methods.map(\.name))
                }
                for methodList in [objcProtocol.classMethodList(in: protocolMachO), objcProtocol.optionalClassMethodList(in: protocolMachO)] {
                    guard let methodList, !methodList.isListOfLists, let methods = methodList.methods(in: protocolMachO) else { continue }
                    result.insert(classSelectors: methods.map(\.name))
                }
                if let inherited = objcProtocol.protocolList(in: protocolMachO) {
                    visit(inherited, in: protocolMachO)
                }
            }
        }
        visit(protocolList, in: machO)
        return result
    }
}

extension MachOImage: ObjCImplementationClassReading {
    func objcImplementationClassObjects() -> [ObjCClass64]? {
        objc.classes64
    }

    /// Resolves the realized (`class_rw_t`) form dyld installs for
    /// cache-resident classes, whose `data` pointer no longer points at
    /// `class_ro_t` directly (same lookup as `SwiftLayout.ObjCClassIndex`).
    func instanceReadOnlyData(of classObject: ObjCClass64) -> ObjCClassROData64? {
        if let readOnlyData = classObject.classROData(in: self) { return readOnlyData }
        guard let readWriteData = classObject.classRWData(in: self) else { return nil }
        if let readOnlyData = readWriteData.classROData(in: self) { return readOnlyData }
        return readWriteData.ext(in: self)?.classROData(in: self)
    }

    func className(of readOnlyData: ObjCClassROData64) -> String? {
        readOnlyData.name(in: self)
    }

    func superclassName(of classObject: ObjCClass64) -> String? {
        classObject.superClassName(in: self)
    }

    /// In-process every superclass pointer is real: it resolves into whichever
    /// loaded image holds the class, and only a root class has none.
    func superclassLocation(of classObject: ObjCClass64) -> ObjCSuperclassLocation {
        guard classObject.layout.superclass != 0 else { return .root }
        let resolved: (MachOImage, ObjCClass64)? = classObject.superClass(in: self)
        guard let (superclassMachO, superclassObject) = resolved else { return .unresolvable(nil) }
        return .resolved(superclassMachO, superclassObject)
    }

    func metaClass(of classObject: ObjCClass64) -> ObjCClass64? {
        classObject.metaClass(in: self)?.1
    }

    func rawInstanceVariables(of readOnlyData: ObjCClassROData64) -> [RawObjCInstanceVariable] {
        guard let instanceVariables = readOnlyData.ivarList(in: self)?.ivars(in: self) else { return [] }
        return instanceVariables.map { instanceVariable in
            return RawObjCInstanceVariable(
                name: instanceVariable.name(in: self),
                offset: Int(instanceVariable.offset(in: self) ?? 0),
                size: Int(instanceVariable.layout.size),
                alignment: Int(instanceVariable.alignment),
                typeEncoding: instanceVariable.type(in: self) ?? ""
            )
        }
    }

    func methods(of readOnlyData: ObjCClassROData64) -> [RawObjCMethod] {
        var methodLists: [(MachOImage, ObjCMethodList)] = []
        if let methodList = readOnlyData.methodList(in: self) {
            methodLists.append((self, methodList))
        } else if let relativeListList = readOnlyData.methodRelativeListList(in: self) {
            methodLists.append(contentsOf: relativeListList.lists(in: self))
        }
        var rawMethods: [RawObjCMethod] = []
        for (listMachO, methodList) in methodLists {
            guard !methodList.isListOfLists else { continue }
            for method in methodList.methods(in: listMachO) {
                // In-process the reader hands back an address.
                rawMethods.append(RawObjCMethod(selector: method.name, typeEncoding: method.types, implementationOffset: method.imp == 0 ? nil : listMachO.resolveOffset(at: method.imp)))
            }
        }
        return rawMethods
    }

    func properties(of readOnlyData: ObjCClassROData64) -> [ObjCImplementationClassFacts.Property] {
        guard let propertyList = readOnlyData.propertyList(in: self), !propertyList.isListOfLists else { return [] }
        return propertyList.properties(in: self).map { .init(name: $0.name, attributes: $0.attributes) }
    }

    func protocolNames(of readOnlyData: ObjCClassROData64) -> [String] {
        guard let protocolList = readOnlyData.protocolList(in: self), !protocolList.isListOfLists,
              let protocols = protocolList.protocols(in: self)
        else { return [] }
        return protocols.map { $1.mangledName(in: $0) }
    }

    func protocolSelectors(of readOnlyData: ObjCClassROData64) -> RawObjCProtocolSelectors {
        Self.protocolSelectors(of: readOnlyData.protocolList(in: self), in: self)
    }

    func objcCategories() -> [ObjCCategory64]? {
        objc.categories64
    }

    func targetClassName(of category: ObjCCategory64) -> String? {
        category.className(in: self)
    }

    /// In-process every class pointer is real.
    func targetClass(of category: ObjCCategory64) -> (any ObjCImplementationClassReading, ObjCClass64)? {
        let resolved: (MachOImage, ObjCClass64)? = category.class(in: self)
        guard let (classMachO, classObject) = resolved else { return nil }
        return (classMachO, classObject)
    }

    func instanceMethods(of category: ObjCCategory64) -> [RawObjCMethod] {
        rawMethods(of: category.instanceMethodList(in: self))
    }

    func classMethods(of category: ObjCCategory64) -> [RawObjCMethod] {
        rawMethods(of: category.classMethodList(in: self))
    }

    func protocolSelectors(of category: ObjCCategory64) -> RawObjCProtocolSelectors {
        Self.protocolSelectors(of: category.protocolList(in: self), in: self)
    }

    private func rawMethods(of methodList: ObjCMethodList?) -> [RawObjCMethod] {
        guard let methodList, !methodList.isListOfLists else { return [] }
        return methodList.methods(in: self).map { RawObjCMethod(selector: $0.name, typeEncoding: $0.types, implementationOffset: $0.imp == 0 ? nil : resolveOffset(at: $0.imp)) }
    }

    private static func protocolSelectors(of protocolList: ObjCProtocolList64?, in machO: MachOImage) -> RawObjCProtocolSelectors {
        var result = RawObjCProtocolSelectors(instanceSelectors: [], classSelectors: [], isComplete: true)
        guard let protocolList else { return result }
        var visited: Set<String> = []
        func visit(_ protocolList: ObjCProtocolList64, in machO: MachOImage) {
            guard !protocolList.isListOfLists, let protocols = protocolList.protocols(in: machO) else {
                result.isComplete = false
                return
            }
            for (protocolMachO, objcProtocol) in protocols {
                guard visited.insert(objcProtocol.mangledName(in: protocolMachO)).inserted else { continue }
                for methodList in [objcProtocol.instanceMethodList(in: protocolMachO), objcProtocol.optionalInstanceMethodList(in: protocolMachO)] {
                    guard let methodList, !methodList.isListOfLists else { continue }
                    result.insert(instanceSelectors: methodList.methods(in: protocolMachO).map(\.name))
                }
                for methodList in [objcProtocol.classMethodList(in: protocolMachO), objcProtocol.optionalClassMethodList(in: protocolMachO)] {
                    guard let methodList, !methodList.isListOfLists else { continue }
                    result.insert(classSelectors: methodList.methods(in: protocolMachO).map(\.name))
                }
                if let inherited = objcProtocol.protocolList(in: protocolMachO) {
                    visit(inherited, in: protocolMachO)
                }
            }
        }
        visit(protocolList, in: machO)
        return result
    }
}
