import ArgumentParser
import MachOKit

enum Architecture: String, ExpressibleByArgument, CaseIterable {
    case x86_64
    case arm64
    case arm64e

    var cpu: CPUSubType {
        switch self {
        case .x86_64:
            return .x86(.x86_64_all)
        case .arm64:
            return .arm64(.arm64_all)
        case .arm64e:
            return .arm64(.arm64e)
        }
    }
}
