import Foundation

extension Data {
    func rawValue() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
