@attached(peer, names: suffixed(Field))
@attached(member, names: named(offset), named(pointer))
@attached(extension, names: named(offset), named(pointer))
public macro Layout() = #externalMacro(module: "SwiftSectionMacros", type: "LayoutMacro")
