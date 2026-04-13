import Foundation

public enum ErrorTypes {
    public enum SimpleErrorTest: Error {
        case notFound
        case invalid
        case unknown
    }

    public enum AssociatedValueErrorTest: Error {
        case withMessage(String)
        case withCode(Int)
        case withContext(message: String, code: Int, underlying: (any Error)?)
    }

    public struct LocalizedErrorTest: LocalizedError {
        public let errorDescription: String?
        public let failureReason: String?
        public let recoverySuggestion: String?
        public let helpAnchor: String?

        public init(description: String, reason: String, suggestion: String, helpAnchor: String) {
            self.errorDescription = description
            self.failureReason = reason
            self.recoverySuggestion = suggestion
            self.helpAnchor = helpAnchor
        }
    }

    public struct CustomNSErrorTest: CustomNSError {
        public static let errorDomain: String = "com.test.CustomNSErrorTest"
        public let errorCode: Int
        public let errorUserInfo: [String: Any]

        public init(errorCode: Int, errorUserInfo: [String: Any]) {
            self.errorCode = errorCode
            self.errorUserInfo = errorUserInfo
        }
    }

    public struct SendableErrorTest: Error, Sendable {
        public let identifier: Int
        public let descriptionText: String

        public init(identifier: Int, descriptionText: String) {
            self.identifier = identifier
            self.descriptionText = descriptionText
        }
    }
}
