#pragma once

// A minimal, immortal C++ foreign reference type.
class __attribute__((swift_attr("import_reference")))
      __attribute__((swift_attr("retain:immortal")))
      __attribute__((swift_attr("release:immortal")))
Widget {
public:
  int value() const { return value_; }
  void setValue(int value) { value_ = value; }

private:
  int value_ = 42;
};
