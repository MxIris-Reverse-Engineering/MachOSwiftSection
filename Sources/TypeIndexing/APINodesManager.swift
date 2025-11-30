#if os(macOS)

import Foundation
import APINotes
import FoundationToolbox

@available(macOS 13.0, *)
final class APINotesManager: Sendable {
    
    struct Name: Sendable {
        let moduleName: String
        let name: String
    }
    
    @Mutex
    private(set) var files: [APINotesFile] = []

    @Mutex
    private(set) var cNameToSwiftName: [String: Name] = [:]

    @Mutex
    private(set) var swiftNameToCName: [String: Name] = [:]
    
    init() {}

    func addFiles(_ newFiles: [APINotesFile]) {
        files.append(contentsOf: newFiles)
    }

    func clear() {
        files.removeAll()
        cNameToSwiftName.removeAll()
    }

    func swiftName(forCName cName: String) -> Name? {
        cNameToSwiftName[cName]
    }

    func cName(forSwiftName swiftName: String) -> Name? {
        swiftNameToCName[swiftName]
    }
    
    func index() {
        for file in files {
            let module = file.apiNotesModule
            setNames(for: module.classes, in: file.moduleName)
            setNames(for: module.protocols, in: file.moduleName)
            setNames(for: module.tags, in: file.moduleName)
            setNames(for: module.enumerators, in: file.moduleName)
            setNames(for: module.typedefs, in: file.moduleName)
        }
    }

    private func setNames(for entities: [CommonEntity]?, in moduleName: String) {
        guard let entities else { return }
        for entity in entities {
            guard let swiftName = entity.swiftName, entity.isSwiftPrivate.orFalse == false else {
                continue
            }
            let cName = entity.name
            cNameToSwiftName[cName] = .init(moduleName: swiftName, name: swiftName)
            swiftNameToCName[swiftName] = .init(moduleName: moduleName, name: cName)
        }
    }
}

extension Bool? {
    var orFalse: Bool { self ?? false }
}


#endif
