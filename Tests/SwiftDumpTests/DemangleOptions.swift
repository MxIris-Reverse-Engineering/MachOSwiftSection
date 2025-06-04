import Foundation
import MachOSwiftSection
import SwiftDump

let printOptions: DemangleOptions = {
    var options = DemangleOptions.default
    options.remove(.displayObjCModule)
    options.insert(.synthesizeSugarOnTypes)
    options.remove(.displayWhereClauses)
    options.remove(.displayExtensionContexts)
    options.remove(.showPrivateDiscriminators)
    return options
}()
