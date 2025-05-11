import Foundation
import MachOKit
private import Demangling

public enum Demangler {
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

                    return try parseMangledSwiftSymbol(name.insertTypeManglePrefix).typeSymbol
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
                    result = try .init(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertTypeManglePrefix).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: fileOffset, in: machO)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: machO).stringValue()
                    result = try .init(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, children: parseMangledSwiftSymbol(existentialType.insertTypeManglePrefix).children)
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
