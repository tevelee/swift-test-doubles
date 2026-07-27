// `Widget` is defined entirely in the header (see include/Widget.h) since
// its methods are inline. This translation unit exists only so the target
// has a real source file: Xcode's build system (unlike plain `swift build`)
// requires an actual compiled object file per target, even when everything
// the target declares is header-only.
