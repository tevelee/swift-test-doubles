#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "TestDoublesTrampoline.h"

#if defined(__APPLE__)
#include <mach/mach.h>
#elif defined(__linux__)
#include <sys/uio.h>
#include <unistd.h>
#endif

bool td_read_process_memory(const void *source,
                            void *destination,
                            size_t byteCount) {
  if (byteCount == 0) {
    return true;
  }
  if (source == NULL || destination == NULL) {
    return false;
  }

#if defined(__APPLE__)
  vm_size_t copied = 0;
  kern_return_t result = vm_read_overwrite(
      mach_task_self(), (vm_address_t)(uintptr_t)source, (vm_size_t)byteCount,
      (vm_address_t)(uintptr_t)destination, &copied);
  return result == KERN_SUCCESS && copied == byteCount;
#elif defined(__linux__)
  struct iovec local = {.iov_base = destination, .iov_len = byteCount};
  struct iovec remote = {
      .iov_base = (void *)(uintptr_t)source,
      .iov_len = byteCount,
  };
  ssize_t copied = process_vm_readv(getpid(), &local, 1, &remote, 1, 0);
  return copied >= 0 && (size_t)copied == byteCount;
#else
  (void)source;
  (void)destination;
  return false;
#endif
}

void td_scrub_argument_registers(uintptr_t gp0,
                                 uintptr_t gp1,
                                 uintptr_t gp2,
                                 uintptr_t gp3,
                                 uintptr_t gp4,
                                 uintptr_t gp5,
                                 uintptr_t gp6,
                                 uintptr_t gp7,
                                 double fp0,
                                 double fp1,
                                 double fp2,
                                 double fp3,
                                 double fp4,
                                 double fp5,
                                 double fp6,
                                 double fp7) {
  (void)gp0;
  (void)gp1;
  (void)gp2;
  (void)gp3;
  (void)gp4;
  (void)gp5;
  (void)gp6;
  (void)gp7;
  (void)fp0;
  (void)fp1;
  (void)fp2;
  (void)fp3;
  (void)fp4;
  (void)fp5;
  (void)fp6;
  (void)fp7;
}
