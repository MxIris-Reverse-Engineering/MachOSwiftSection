import Foundation
import MachOSwiftSection
import SwiftDump

let printOptions: SymbolPrintOptions = {
    var options = SymbolPrintOptions.default
    options.remove(.displayObjCModule)
    options.insert(.synthesizeSugarOnTypes)
    options.remove(.displayWhereClauses)
    options.remove(.displayExtensionContexts)
    options.remove(.showPrivateDiscriminators)
    return options
}()
