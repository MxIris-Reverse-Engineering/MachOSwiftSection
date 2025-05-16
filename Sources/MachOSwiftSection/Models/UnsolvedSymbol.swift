import Foundation

public struct UnsolvedSymbol {
    public let offset: Int
    
    public let stringValue: String
    
    public init(offset: Int, stringValue: String) {
        self.offset = offset
        self.stringValue = stringValue
    }
}
