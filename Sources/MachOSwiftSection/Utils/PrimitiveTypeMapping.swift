import Foundation
import MachOFoundation
import MachOKit
import Demangle
import MachOMacro

package class PrimitiveTypeMapping {
    private var storage: [String: String] = [:]

    package func dump() {
        for (name, type) in storage {
            print("\(name) ---> \(type)")
        }
    }

    package func primitiveType(for name: String) -> String? {
        return storage[name]
    }

    @MachOImageGenerator
    package init(machO: MachOFile) throws {
        let builtinTypes = try machO.swift.builtinTypeDescriptors.map { try BuiltinType(descriptor: $0, in: machO) }
        for builtinType in builtinTypes {
            guard let typeName = builtinType.typeName else { continue }
            let node = try MetadataReader.demangleType(for: typeName, in: machO)
            guard node.children.first?.children.first?.text == objcModule, let descriptorLookup = typeName.lookupElements.first else { continue }
            switch descriptorLookup.reference {
            case .relative(let relativeReference):
                guard let (kind, directness) = SymbolicReference.symbolicReference(for: relativeReference.kind) else { continue }
                switch kind {
                case .context:
                    switch directness {
                    case .direct:
                        guard let descriptor = try RelativeDirectPointer<ContextDescriptorWrapper>(relativeOffset: relativeReference.relativeOffset).resolve(from: descriptorLookup.offset, in: machO).namedContextDescriptor else { continue }
                        let name = try descriptor.name(in: machO)
                        let mangledName = try descriptor.mangledName(in: machO)
                        guard let endOffset = mangledName.endOffset else { continue }
                        storage[name] = try machO.readString(offset: endOffset)
                    case .indirect:
                        continue
                    }
                default:
                    continue
                }
            case .absolute:
                continue
            }
        }
    }
}
