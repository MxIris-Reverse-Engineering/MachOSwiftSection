import Foundation
import MachOKit
private import Demangling

public final class MetadataReader {
    private enum ResolvableContextDescriptor {
        case symbol(String)
        case context(any ContextDescriptorProtocol)

        var isResolved: Bool {
            switch self {
            case .symbol:
                return false
            case .context:
                return true
            }
        }
    }

    private let machOFile: MachOFile

    private init(machOFile: MachOFile) {
        self.machOFile = machOFile
    }

    private func buildContextMangling(context: ResolvableContextDescriptor) throws -> SwiftSymbol? {
        switch context {
        case let .symbol(symbol):
            return try buildContextManglingForSymbol(symbol: symbol)
        case let .context(contextDescriptorProtocol):
            return try buildContextMangling(context: contextDescriptorProtocol)
        }
    }

    private func buildContextMangling(context: any ContextDescriptorProtocol) throws -> SwiftSymbol? {
        guard let demangling = try buildContextDescriptorMangling(context: context, recursionLimit: 50) else {
            return nil
        }
        let top: SwiftSymbol
        if context is (any TypeContextDescriptorProtocol) || context is (any ProtocolDescriptorProtocol) {
            top = .init(kind: .type, children: [demangling])
        } else if context is (any ProtocolDescriptorProtocol) {
            top = .init(kind: .type, children: [.init(kind: .typeSymbolicReference, children: [demangling])])
        } else {
            top = demangling
        }
        return top
    }

    private func adoptAnonymousContextName(context: any ContextDescriptorProtocol, parentContext parentContextRef: inout (any ContextDescriptorProtocol)?, outSymbol: inout SwiftSymbol?) throws -> SwiftSymbol? {
        outSymbol = nil
        guard let parentContext = parentContextRef else { return nil }
        let typeContext = context as? (any TypeContextDescriptorProtocol)
        let protoContext = context as? (any ProtocolDescriptorProtocol)
        guard typeContext != nil || protoContext != nil else { return nil }
        guard let anonymousParent = parentContext as? (any AnonymousContextDescriptorProtocol) else { return nil }
        guard var mangledNode = try demangleAnonymousContextName(context: anonymousParent) else { return nil }
        if mangledNode.kind == .global {
            mangledNode = mangledNode.children[0]
        }
        guard mangledNode.children.count >= 2 else { return nil }

        let nameChild = mangledNode.children[1]

        guard nameChild.kind == .privateDeclName || nameChild.kind == .localDeclName, nameChild.children.count >= 2 else { return nil }

        let identifierNode = nameChild.children[1]

        guard identifierNode.kind == .identifier, identifierNode.contents.hasName else { return nil }

        guard let namedContext = context as? (any NamedContextDescriptorProtocol) else { return nil }
        guard try namedContext.name(in: machOFile) == identifierNode.contents.name else { return nil }

        parentContextRef = try parentContext.parent(in: machOFile)?.contextDescriptor

        outSymbol = mangledNode.children[0]

        return nameChild
    }

    private func demangleAnonymousContextName(context: any AnonymousContextDescriptorProtocol) throws -> SwiftSymbol? {
        guard let mangledName = try context.mangledName(in: machOFile) else { return nil }
        return try demangle(for: mangledName, kind: .symbol)
    }

    private func readProtocol(offset: Int, pointer: RelativeProtocolDescriptorPointer) throws -> SwiftSymbol? {
        switch pointer {
        case let .objcPointer(objcPointer):
            let objcPrefix = try objcPointer.resolve(from: offset, in: machOFile)
            let mangledName = try objcPrefix.mangledName(in: machOFile)
            let name = mangledName.symbolStringValue()
            if name.starts(with: "_TtP") {
                var demangled = try demangle(for: mangledName, kind: .symbol)
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
        case let .swiftPointer(swiftPointer):
            return try buildContextMangling(context: swiftPointer.resolve(from: offset, in: machOFile))
        }
    }

    private func buildContextDescriptorMangling(context: any ContextDescriptorProtocol, recursionLimit: Int) throws -> SwiftSymbol? {
        guard recursionLimit > 0 else { return nil }
        var parentDescriptorResult = try context.parent(in: machOFile)?.contextDescriptor
        var demangledParentNode: SwiftSymbol?
        var nameNode = try adoptAnonymousContextName(context: context, parentContext: &parentDescriptorResult, outSymbol: &demangledParentNode)
//        guard let parentDescriptorResult else { return nil }
        var parentDemangling: SwiftSymbol?

        if let parentDescriptor = parentDescriptorResult {
            parentDemangling = try buildContextDescriptorMangling(context: parentDescriptor, recursionLimit: recursionLimit - 1)
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
            } else if let namedContext = context as? (any NamedContextDescriptorProtocol) {
                nameNode = try .init(kind: .identifier, contents: .name(namedContext.name(in: machOFile)))
                return true
            } else {
                return false
            }
        }

        switch context.layout.flags.kind {
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
            let extensionContext = context as! (any ExtensionContextDescriptorProtocol)
            guard let extendedContext = try extensionContext.extendedContext(in: machOFile) else { return nil }
            guard let demangledExtendedContext = try demangle(for: extendedContext, kind: .type).nominalSymbol else { return nil }
            var demangling = SwiftSymbol(kind: .extension, children: [parentDemangling, demangledExtendedContext])
            if let requirements = try extensionContext.genericContext(in: machOFile)?.requirements {
                var signatureNode = SwiftSymbol(kind: .dependentGenericSignature)
                var failed = false
                for requirement in requirements {
                    if failed {
                        break
                    }
                    let subject = try demangle(for: requirement.paramManagedName(in: machOFile), kind: .type)
                    let offset = requirement.fileOffset(of: \.content)
                    switch requirement.content {
                    case let .protocol(relativeProtocolDescriptorPointer):
                        guard let proto = try? readProtocol(offset: offset, pointer: relativeProtocolDescriptorPointer) else {
                            failed = true
                            break
                        }
                        let requirementNode = SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [subject, proto])
                        signatureNode.children.append(requirementNode)
                    case let .type(relativeDirectPointer):
                        let mangledName = try relativeDirectPointer.resolve(from: offset, in: machOFile)
                        guard let type = try? demangle(for: mangledName, kind: .type) else {
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
            let moduleContext = context as! (any ModuleContextDescriptorProtocol)
            return try .init(kind: .module, contents: .name(moduleContext.name(in: machOFile)))
        case .opaqueType:
            guard let parentDescriptorResult else { return nil }
            if parentDemangling?.kind == .anonymousContext {
                guard var mangledNode = try demangleAnonymousContextName(context: parentDescriptorResult as! (any AnonymousContextDescriptorProtocol)) else {
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

    private func buildContextManglingForSymbol(symbol: String) throws -> SwiftSymbol? {
        var demangler = Demangler(scalars: symbol.unicodeScalars)
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

    private func demangle(for mangledName: MangledName, kind: MangledNameKind, useOpaqueTypeSymbolicReferences: Bool = false) throws -> SwiftSymbol {
        let stringValue = switch kind {
        case .type:
            mangledName.typeStringValue()
        case .symbol:
            mangledName.symbolStringValue()
        }
        var demangler = Demangler(scalars: stringValue.unicodeScalars)
        demangler.symbolicReferenceResolver = { [weak self] kind, directness, index -> SwiftSymbol? in
            guard let self else { return nil }
            do {
                var result: SwiftSymbol?
                let lookup = mangledName.lookupElements[index]
                let fileOffset = lookup.offset
                guard case let .relative(relativeReference) = lookup.reference else { return nil }
                let relativeOffset = relativeReference.relativeOffset
                switch kind {
                case .context:
                    switch directness {
                    case .direct:
                        if let context = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machOFile) {
                            result = try buildContextMangling(context: .context(context.contextDescriptor))
                        }
                    case .indirect:
                        let relativePointer = RelativeIndirectPointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>(relativeOffset: relativeOffset)
                        if let bind = try machOFile.resolveBind(at: fileOffset, for: relativePointer), let symbolName = machOFile.dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
                            result = try buildContextMangling(context: .symbol(symbolName))
                        } else if let context = try relativePointer.resolve(from: fileOffset, in: machOFile) {
                            result = try buildContextMangling(context: .context(context.contextDescriptor))
                        }
                    }
                case .accessorFunctionReference:
                    break
                case .uniqueExtendedExistentialTypeShape:
                    let extendedExistentialTypeShape = try RelativeDirectPointer<ExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machOFile)
                    let existentialType = try extendedExistentialTypeShape.existentialType(in: machOFile).symbolStringValue()
                    result = try .init(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machOFile)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: machOFile).symbolStringValue()
                    result = try .init(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .objectiveCProtocol:
                    let relativePointer = RelativeDirectPointer<RelativeObjCProtocolPrefix>(relativeOffset: relativeOffset)
                    let objcProtocol = try relativePointer.resolve(from: fileOffset, in: machOFile)
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

    public static func demangle(for mangledName: MangledName, in machOFile: MachOFile) throws -> String {
        let reader = MetadataReader(machOFile: machOFile)
        return try reader.demangle(for: mangledName, kind: .type).print()
    }

    public static func oldDemangle(for mangledName: MangledName, in machOFile: MachOFile) throws -> String {
        let mangledNameString = mangledName.symbolStringValue()
        guard !mangledNameString.isEmpty else { return "" }
        return try parseMangledSwiftSymbol(mangledNameString.unicodeScalars) { kind, directness, index -> SwiftSymbol? in
            do {
                func handleContextDescriptor(_ context: ContextDescriptorWrapper) throws -> SwiftSymbol? {
                    guard var name = try context.name(in: machOFile) else { return nil }
                    name = name.countedString
                    name += context.contextDescriptor.layout.flags.kind.mangledType
                    var parent = try context.contextDescriptor.parent(in: machOFile)
                    while let currnetParent = parent {
                        if let parentName = try currnetParent.name(in: machOFile) {
                            name = parentName.countedString + currnetParent.contextDescriptor.layout.flags.kind.mangledType + name
                        }
                        parent = try currnetParent.contextDescriptor.parent(in: machOFile)
                    }

                    return try parseMangledSwiftSymbol(name.insertManglePrefix).typeSymbol
                }
                var result: SwiftSymbol?
                let lookup = mangledName.lookupElements[index]
                let fileOffset = lookup.offset
                guard case let .relative(relativeReference) = lookup.reference else { return nil }
                let relativeOffset = relativeReference.relativeOffset
                switch kind {
                case .context:
                    switch directness {
                    case .direct:
                        if let context = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machOFile) {
                            result = try handleContextDescriptor(context)
                        }
                    case .indirect:
                        let relativePointer = RelativeIndirectPointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>(relativeOffset: relativeOffset)
                        if let bind = try machOFile.resolveBind(at: fileOffset, for: relativePointer), let symbolName = machOFile.dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
                            result = try parseMangledSwiftSymbol(symbolName).typeSymbol
                        } else if let context = try relativePointer.resolve(from: fileOffset, in: machOFile) {
                            result = try handleContextDescriptor(context)
                        }
                    }
                case .accessorFunctionReference:
                    break
                case .uniqueExtendedExistentialTypeShape:
                    let extendedExistentialTypeShape = try RelativeDirectPointer<ExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machOFile)
                    let existentialType = try extendedExistentialTypeShape.existentialType(in: machOFile).symbolStringValue()
                    result = try .init(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machOFile)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: machOFile).symbolStringValue()
                    result = try .init(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .objectiveCProtocol:
                    let relativePointer = RelativeDirectPointer<RelativeObjCProtocolPrefix>(relativeOffset: relativeOffset)
                    let objcProtocol = try relativePointer.resolve(from: fileOffset, in: machOFile)
                    let name = try objcProtocol.mangledName(in: machOFile).symbolStringValue()
                    result = try parseMangledSwiftSymbol(name).typeSymbol
                }
                return result
            } catch {
                return nil
            }

        }.print()
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

    fileprivate var nominalSymbol: SwiftSymbol? {
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
