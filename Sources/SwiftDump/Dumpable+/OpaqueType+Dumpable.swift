import Foundation
import MachOKit
import MachOSwiftSection
import MachOSwiftSectionMacro

//extension OpaqueType: Dumpable {
//    @MachOImageGenerator
//    @StringBuilder
//    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
//        try "opaquetype \(descriptor.dumpFullname(using: options, in: machOFile))"
//        for underlyingTypeArgumentMangledName in self.underlyingTypeArgumentMangledNames {
//            try MetadataReader.demangleType(for: underlyingTypeArgumentMangledName, in: machOFile).print(using: options)
//        }
//    }
//    
//    
//    
//}
//
//@MachOImageAllMembersGenerator
//extension OpaqueTypeDescriptorProtocol {
//    func dumpFullname(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
//        var name = ""
//        var parent = try parent(in: machOFile)
//        findParent: while let currnetParent = parent {
//            switch currnetParent {
//            case .symbol(let unsolvedSymbol):
//                name = unsolvedSymbol.stringValue + "." + name
//                break findParent
//            case .element(let element):
//                if let parentName = try element.dumpName(using: options, in: machOFile) {
//                    name = parentName + "." + name
//                }
//                parent = try element.contextDescriptor.parent(in: machOFile)
//            }
//        }
//        return name
//    }
//}
