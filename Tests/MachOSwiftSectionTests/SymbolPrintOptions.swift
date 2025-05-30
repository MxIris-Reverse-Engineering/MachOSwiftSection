import Foundation
import MachOSwiftSection

let printOptions: SymbolPrintOptions = {
    var options = SymbolPrintOptions.default
    options.remove(.displayObjCModule)
    options.insert(.synthesizeSugarOnTypes)
    options.remove(.displayWhereClauses)
    options.remove(.displayExtensionContexts)
    return options
}()
