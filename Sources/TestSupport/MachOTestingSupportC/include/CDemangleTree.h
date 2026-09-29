#ifndef CDEMANGLETREE_H
#define CDEMANGLETREE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Demangle a mangled name and return the node tree as a string.
/// Returns NULL if demangling fails. Caller must free() the result.
char * _Nullable swift_demangle_getNodeTreeAsString(
    const char * _Nonnull mangledName
);

#ifdef __cplusplus
}
#endif

#endif /* CDEMANGLETREE_H */
