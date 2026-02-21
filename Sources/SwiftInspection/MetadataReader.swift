import Foundation
import MachOKit
import Demangling
import MachOFoundation
import SwiftStdlibToolbox
import MachOSwiftSection
@_spi(Internals) import MachOCaches
@_spi(Internals) import MachOSymbols

package enum MetadataReader {}

extension MetadataReader {
    package nonisolated(unsafe) static var isCahceEnabled: Bool = true

    package static func demangleType<MachO: MachOSwiftSectionRepresentableWithCache>(for mangledName: MangledName, in machO: MachO) throws -> Node {
        if isCahceEnabled {
            return try MetadataReaderCache.shared.demangleType(for: mangledName, in: machO)
        } else {
            return try _demangleType(for: mangledName, in: machO)
        }
    }

    fileprivate static func _demangleType<MachO: MachOSwiftSectionRepresentableWithCache>(for mangledName: MangledName, in machO: MachO) throws -> Node {
        return try demangle(for: mangledName, kind: .type, in: machO.context)
    }

    package static func demangleType<MachO: MachOSwiftSectionRepresentableWithCache>(for symbol: Symbol, in machO: MachO) throws -> Node? {
        if isCahceEnabled {
            return try MetadataReaderCache.shared.buildContextManglingForSymbol(symbol, in: machO)
        } else {
            return try _buildContextManglingForSymbol(symbol, in: machO.context)
        }
    }

    package static func demangleSymbol<MachO: MachOSwiftSectionRepresentableWithCache>(for symbol: Symbol, in machO: MachO) throws -> Node? {
        return SymbolIndexStore.shared.demangledNode(for: symbol, in: machO)
    }

    package static func demangleContext<MachO: MachOSwiftSectionRepresentableWithCache>(for context: ContextDescriptorWrapper, in machO: MachO) throws -> Node {
        if isCahceEnabled {
            return try MetadataReaderCache.shared.demangleContext(for: context, in: machO)
        } else {
            return try _demangleContext(for: context, in: machO)
        }
    }

    fileprivate static func _demangleContext<MachO: MachOSwiftSectionRepresentableWithCache>(for context: ContextDescriptorWrapper, in machO: MachO) throws -> Node {
        return try required(buildContextMangling(context: context, in: machO.context))
    }

    package static func buildGenericSignature<MachO: MachOSwiftSectionRepresentableWithCache>(for requirement: GenericRequirementDescriptor, in machO: MachO) throws -> Node? {
        try buildGenericSignature(for: [requirement], in: machO)
    }

    package static func buildGenericSignature<MachO: MachOSwiftSectionRepresentableWithCache>(for requirements: GenericRequirementDescriptor..., in machO: MachO) throws -> Node? {
        try buildGenericSignature(for: requirements, in: machO)
    }

    package static func buildGenericSignature<MachO: MachOSwiftSectionRepresentableWithCache>(for requirements: [GenericRequirementDescriptor], in machO: MachO) throws -> Node? {
        return try buildGenericSignature(for: requirements, in: machO.context)
    }
}

extension MetadataReader {
    package static func demangleType(for mangledName: MangledName) throws -> Node {
        if isCahceEnabled {
            return try MetadataReaderCache.shared.demangleType(for: mangledName)
        } else {
            return try _demangleType(for: mangledName)
        }
    }

    fileprivate static func _demangleType(for mangledName: MangledName) throws -> Node {
        return try demangle(for: mangledName, kind: .type, in: InProcessContext.shared)
    }

    package static func demangleType(for symbol: Symbol) throws -> Node? {
        if isCahceEnabled {
            return try MetadataReaderCache.shared.buildContextManglingForSymbol(symbol)
        } else {
            return try _buildContextManglingForSymbol(symbol, in: InProcessContext.shared)
        }
    }

    package static func demangleSymbol(for symbol: Symbol) throws -> Node? {
        return try demangleAsNode(symbol.name)
    }

    package static func demangleContext(for context: ContextDescriptorWrapper) throws -> Node {
        if isCahceEnabled {
            return try MetadataReaderCache.shared.demangleContext(for: context)
        } else {
            return try _demangleContext(for: context)
        }
    }

    fileprivate static func _demangleContext(for context: ContextDescriptorWrapper) throws -> Node {
        return try required(buildContextMangling(context: context, in: InProcessContext.shared))
    }

    package static func buildGenericSignature(for requirement: GenericRequirementDescriptor) throws -> Node? {
        try buildGenericSignature(for: [requirement])
    }

    package static func buildGenericSignature(for requirements: GenericRequirementDescriptor...) throws -> Node? {
        try buildGenericSignature(for: requirements)
    }

    package static func buildGenericSignature(for requirements: [GenericRequirementDescriptor]) throws -> Node? {
        return try buildGenericSignature(for: requirements, in: InProcessContext.shared)
    }
}

// MARK: - Symbol Lookup Protocol

private protocol SymbolLookupContext {
    func lookupSymbol(at offset: Int) -> MachOSymbols.Symbol?
}

extension MachOContext: SymbolLookupContext {
    func lookupSymbol(at offset: Int) -> MachOSymbols.Symbol? {
        try? Symbol.resolve(from: offset, in: machO)
    }
}

extension InProcessContext: SymbolLookupContext {
    func lookupSymbol(at offset: Int) -> MachOSymbols.Symbol? {
        guard let ptr = UnsafeRawPointer(bitPattern: offset) else { return nil }
        guard let result = MachOImage.symbol(for: ptr) else { return nil }
        return Symbol(offset: offset, name: result.1.name)
    }
}

// MARK: - ReadingContext Support

extension MetadataReader {
    package static func demangleType<Context: ReadingContext>(for mangledName: MangledName, in context: Context) throws -> Node {
        return try demangle(for: mangledName, kind: .type, in: context)
    }

    package static func demangleContext<Context: ReadingContext>(for contextWrapper: ContextDescriptorWrapper, in context: Context) throws -> Node {
        return try required(buildContextMangling(context: contextWrapper, in: context))
    }

    package static func buildGenericSignature<Context: ReadingContext>(for requirement: GenericRequirementDescriptor, in context: Context) throws -> Node? {
        try buildGenericSignature(for: [requirement], in: context)
    }

    package static func buildGenericSignature<Context: ReadingContext>(for requirements: GenericRequirementDescriptor..., in context: Context) throws -> Node? {
        try buildGenericSignature(for: requirements, in: context)
    }

    package static func buildGenericSignature<Context: ReadingContext>(for requirements: [GenericRequirementDescriptor], in context: Context) throws -> Node? {
        guard !requirements.isEmpty else { return nil }
        var requirementNodes: [Node] = []
        var failed = false
        for requirement in requirements {
            if failed {
                break
            }
            let paramMangledName = try requirement.paramMangledName(in: context)
            let subject = try demangle(for: paramMangledName, kind: .type, in: context)
            let contentOffset = requirement.offset(of: \.content)
            switch requirement.content {
            case .protocol(let relativeProtocolDescriptorPointer):
                guard let proto = try? readProtocol(offset: contentOffset, pointer: relativeProtocolDescriptorPointer, in: context) else {
                    failed = true
                    break
                }
                requirementNodes.append(Node.create(kind: .dependentGenericConformanceRequirement, children: [subject, proto]))
            case .type(let relativeDirectPointer):
                let typeAddress = try context.addressFromOffset(contentOffset)
                let mangledName = try relativeDirectPointer.resolve(at: typeAddress, in: context)
                guard let type = try? demangle(for: mangledName, kind: .type, in: context) else {
                    failed = true
                    break
                }
                let nodeKind: Node.Kind

                if requirement.flags.kind == .sameType {
                    nodeKind = .dependentGenericSameTypeRequirement
                } else {
                    nodeKind = .dependentGenericConformanceRequirement
                }

                requirementNodes.append(Node.create(kind: nodeKind, children: [subject, type]))
            case .layout(let genericRequirementLayoutKind):
                if genericRequirementLayoutKind == .class {
                    requirementNodes.append(Node.create(kind: .dependentGenericLayoutRequirement, children: [subject, .create(kind: .identifier, text: "C")]))
                } else {
                    failed = true
                }
            case .conformance:
                break
            case .invertedProtocols:
                break
            }
        }
        if failed || requirementNodes.isEmpty {
            return nil
        } else {
            return Node.create(kind: .dependentGenericSignature, children: requirementNodes)
        }
    }

    private static func demangle<Context: ReadingContext>(for mangledName: MangledName, kind: MangledNameKind, in context: Context) throws -> Node {
        let stringValue = switch kind {
        case .type:
            mangledName.typeString
        case .symbol:
            mangledName.symbolString
        }
        let symbolicReferenceResolver: DemangleSymbolicReferenceResolver = { kind, directness, index -> Node? in
            do {
                var result: Node?
                let lookup = mangledName.lookupElements[index]
                let offset = lookup.offset
                guard case .relative(let relativeReference) = lookup.reference else { return nil }
                let relativeOffset = relativeReference.relativeOffset
                let baseAddress = try context.addressFromOffset(offset)
                switch kind {
                case .context:
                    switch directness {
                    case .direct:
                        if let contextWrapper = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset).resolve(at: baseAddress, in: context) {
                            if let opaqueTypeDescriptor = contextWrapper.opaqueTypeDescriptor {
                                result = .create(kind: .opaqueTypeDescriptorSymbolicReference, index: opaqueTypeDescriptor.offset.cast())
                            } else {
                                result = try buildContextMangling(context: .element(contextWrapper), in: context)
                            }
                        }
                    case .indirect:
                        let relativePointer = RelativeIndirectSymbolOrElementPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset)
                        if let resolvableElement = try relativePointer.resolve(at: baseAddress, in: context).asOptional {
                            if case .element(let element) = resolvableElement, let opaqueTypeDescriptor = element.opaqueTypeDescriptor {
                                result = .create(kind: .opaqueTypeDescriptorSymbolicReference, index: opaqueTypeDescriptor.offset.cast())
                            } else {
                                result = try buildContextMangling(context: resolvableElement, in: context)
                            }
                        }
                    }
                case .accessorFunctionReference:
                    // The symbolic reference points at a resolver function, but we can't
                    // execute code in the target process to resolve it from here.
                    let rawPointerOffset = try RelativeDirectRawPointer(relativeOffset: relativeOffset).resolveDirectAddress(at: context.addressFromOffset(offset), in: context)
                    result = try .create(kind: .accessorFunctionReference, index: context.offsetFromAddress(rawPointerOffset).cast())
                case .uniqueExtendedExistentialTypeShape:
                    let extendedExistentialTypeShape = try RelativeDirectPointer<ExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(at: baseAddress, in: context)
                    let existentialType = try extendedExistentialTypeShape.existentialType(in: context)
                    result = try .create(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, inlineChildren: demangle(for: existentialType, kind: .type, in: context).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(at: baseAddress, in: context)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: context)
                    result = try .create(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, inlineChildren: demangle(for: existentialType, kind: .type, in: context).children)
                case .objectiveCProtocol:
                    let relativePointer = RelativeDirectPointer<RelativeObjCProtocolPrefix>(relativeOffset: relativeOffset)
                    let objcProtocol = try relativePointer.resolve(at: baseAddress, in: context)
                    let protocolMangledName = try objcProtocol.mangledName(in: context)
                    let name = protocolMangledName.symbolString
                    result = try demangleAsNode(name).typeSymbol
                }
                return result
            } catch {
                return nil
            }
        }
        let result: Node
        switch kind {
        case .type:
            result = try demangleAsNode(stringValue, isType: true, symbolicReferenceResolver: symbolicReferenceResolver)
        case .symbol:
            result = try demangleAsNode(stringValue, isType: false, symbolicReferenceResolver: symbolicReferenceResolver)
        }
        return result
    }

    private static func buildContextMangling<Context: ReadingContext>(context: SymbolOrElement<ContextDescriptorWrapper>, in readingContext: Context) throws -> Node? {
        switch context {
        case .symbol(let symbol):
            return try _buildContextManglingForSymbol(symbol, in: readingContext)
        case .element(let contextDescriptorProtocol):
            return try buildContextMangling(context: contextDescriptorProtocol, in: readingContext)
        }
    }

    private static func buildContextMangling<Context: ReadingContext>(context: ContextDescriptorWrapper, in readingContext: Context) throws -> Node? {
        guard let demangling = try buildContextDescriptorMangling(context: context, recursionLimit: 50, in: readingContext) else {
            return nil
        }
        let top: Node

        switch context {
        case .type,
             .protocol:
            top = .create(kind: .type, children: [demangling])
        default:
            top = demangling
        }

        return top
    }

    private static func buildContextDescriptorMangling<Context: ReadingContext>(context: SymbolOrElement<ContextDescriptorWrapper>, recursionLimit: Int, in readingContext: Context) throws -> Node? {
        guard recursionLimit > 0 else { return nil }
        switch context {
        case .symbol(let symbol):
            return try _buildContextManglingForSymbol(symbol, in: readingContext)
        case .element(let contextDescriptor):
            var demangleSymbol = try buildContextDescriptorMangling(context: contextDescriptor, recursionLimit: recursionLimit, in: readingContext)

            if demangleSymbol?.kind == .type {
                demangleSymbol = demangleSymbol?.children.first
            }
            return demangleSymbol
        }
    }

    private static func buildContextDescriptorMangling<Context: ReadingContext>(context: ContextDescriptorWrapper, recursionLimit: Int, in readingContext: Context) throws -> Node? {
        guard recursionLimit > 0 else { return nil }
        var parentDescriptorResult = try context.parent(in: readingContext)
        var demangledParentNode: Node?
        var nameNode = try adoptAnonymousContextName(context: context, parentContextRef: &parentDescriptorResult, outSymbol: &demangledParentNode, in: readingContext)
        var parentDemangling: Node?

        if let parentDescriptor = parentDescriptorResult {
            parentDemangling = try buildContextDescriptorMangling(context: parentDescriptor, recursionLimit: recursionLimit - 1, in: readingContext)
            if parentDemangling == nil, demangledParentNode == nil {
                return nil
            }
        }

        if let demangledParentNode, parentDemangling == nil || parentDemangling!.kind == .anonymousContext {
            parentDemangling = demangledParentNode
        }

        let kind: Node.Kind

        func getContextName() throws -> Bool {
            if nameNode != nil {
                return true
            } else if let namedContext = context.namedContextDescriptor {
                nameNode = try .create(kind: .identifier, text: namedContext.name(in: readingContext))
                return true
            } else {
                return false
            }
        }

        switch context.contextDescriptor.layout.flags.kind {
        case .class:
            guard try getContextName() else { return nil }
            kind = .class
        case .struct:
            guard try getContextName() else { return nil }
            kind = .structure
        case .enum:
            guard try getContextName() else { return nil }
            kind = .enum
        case .protocol:
            guard try getContextName() else { return nil }
            kind = .protocol
        case .extension:
            guard let parentDemangling else { return nil }
            guard let extensionContext = context.extensionContextDescriptor else { return nil }
            guard let extendedContext = try extensionContext.extendedContext(in: readingContext) else { return nil }
            guard let demangledExtendedContext = try demangle(for: extendedContext, kind: .type, in: readingContext).extensionSymbol else { return nil }
            if let requirements = try extensionContext.genericContext(in: readingContext)?.requirements, let signatureNode = try buildGenericSignature(for: requirements, in: readingContext) {
                return Node.create(kind: .extension, children: [parentDemangling, demangledExtendedContext, signatureNode])
            } else {
                return Node.create(kind: .extension, children: [parentDemangling, demangledExtendedContext])
            }
        case .anonymous:
            // Look up symbol using the context's symbol lookup capability
            if let lookupContext = readingContext as? SymbolLookupContext,
               let symbol = lookupContext.lookupSymbol(at: context.contextDescriptor.offset),
               let privateDeclName = try? symbol.demangledNode.first(of: Node.Kind.privateDeclName),
               let privateDeclNameIdentifier = privateDeclName.children.first {
                if let parentDemangling {
                    return Node.create(kind: .anonymousContext, children: [privateDeclNameIdentifier, parentDemangling])
                } else {
                    return Node.create(kind: .anonymousContext, children: [privateDeclNameIdentifier])
                }
            }
            return parentDemangling
        case .module:
            if parentDemangling != nil {
                return nil
            }
            guard let moduleContext = context.moduleContextDescriptor else { return nil }
            return try .create(kind: .module, text: moduleContext.name(in: readingContext))
        case .opaqueType:
            guard let parentDescriptorResult else { return nil }
            if parentDemangling?.kind == .anonymousContext {
                guard var mangledNode = try demangleAnonymousContextName(context: parentDescriptorResult, in: readingContext) else {
                    return nil
                }
                if mangledNode.kind == .global {
                    mangledNode = mangledNode.children[0]
                }
                let opaqueNode = Node.create(kind: .opaqueReturnTypeOf, children: [mangledNode])
                return opaqueNode
            } else if let parentDemangling, parentDemangling.kind == .module {
                let opaqueNode = Node.create(kind: .opaqueReturnTypeOf, children: [parentDemangling])
                return opaqueNode
            } else {
                return nil
            }
        default:
            return nil
        }
        guard var parentDemangling, var nameNode else { return nil }
        if parentDemangling.kind == .anonymousContext, nameNode.kind == .identifier {
            if parentDemangling.children.count < 2 {
                return nil
            }
            nameNode = Node.create(kind: .privateDeclName, children: [parentDemangling.children[0], nameNode])
            parentDemangling = parentDemangling.children[1]
        }
        let demangling = Node.create(kind: kind, children: [parentDemangling, nameNode])

        return demangling
    }

    private static func adoptAnonymousContextName<Context: ReadingContext>(context: ContextDescriptorWrapper, parentContextRef: inout SymbolOrElement<ContextDescriptorWrapper>?, outSymbol: inout Node?, in readingContext: Context) throws -> Node? {
        outSymbol = nil
        guard let parentContextLocalRef = parentContextRef else { return nil }
        guard case .element(let parentContext) = parentContextRef else { return nil }
        guard context.isType || context.isProtocol else { return nil }
        guard var mangledNode = try demangleAnonymousContextName(context: parentContextLocalRef, in: readingContext) else { return nil }
        if mangledNode.kind == .global {
            mangledNode = mangledNode.children[0]
        }
        guard mangledNode.children.count >= 2 else { return nil }

        let nameChild = mangledNode.children[1]

        guard nameChild.kind == .privateDeclName || nameChild.kind == .localDeclName, nameChild.children.count >= 2 else { return nil }

        let identifierNode = nameChild.children[1]

        guard identifierNode.kind == .identifier, identifierNode.hasText else { return nil }

        guard let namedContext = context.namedContextDescriptor else { return nil }
        guard try namedContext.name(in: readingContext) == identifierNode.text else { return nil }

        parentContextRef = try parentContext.parent(in: readingContext)

        outSymbol = mangledNode.children[0]

        return nameChild
    }

    private static func demangleAnonymousContextName<Context: ReadingContext>(context: SymbolOrElement<ContextDescriptorWrapper>, in readingContext: Context) throws -> Node? {
        guard case .element(.anonymous(let context)) = context, let mangledName = try context.mangledName(in: readingContext) else { return nil }
        return try demangle(for: mangledName, kind: .symbol, in: readingContext)
    }

    private static func readProtocol<Context: ReadingContext>(offset: Int, pointer: RelativeProtocolDescriptorPointer, in context: Context) throws -> Node? {
        let baseAddress = try context.addressFromOffset(offset)
        switch pointer {
        case .objcPointer(let objcPointer):
            let objcPrefixElement = try objcPointer.resolve(at: baseAddress, in: context)
            switch objcPrefixElement {
            case .symbol(let symbol):
                return try _buildContextManglingForSymbol(symbol, in: context)
            case .element(let objcPrefix):
                let mangledName = try objcPrefix.mangledName(in: context)
                let name = mangledName.symbolString
                if name.starts(with: "_TtP") {
                    var demangled = try demangle(for: mangledName, kind: .symbol, in: context)
                    while demangled.kind == .global ||
                        demangled.kind == .typeMangling ||
                        demangled.kind == .type ||
                        demangled.kind == .protocolList ||
                        demangled.kind == .typeList ||
                        demangled.kind == .type {
                        if demangled.children.count != 1 {
                            return nil
                        }
                        demangled = demangled.children.first!
                    }
                    return demangled
                } else {
                    return Node.create(kind: .protocol, children: [.create(kind: .module, text: objcModule), .create(kind: .identifier, text: name)])
                }
            }
        case .swiftPointer(let swiftPointer):
            let resolvableProtocolDescriptor = try swiftPointer.resolve(at: baseAddress, in: context)
            switch resolvableProtocolDescriptor {
            case .symbol(let symbol):
                return try _buildContextManglingForSymbol(symbol, in: context)
            case .element(let protocolDescriptor):
                return try buildContextMangling(context: .protocol(protocolDescriptor), in: context)
            }
        }
    }

    fileprivate static func _buildContextManglingForSymbol<Context: ReadingContext>(_ symbol: Symbol, in context: Context) throws -> Node? {
        var demangledSymbol = try demangleAsNode(symbol.name)
        if demangledSymbol.kind == .global {
            demangledSymbol = demangledSymbol.children[0]
        }
        switch demangledSymbol.kind {
        case .nominalTypeDescriptor,
             .protocolDescriptor:
            demangledSymbol = demangledSymbol.children[0]
        case .opaqueTypeDescriptor:
            demangledSymbol = demangledSymbol.children[0]
        default:
            return nil
        }
        return demangledSymbol
    }
}

extension Node {
    fileprivate var typeSymbol: Node? {
        func enumerate(_ child: Node) -> Node? {
            if child.kind == .type {
                return child
            }

            if child.kind == .enum || child.kind == .structure || child.kind == .class || child.kind == .protocol {
                return .create(kind: .type, contents: .none, children: [child])
            }

            for child in child.children {
                if let result = enumerate(child) {
                    return result
                }
            }
            return nil
        }
        return enumerate(self)
    }

    fileprivate var typeNonWrapperSymbol: Node? {
        func enumerate(_ child: Node) -> Node? {
            if child.kind == .enum || child.kind == .structure || child.kind == .class || child.kind == .protocol {
                return child
            }

            for child in child.children {
                if let result = enumerate(child) {
                    return result
                }
            }
            return nil
        }
        return enumerate(self)
    }

    fileprivate var extensionSymbol: Node? {
        typeNonWrapperSymbol
    }

    fileprivate func nodes(for kind: Node.Kind) -> [Node] {
        var nodes: [Node] = []
        func enumerate(_ child: Node) {
            if child.kind == kind {
                nodes.append(child)
            }
            for child in child.children {
                enumerate(child)
            }
        }
        enumerate(self)
        return nodes
    }
}

private final class MetadataReaderCache: SharedCache<MetadataReaderCache.Storage>, @unchecked Sendable {
    fileprivate static let shared = MetadataReaderCache()

    private override init() {}

    fileprivate struct MangledNameBox: Hashable {
        let wrappedValue: MangledName

        func hash(into hasher: inout Hasher) {
            hasher.combine(wrappedValue.elements)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.wrappedValue.elements == rhs.wrappedValue.elements
        }

        init(_ wrappedValue: MangledName) {
            self.wrappedValue = wrappedValue
        }
    }

    final class Storage {
        @Mutex
        fileprivate var nodeForMangledNameBox: [MangledNameBox: Node] = [:]

        /// Cache for context descriptor demangling results, keyed by descriptor offset.
        @Mutex
        fileprivate var nodeForContextOffset: [Int: Node] = [:]

        /// Cache for symbol-based context mangling results, keyed by symbol name.
        @Mutex
        fileprivate var nodeForSymbolName: [String: Node?] = [:]
    }

    override func buildStorage<MachO: MachORepresentableWithCache>(for machO: MachO) -> Storage? {
        Storage()
    }

    override func buildStorage() -> Storage? {
        Storage()
    }

    func demangleType<MachO: MachOSwiftSectionRepresentableWithCache>(for mangledName: MangledName, in machO: MachO) throws -> Node {
        if let node = storage(in: machO)?.nodeForMangledNameBox[MangledNameBox(mangledName)] {
            return node
        } else {
            let node = try MetadataReader._demangleType(for: mangledName, in: machO)
            storage(in: machO)?.nodeForMangledNameBox[MangledNameBox(mangledName)] = node
            return node
        }
    }

    func demangleType(for mangledName: MangledName) throws -> Node {
        if let node = storage()?.nodeForMangledNameBox[MangledNameBox(mangledName)] {
            return node
        } else {
            let node = try MetadataReader._demangleType(for: mangledName)
            storage()?.nodeForMangledNameBox[MangledNameBox(mangledName)] = node
            return node
        }
    }

    // MARK: - Context Descriptor Cache

    func demangleContext<MachO: MachOSwiftSectionRepresentableWithCache>(for context: ContextDescriptorWrapper, in machO: MachO) throws -> Node {
        let key = context.contextDescriptor.offset
        if let node = storage(in: machO)?.nodeForContextOffset[key] {
            return node
        } else {
            let node = try MetadataReader._demangleContext(for: context, in: machO)
            storage(in: machO)?.nodeForContextOffset[key] = node
            return node
        }
    }

    func demangleContext(for context: ContextDescriptorWrapper) throws -> Node {
        let key = context.contextDescriptor.offset
        if let node = storage()?.nodeForContextOffset[key] {
            return node
        } else {
            let node = try MetadataReader._demangleContext(for: context)
            storage()?.nodeForContextOffset[key] = node
            return node
        }
    }

    // MARK: - Symbol Context Mangling Cache

    func buildContextManglingForSymbol<MachO: MachOSwiftSectionRepresentableWithCache>(_ symbol: Symbol, in machO: MachO) throws -> Node? {
        let key = symbol.name
        if let cached = storage(in: machO)?.nodeForSymbolName[key] {
            return cached
        } else {
            let node = try MetadataReader._buildContextManglingForSymbol(symbol, in: machO.context)
            storage(in: machO)?.nodeForSymbolName[key] = node
            return node
        }
    }

    func buildContextManglingForSymbol(_ symbol: Symbol) throws -> Node? {
        let key = symbol.name
        if let cached = storage()?.nodeForSymbolName[key] {
            return cached
        } else {
            let node = try MetadataReader._buildContextManglingForSymbol(symbol, in: InProcessContext.shared)
            storage()?.nodeForSymbolName[key] = node
            return node
        }
    }
}
