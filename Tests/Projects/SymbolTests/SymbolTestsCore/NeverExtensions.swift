extension Never: Protocols.ProtocolTest {
    public typealias Body = Never
    public var body: Body { fatalError() }
}

extension Never: @retroactive IteratorProtocol {
    public typealias Element = Never
    public mutating func next() -> Element? {
        fatalError()
    }
}

extension Never: @retroactive Sequence {
    public typealias Iterator = Never

    public func makeIterator() -> Iterator {
        fatalError()
    }
}
