import Foundation
import Demangle
import MachOKit

public typealias DemangleOptions = Demangle.DemangleOptions

public protocol Dumpable {
    func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> String
    func dump(using options: DemangleOptions, in machOImage: MachOImage) throws -> String
}
