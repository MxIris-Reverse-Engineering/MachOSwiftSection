import Foundation
import MachOKit
import Demangling
import MachOSwiftSectionMacro

@MachOImageAllMembersGenerator
public struct MetadataReader {
    private static func buildContextMangling(context: ResolvableElement<ContextDescriptorWrapper>, in machOFile: MachOFile) throws -> SwiftSymbol? {
        switch context {
        case let .symbol(symbol):
            return try buildContextManglingForSymbol(symbol: symbol, in: machOFile)
        case let .element(contextDescriptorProtocol):
            return try buildContextMangling(context: contextDescriptorProtocol, in: machOFile)
        }
    }

    private static func buildContextMangling(context: ContextDescriptorWrapper, in machOFile: MachOFile) throws -> SwiftSymbol? {
        guard let demangling = try buildContextDescriptorMangling(context: context, recursionLimit: 50, in: machOFile) else {
            return nil
        }
        let top: SwiftSymbol

        switch context {
        case .type,
             .protocol:
            top = .init(kind: .type, children: [demangling])
        default:
            top = demangling
        }

        return top
    }
    
    private static func adoptAnonymousContextName(context: ContextDescriptorWrapper, parentContextRef: inout ContextDescriptorWrapper?, outSymbol: inout SwiftSymbol?, in machOFile: MachOFile) throws -> SwiftSymbol? {
        outSymbol = nil
        guard let parentContext = parentContextRef else { return nil }
        guard context.isType || context.isProtocol else { return nil }
        guard case let .anonymous(anonymousParent) = parentContext else { return nil }
        guard var mangledNode = try demangleAnonymousContextName(context: anonymousParent, in: machOFile) else { return nil }
        if mangledNode.kind == .global {
            mangledNode = mangledNode.children[0]
        }
        guard mangledNode.children.count >= 2 else { return nil }

        let nameChild = mangledNode.children[1]

        guard nameChild.kind == .privateDeclName || nameChild.kind == .localDeclName, nameChild.children.count >= 2 else { return nil }

        let identifierNode = nameChild.children[1]

        guard identifierNode.kind == .identifier, identifierNode.contents.hasName else { return nil }

        guard let namedContext = context.namedContextDescriptor else { return nil }
        guard try namedContext.name(in: machOFile) == identifierNode.contents.name else { return nil }

        parentContextRef = try parentContext.parent(in: machOFile)?.resolved

        outSymbol = mangledNode.children[0]

        return nameChild
    }

    private static func demangleAnonymousContextName(context: AnonymousContextDescriptor, in machOFile: MachOFile) throws -> SwiftSymbol? {
//        switch context {
//        case .symbol(let unsolvedSymbol):
//            return try buildContextManglingForSymbol(symbol: unsolvedSymbol)
//        case .element(let context):
        guard let mangledName = try context.mangledName(in: machOFile) else { return nil }
        return try demangle(for: mangledName, kind: .symbol, in: machOFile)
//        }
    }

    private static func readProtocol(offset: Int, pointer: RelativeProtocolDescriptorPointer, in machOFile: MachOFile) throws -> SwiftSymbol? {
        switch pointer {
        case let .objcPointer(objcPointer):
            let objcPrefixElement = try objcPointer.resolve(from: offset, in: machOFile)
            switch objcPrefixElement {
            case let .symbol(symbol):
                return try buildContextManglingForSymbol(symbol: symbol, in: machOFile)
            case let .element(objcPrefix):
                let mangledName = try objcPrefix.mangledName(in: machOFile)
                let name = mangledName.symbolStringValue()
                if name.starts(with: "_TtP") {
                    var demangled = try demangle(for: mangledName, kind: .symbol, in: machOFile)
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
                    return SwiftSymbol(kind: .protocol, children: [.init(kind: .module, contents: .name(objcModule)), .init(kind: .identifier, contents: .name(name))])
                }
            }
        case let .swiftPointer(swiftPointer):
            let resolvableProtocolDescriptor = try swiftPointer.resolve(from: offset, in: machOFile)
            switch resolvableProtocolDescriptor {
            case let .symbol(symbol):
                return try buildContextManglingForSymbol(symbol: symbol, in: machOFile)
            case let .element(context):
                return try buildContextMangling(context: .protocol(context), in: machOFile)
            }
        }
    }

    private static func buildContextDescriptorMangling(context: ContextDescriptorWrapper, recursionLimit: Int, in machOFile: MachOFile) throws -> SwiftSymbol? {
        guard recursionLimit > 0 else { return nil }
        var parentDescriptorResult = try context.parent(in: machOFile)?.resolved
        var demangledParentNode: SwiftSymbol?
        var nameNode = try adoptAnonymousContextName(context: context, parentContextRef: &parentDescriptorResult, outSymbol: &demangledParentNode, in: machOFile)
//        guard let parentDescriptorResult else { return nil }
        var parentDemangling: SwiftSymbol?

        if let parentDescriptor = parentDescriptorResult {
            parentDemangling = try buildContextDescriptorMangling(context: parentDescriptor, recursionLimit: recursionLimit - 1, in: machOFile)
            if parentDemangling == nil, demangledParentNode == nil {
                return nil
            }
        }

        if let demangledParentNode, parentDemangling == nil || parentDemangling!.kind == .anonymousContext {
            parentDemangling = demangledParentNode
        }

        let kind: SwiftSymbol.Kind
        func getContextName() throws -> Bool {
            if nameNode != nil {
                return true
            } else if let namedContext = context.namedContextDescriptor {
                nameNode = try .init(kind: .identifier, contents: .name(namedContext.name(in: machOFile)))
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
//            return parentDemangling
            guard let parentDemangling else { return nil }
            guard let extensionContext = context.extensionContextDescriptor else { return nil }
            guard let extendedContext = try extensionContext.extendedContext(in: machOFile) else { return nil }
            guard let demangledExtendedContext = try demangle(for: extendedContext, kind: .type, in: machOFile).typeNonWrapperSymbol else { return nil }
            var demangling = SwiftSymbol(kind: .extension, children: [parentDemangling, demangledExtendedContext])
            if let requirements = try extensionContext.genericContext(in: machOFile)?.requirements {
                var signatureNode = SwiftSymbol(kind: .dependentGenericSignature)
                var failed = false
                for requirement in requirements {
                    if failed {
                        break
                    }
                    let subject = try demangle(for: requirement.paramManagedName(in: machOFile), kind: .type, in: machOFile)
                    let offset = requirement.offset(of: \.content)
                    switch requirement.content {
                    case let .protocol(relativeProtocolDescriptorPointer):
                        guard let proto = try? readProtocol(offset: offset, pointer: relativeProtocolDescriptorPointer, in: machOFile) else {
                            failed = true
                            break
                        }
                        let requirementNode = SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [subject, proto])
                        signatureNode.children.append(requirementNode)
                    case let .type(relativeDirectPointer):
                        let mangledName = try relativeDirectPointer.resolve(from: offset, in: machOFile)
                        guard let type = try? demangle(for: mangledName, kind: .type, in: machOFile) else {
                            failed = true
                            break
                        }
                        let nodeKind: SwiftSymbol.Kind

                        if requirement.flags.kind == .sameType {
                            nodeKind = .dependentGenericSameTypeRequirement
                        } else {
                            nodeKind = .dependentGenericConformanceRequirement
                        }

                        let requirementNode = SwiftSymbol(kind: nodeKind, children: [subject, type])
                        signatureNode.children.append(requirementNode)
                    case let .layout(genericRequirementLayoutKind):
                        if genericRequirementLayoutKind == .class {
                            let requirementNode = SwiftSymbol(kind: .dependentGenericLayoutRequirement, children: [subject, .init(kind: .identifier, contents: .name("C"))])
                            signatureNode.children.append(requirementNode)
                        } else {
                            failed = true
                        }
                    case .conformance:
                        break
                    case .invertedProtocols:
                        break
                    }
                }
                if !failed {
                    demangling.children.append(signatureNode)
                }
            }
            return demangling
        case .anonymous:
//            return nil
//            break
            return parentDemangling
//            var anonNode = SwiftSymbol(kind: .anonymousContext)
//            anonNode.children.append(.init(kind: .identifier, contents: .name(context.offset.description)))
//            if let parentDemangling {
//                anonNode.children.append(parentDemangling)
//            }
//            return anonNode
        case .module:
            if parentDemangling != nil {
                return nil
            }
            guard let moduleContext = context.moduleContextDescriptor else { return nil }
            return try .init(kind: .module, contents: .name(moduleContext.name(in: machOFile)))
        case .opaqueType:
            guard let parentDescriptorResult else { return nil }
            if parentDemangling?.kind == .anonymousContext {
                guard var mangledNode = try demangleAnonymousContextName(context: parentDescriptorResult.anonymousContextDescriptor!, in: machOFile) else {
                    return nil
                }
                if mangledNode.kind == .global {
                    mangledNode = mangledNode.children[0]
                }
                let opaqueNode = SwiftSymbol(kind: .opaqueReturnTypeOf, children: [mangledNode])
                return opaqueNode
            } else if let parentDemangling, parentDemangling.kind == .module {
                let opaqueNode = SwiftSymbol(kind: .opaqueReturnTypeOf, children: [parentDemangling])
                return opaqueNode
            } else {
                return nil
            }
        default:
            return nil
        }
        guard let parentDemangling, let nameNode else { return nil }
        if parentDemangling.kind == .anonymousContext, nameNode.kind == .identifier {
            if parentDemangling.children.count < 2 {
                return nil
            }
        }
        let demangling = SwiftSymbol(kind: kind, children: [parentDemangling, nameNode])

        return demangling
    }

    private static func buildContextManglingForSymbol(symbol: UnsolvedSymbol, in machOFile: MachOFile) throws -> SwiftSymbol? {
        var demangler = Demangler(scalars: symbol.stringValue.unicodeScalars)
        var demangledSymbol = try demangler.demangleSymbol()
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

    private static func demangle(for mangledName: MangledName, kind: MangledNameKind, useOpaqueTypeSymbolicReferences: Bool = false, in machOFile: MachOFile) throws -> SwiftSymbol {
        let stringValue = switch kind {
        case .type:
            mangledName.typeStringValue()
        case .symbol:
            mangledName.symbolStringValue()
        }
        var demangler = Demangler(scalars: stringValue.unicodeScalars)
        demangler.symbolicReferenceResolver = { kind, directness, index -> SwiftSymbol? in
            do {
                var result: SwiftSymbol?
                let lookup = mangledName.lookupElements[index]
                let offset = lookup.offset
                guard case let .relative(relativeReference) = lookup.reference else { return nil }
                let relativeOffset = relativeReference.relativeOffset
                switch kind {
                case .context:
                    switch directness {
                    case .direct:
                        if let context = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset).resolve(from: offset, in: machOFile) {
                            result = try buildContextMangling(context: .element(context), in: machOFile)
                        }
                    case .indirect:
                        let relativePointer = RelativeIndirectResolvableElementPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset)
                        if let resolvableElement = try relativePointer.resolve(from: offset, in: machOFile).asOptional {
                            result = try buildContextMangling(context: resolvableElement, in: machOFile)
                        }
                    }
                case .accessorFunctionReference:
                    break
                case .uniqueExtendedExistentialTypeShape:
                    let extendedExistentialTypeShape = try RelativeDirectPointer<ExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: offset, in: machOFile)
                    let existentialType = try extendedExistentialTypeShape.existentialType(in: machOFile).symbolStringValue()
                    result = try .init(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: offset, in: machOFile)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: machOFile).symbolStringValue()
                    result = try .init(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .objectiveCProtocol:
                    let relativePointer = RelativeDirectPointer<RelativeObjCProtocolPrefix>(relativeOffset: relativeOffset)
                    let objcProtocol = try relativePointer.resolve(from: offset, in: machOFile)
                    let name = try objcProtocol.mangledName(in: machOFile).symbolStringValue()
                    result = try parseMangledSwiftSymbol(name).typeSymbol
                }
                return result
            } catch {
                return nil
            }
        }
        let result: SwiftSymbol
        switch kind {
        case .type:
            result = try demangler.demangleType()
        case .symbol:
            result = try demangler.demangleSymbol()
        }
        return result
    }

    public static func demangleType(for mangledName: MangledName, in machOFile: MachOFile, using options: SymbolPrintOptions = .default) throws -> String {
        return try MetadataReader.demangle(for: mangledName, kind: .type, in: machOFile).print(using: options)
    }

    public static func demangleSymbol(for mangledName: MangledName, in machOFile: MachOFile, using options: SymbolPrintOptions = .default) throws -> String {
        return try MetadataReader.demangle(for: mangledName, kind: .symbol, in: machOFile).print(using: options)
    }

    public static func demangleType(for unsolvedSymbol: UnsolvedSymbol, in machOFile: MachOFile, using options: SymbolPrintOptions = .default) throws -> String {
        return try MetadataReader.buildContextManglingForSymbol(symbol: unsolvedSymbol, in: machOFile)?.print(using: options) ?? ""
    }

    public static func demangleSymbol(for unsolvedSymbol: UnsolvedSymbol, in machOFile: MachOFile, using options: SymbolPrintOptions = .default) throws -> String {
        return try MetadataReader.demangle(for: .init(unsolvedSymbol: unsolvedSymbol), kind: .symbol, in: machOFile).print(using: options)
    }
}

extension SwiftSymbol {
    fileprivate var typeSymbol: SwiftSymbol? {
        func enumerate(_ child: SwiftSymbol) -> SwiftSymbol? {
            if child.kind == .type {
                return child
            }

            if child.kind == .enum || child.kind == .structure || child.kind == .class || child.kind == .protocol {
                return .init(kind: .type, children: [child], contents: .none)
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

    fileprivate var typeNonWrapperSymbol: SwiftSymbol? {
        func enumerate(_ child: SwiftSymbol) -> SwiftSymbol? {
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
}
