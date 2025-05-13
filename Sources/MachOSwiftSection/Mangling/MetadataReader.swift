import Foundation
import MachOKit
private import Demangling

private enum ParentContextDescriptor {
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


public final class MetadataReader {
    
    private let machOFile: MachOFile
    
    public init(machOFile: MachOFile) {
        self.machOFile = machOFile
    }
    
    private func adoptAnonymousContextName(context: any ContextDescriptorProtocol, parentContext: (any ContextDescriptorProtocol)?, outSymbol: inout SwiftSymbol?) -> SwiftSymbol? {
        outSymbol = nil
        guard let parentContext else { return nil }
        let typeContext = context as? (any TypeContextDescriptorProtocol)
        let protoContext = context as? (any ProtocolDescriptorProtocol)
        guard typeContext != nil || protoContext != nil else { return nil }
        guard let anonymousParent = parentContext as? (any AnonymousContextDescriptorProtocol) else { return nil }
        return nil
    }
    
    private func demangleAnonymousContextName(context: any AnonymousContextDescriptorProtocol) -> SwiftSymbol? {
        return nil
    }
    
    private func buildContextMangling(context: any ContextDescriptorProtocol) throws -> SwiftSymbol? {
        return nil
    }
    
    private func buildContextDescriptorMangling(context: any ContextDescriptorProtocol, recursionLimit: Int) throws -> SwiftSymbol? {
        guard recursionLimit > 0 else { return nil }
        let parentDescriptorResult = try context.parent(in: machOFile)?.contextDescriptor
        var demangledParentNode: SwiftSymbol?
        let nameNode = adoptAnonymousContextName(context: context, parentContext: parentDescriptorResult, outSymbol: &demangledParentNode)
//        guard let parentDescriptorResult else { return nil }
        var parentDemangling: SwiftSymbol?
        
        if let parentDescriptor = parentDescriptorResult {
            parentDemangling = try buildContextDescriptorMangling(context: parentDescriptor, recursionLimit: recursionLimit - 1)
            if parentDemangling == nil, demangledParentNode == nil {
                return nil
            }
        }
        
        if let demangledParentNode, (parentDemangling == nil || parentDemangling!.kind == .anonymousContext) {
            parentDemangling = demangledParentNode
        }
        
        var kind: SwiftSymbol.Kind
//        func contextName() -> Bool {
//            
//        }
        return nil
    }
    
    private func buildContextManglingForSymbol(symbol: String) throws -> SwiftSymbol? {
        var demangler = Demangler(scalars: symbol.unicodeScalars)
        var demangledSymbol = try demangler.demangleSymbol()
        if demangledSymbol.kind == .global {
            demangledSymbol = demangledSymbol.children[0]
        }
        switch demangledSymbol.kind {
        case .nominalTypeDescriptor, .protocolDescriptor:
            demangledSymbol = demangledSymbol.children[0]
        case .opaqueTypeDescriptor:
            demangledSymbol = demangledSymbol.children[0]
        default:
            return nil
        }
        return demangledSymbol
    }
    
    private func demangle(for mangledName: MangledName, kind: MangledNameKind, useOpaqueTypeSymbolicReferences: Bool = false) throws -> SwiftSymbol {
        var demangler = Demangler(scalars: mangledName.stringValue().unicodeScalars)
        demangler.symbolicReferenceResolver = { kind, directness, index -> SwiftSymbol? in
//            switch kind {
//            case .context:
//                
//            }
            return nil
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
    
    
    
    public static func demangle(for mangledName: MangledName, in machO: MachOFile) throws -> String {
        let mangledNameString = mangledName.stringValue()
        guard !mangledNameString.isEmpty else { return "" }
        return try parseMangledSwiftSymbol(mangledNameString.unicodeScalars) { kind, directness, index -> SwiftSymbol? in
            do {
                func handleContextDescriptor(_ context: ContextDescriptorWrapper) throws -> SwiftSymbol? {
                    guard var name = try context.name(in: machO) else { return nil }
                    name = name.countedString
                    name += context.contextDescriptor.layout.flags.kind.mangledType
                    var parent = try context.contextDescriptor.parent(in: machO)
                    while let currnetParent = parent {
                        if let parentName = try currnetParent.name(in: machO) {
                            name = parentName.countedString + currnetParent.contextDescriptor.layout.flags.kind.mangledType + name
                        }
                        parent = try currnetParent.contextDescriptor.parent(in: machO)
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
                        if let context = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machO) {
                            result = try handleContextDescriptor(context)
                        }
                    case .indirect:
                        let relativePointer = RelativeIndirectPointer<ContextDescriptorWrapper?, Pointer<ContextDescriptorWrapper?>>(relativeOffset: relativeOffset)
                        if let bind = try machO.resolveBind(at: fileOffset, for: relativePointer), let symbolName = machO.dyldChainedFixups?.symbolName(for: bind.0.info.nameOffset) {
                            result = try parseMangledSwiftSymbol(symbolName).typeSymbol
                        } else if let context = try relativePointer.resolve(from: fileOffset, in: machO) {
                            result = try handleContextDescriptor(context)
                        }
                    }
                case .accessorFunctionReference:
                    break
                case .uniqueExtendedExistentialTypeShape:
                    let extendedExistentialTypeShape = try RelativeDirectPointer<ExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machO)
                    let existentialType = try extendedExistentialTypeShape.existentialType(in: machO).stringValue()
                    result = try .init(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machO)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: machO).stringValue()
                    result = try .init(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertManglePrefix).children)
                case .objectiveCProtocol:
                    let relativePointer = RelativeDirectPointer<ObjCProtocolPrefix>(relativeOffset: relativeOffset)
                    let objcProtocol = try relativePointer.resolve(from: fileOffset, in: machO)
                    let name = try objcProtocol.mangledName(in: machO).stringValue()
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
}
