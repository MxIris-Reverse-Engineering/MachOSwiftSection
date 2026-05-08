#if os(macOS)

import Foundation
import Testing
import APINotes
@testable import TypeIndexing

struct APINotesManagerTests {
    @Test func index() async throws {
        let indexer = SDKIndexer(platform: .macOS, options: [.indexAPINotesFiles])
        try await indexer.index()
        for apiNotesFile in indexer.apiNotesFiles {
            let module = try Module(contentsOf: .init(filePath: apiNotesFile.path))
            if let classes = module.classes {
                for cls in classes {
                    if let swiftName = cls.swiftName, cls.isSwiftPrivate.orFalse == false {
                        print("-----")
                        print("Class Name: \(cls.name)")
                        print("Class SwiftName: \(swiftName)")
                    }
                }
            }
            if let protocols = module.protocols {
                for proto in protocols {
                    if let swiftName = proto.swiftName, proto.isSwiftPrivate.orFalse == false {
                        print("-----")
                        print("Protocol Name: \(proto.name)")
                        print("Protocol SwiftName: \(swiftName)")
                    }
                }
            }
        }
    }
}

extension Bool? {
    var orFalse: Bool { self ?? false }
}


#endif

