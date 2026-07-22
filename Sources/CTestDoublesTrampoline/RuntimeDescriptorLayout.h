#ifndef TEST_DOUBLES_RUNTIME_DESCRIPTOR_LAYOUT_H
#define TEST_DOUBLES_RUNTIME_DESCRIPTOR_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

typedef struct TDAsyncFunctionPointer {
  int32_t relativeFunction;
  uint32_t expectedContextSize;
} TDAsyncFunctionPointer;

typedef struct TDCoroFunctionPointer {
  int32_t relativeFunction;
  uint32_t callerFrameSize;
  uint64_t mallocTypeID;
} TDCoroFunctionPointer;

_Static_assert(sizeof(TDAsyncFunctionPointer) == 8,
               "async function descriptor size changed");
_Static_assert(offsetof(TDAsyncFunctionPointer, relativeFunction) == 0,
               "async function descriptor relative function offset changed");
_Static_assert(offsetof(TDAsyncFunctionPointer, expectedContextSize) == 4,
               "async function descriptor context size offset changed");
_Static_assert(sizeof(TDCoroFunctionPointer) == 16,
               "coroutine function descriptor size changed");
_Static_assert(offsetof(TDCoroFunctionPointer, relativeFunction) == 0,
               "coroutine descriptor relative function offset changed");
_Static_assert(offsetof(TDCoroFunctionPointer, callerFrameSize) == 4,
               "coroutine descriptor frame size offset changed");
_Static_assert(offsetof(TDCoroFunctionPointer, mallocTypeID) == 8,
               "coroutine descriptor malloc type ID offset changed");

#endif
