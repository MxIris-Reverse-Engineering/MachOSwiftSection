import Foundation
import MachOKit
import MachOSwiftSection
import MachOSwiftSectionMacro

//@MachOImageAllMembersGenerator
//extension NamedContextDescriptorProtocol {
//    func dumpFullname(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
////        var name = try name(in: machOFile)
////        var parent = try parent(in: machOFile)
////        findParent: while let currnetParent = parent {
////            switch currnetParent {
////            case .symbol(let unsolvedSymbol):
////                name = unsolvedSymbol.stringValue + "." + name
////                break findParent
////            case .element(let element):
////                if let parentName = try element.dumpName(using: options, in: machOFile) {
////                    name = parentName + "." + name
////                }
////                parent = try element.contextDescriptor.parent(in: machOFile)
////            }
////        }
////        return name
//        
//        MetadataReader.demangleContext(for: , in: <#T##MachOFile#>)
//    }
//}

extension ContextDescriptorWrapper {
    @MachOImageGenerator
    func dumpName(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
//        if case .extension(let extensionContextDescriptor) = self {
//            return try extensionContextDescriptor.extendedContext(in: machOFile).map { try MetadataReader.demangleType(for: $0, in: machOFile).print(using: options) }
//        } else {
//            return try namedContextDescriptor?.name(in: machOFile)
//        }
        
        try MetadataReader.demangleContext(for: self, in: machOFile).print(using: options)
        
    }
}
