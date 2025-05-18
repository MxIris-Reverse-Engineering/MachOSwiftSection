import Foundation

@attached(member, names: named(offset))
@attached(peer, names: suffixed(Field))
@attached(extension, names: named(offset))
public macro Layout() = #externalMacro(module: "MachOSwiftSectionMacroPlugin", type: "LayoutMacro")
