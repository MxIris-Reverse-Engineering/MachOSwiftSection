import Foundation
import Demangling
import MachOKit

public typealias SymbolPrintOptions = Demangling.SymbolPrintOptions

public protocol Dumpable {
    func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String
    func dump(using options: SymbolPrintOptions, in machOImage: MachOImage) throws -> String
}
