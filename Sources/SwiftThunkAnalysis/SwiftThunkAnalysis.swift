/// `SwiftThunkAnalysis` — recovering a kind-9 accessor-function symbolic
/// reference's answer without running the thunk.
///
/// Evolution proposal `offline-opaque-accessor-thunk-resolution`.
///
/// ## Why this is a target of its own
///
/// When a mangled name would use a feature the deployment target's runtime
/// demangler does not know — or, in SwiftUI's case, when an opaque result type
/// is *availability-conditional* (SE-0360, `if #available` returning different
/// types) — IRGen does not embed a type name at all. It embeds `0x09` plus a
/// relative pointer to a metadata accessor thunk, and the runtime calls that
/// function instead of demangling. Offline that leaves a raw address where a
/// type belongs.
///
/// Reading the answer back means decoding the thunk's instructions, which
/// needs a disassembler. That is the only thing in this package that does, so
/// it lives behind the `ThunkAnalysis` trait rather than in the rendering
/// layer: a host that does not ask for it compiles no Capstone, and this
/// module builds empty.
///
/// ## Direction of the dependency
///
/// `SwiftDeclarationRendering` does **not** depend on this target. It declares
/// the `AccessorThunkResolving` seam; this target implements it and registers
/// the implementation. Inverting that would make the disassembler
/// unconditional for everyone.
#if THUNK_ANALYSIS

// Implementation lands here.

#endif
