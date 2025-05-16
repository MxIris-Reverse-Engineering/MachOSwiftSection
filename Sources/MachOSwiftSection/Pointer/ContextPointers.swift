import Foundation

public typealias SignedContextPointer<Context: ResolvableElement> = SignedPointer<Context>

public typealias RelativeContextPointer<Context: ResolvableElement> = RelativeIndirectablePointer<Context, SignedContextPointer<Context>>

public typealias RelativeContextPointerIntPair<Context: ResolvableElement, Integer: RawRepresentable> = RelativeIndirectablePointerIntPair<Context, Integer, SignedContextPointer<Context>> where Integer.RawValue: FixedWidthInteger
