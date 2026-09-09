import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection

extension ResolvedTypeReference {
    package func node<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node? {
        switch self {
        case .directTypeDescriptor(let descriptor):
            return try descriptor.map { try SymbolicDemangler.demangleContext(for: $0, in: machO) }
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let symbol):
                return try SymbolicDemangler.demangleType(for: symbol, in: machO)
            case .element(let element):
                return try SymbolicDemangler.demangleContext(for: element, in: machO)
            case nil:
                return nil
            }
        case .directObjCClassName(let objcClassName):
            guard let objcClassName, !objcClassName.isEmpty else { return nil }
            return Node.createTransient(kind: .type, children: [
                Node.createTransient(kind: .class, children: [
                    .createTransient(kind: .module, text: objcModule),
                    .createTransient(kind: .identifier, text: objcClassName),
                ])
            ])
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let symbol):
                return try SymbolicDemangler.demangleType(for: symbol, in: machO)
            case .element(let element):
                guard let classDescriptor = try element.descriptor.resolve(in: machO) else { return nil }
                return try SymbolicDemangler.demangleContext(for: .type(.class(classDescriptor)), in: machO)
            case nil:
                return nil
            }
        }
    }

    package func node() throws -> Node? {
        switch self {
        case .directTypeDescriptor(let descriptor):
            return try descriptor.map { try SymbolicDemangler.demangleContext(for: $0) }
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let symbol):
                return try SymbolicDemangler.demangleType(for: symbol)
            case .element(let element):
                return try SymbolicDemangler.demangleContext(for: element)
            case nil:
                return nil
            }
        case .directObjCClassName(let objcClassName):
            guard let objcClassName, !objcClassName.isEmpty else { return nil }
            return Node.createTransient(kind: .type, children: [
                Node.createTransient(kind: .class, children: [
                    .createTransient(kind: .module, text: objcModule),
                    .createTransient(kind: .identifier, text: objcClassName),
                ])
            ])
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let symbol):
                return try SymbolicDemangler.demangleType(for: symbol)
            case .element(let element):
                guard let classDescriptor = try element.descriptor.resolve() else { return nil }
                return try SymbolicDemangler.demangleContext(for: .type(.class(classDescriptor)))
            case nil:
                return nil
            }
        }
    }
}
