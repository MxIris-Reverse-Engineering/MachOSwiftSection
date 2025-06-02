import Foundation
import Demangle
import MachOKit

public typealias SymbolPrintOptions = Demangle.SymbolPrintOptions

public protocol Dumpable {
    func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String
    func dump(using options: SymbolPrintOptions, in machOImage: MachOImage) throws -> String
}
