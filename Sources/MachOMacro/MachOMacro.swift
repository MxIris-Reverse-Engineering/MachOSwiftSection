@attached(member, names: named(offset))
@attached(peer, names: suffixed(Field))
@attached(extension, names: named(offset))
public macro Layout() = #externalMacro(module: "MachOMacroPlugin", type: "LayoutMacro")

@attached(peer, names: arbitrary)
public macro MachOImageGenerator() = #externalMacro(module: "MachOMacroPlugin", type: "MachOImageGeneratorMacro")

@attached(member, names: arbitrary)
public macro MachOImageAllMembersGenerator() = #externalMacro(module: "MachOMacroPlugin", type: "MachOImageAllMembersGeneratorMacro")
