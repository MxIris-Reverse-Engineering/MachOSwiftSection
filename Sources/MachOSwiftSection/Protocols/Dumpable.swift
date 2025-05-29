import Foundation
import Demangling
import MachOKit

public protocol Dumpable {
    typealias SymbolPrintOptions = Demangling.SymbolPrintOptions
    func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String
    func dump(using options: SymbolPrintOptions, in machOImage: MachOImage) throws -> String
}
