#pragma once

/// A minimal C++ foreign reference type, matching the shape verified in
/// CXX_FOREIGN_REFERENCE_FEASIBILITY.md: immortal so this header alone needs
/// no companion retain/release implementation.
class __attribute__((swift_attr("import_reference")))
      __attribute__((swift_attr("retain:immortal")))
      __attribute__((swift_attr("release:immortal")))
Widget {
public:
  int value() const { return 42; }
};
