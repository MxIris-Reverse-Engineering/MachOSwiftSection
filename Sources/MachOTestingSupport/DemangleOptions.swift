import Foundation
import MachOSwiftSection
import SwiftDump

extension DemangleOptions {
    static let test: DemangleOptions = {
        var options = DemangleOptions.default
        options.remove(.displayObjCModule)
        options.insert(.synthesizeSugarOnTypes)
        options.remove(.displayWhereClauses)
        options.remove(.displayExtensionContexts)
        options.remove(.showPrivateDiscriminators)
        options.remove(.showModuleInDependentMemberType)
        return options
    }()
}
