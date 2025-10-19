@attached(member, names: arbitrary)
package macro CaseCheckable(
    _ access: AccessLevel? = nil
) = #externalMacro(
    module: "MachOMacros",
    type: "CaseCheckableMacro"
)
