#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "TestDoublesTrampoline.h"

#include <dlfcn.h>

#if defined(__linux__)
#include <elf.h>
#include <link.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct TDSymbolLookup {
  uintptr_t address;
  char *name;
  size_t capacity;
  int found;
} TDSymbolLookup;

static int td_read_file(FILE *file, ElfW(Off) offset, void *buffer, size_t size) {
  return fseek(file, (long)offset, SEEK_SET) == 0 &&
         fread(buffer, 1, size, file) == size;
}

static int td_lookup_symbol_in_image(struct dl_phdr_info *image,
                                     size_t imageInfoSize,
                                     void *context) {
  (void)imageInfoSize;
  TDSymbolLookup *lookup = context;
  int containsAddress = 0;
  for (ElfW(Half) index = 0; index < image->dlpi_phnum; index++) {
    const ElfW(Phdr) *segment = &image->dlpi_phdr[index];
    if (segment->p_type != PT_LOAD) {
      continue;
    }
    uintptr_t start = image->dlpi_addr + segment->p_vaddr;
    uintptr_t end = start + segment->p_memsz;
    if (lookup->address >= start && lookup->address < end) {
      containsAddress = 1;
      break;
    }
  }
  if (!containsAddress) {
    return 0;
  }

  const char *path = image->dlpi_name;
  if (!path || path[0] == '\0') {
    path = "/proc/self/exe";
  }
  FILE *file = fopen(path, "rb");
  if (!file) {
    return 1;
  }

  ElfW(Ehdr) header;
  if (!td_read_file(file, 0, &header, sizeof(header)) ||
      memcmp(header.e_ident, ELFMAG, SELFMAG) != 0 ||
      header.e_shentsize != sizeof(ElfW(Shdr))) {
    fclose(file);
    return 1;
  }

  size_t sectionsSize = (size_t)header.e_shnum * sizeof(ElfW(Shdr));
  ElfW(Shdr) *sections = malloc(sectionsSize);
  if (!sections ||
      !td_read_file(file, header.e_shoff, sections, sectionsSize)) {
    free(sections);
    fclose(file);
    return 1;
  }

  int bestScore = 0;
  for (ElfW(Half) sectionIndex = 0;
       sectionIndex < header.e_shnum;
       sectionIndex++) {
    const ElfW(Shdr) *symbolSection = &sections[sectionIndex];
    if (symbolSection->sh_type != SHT_SYMTAB ||
        symbolSection->sh_entsize != sizeof(ElfW(Sym)) ||
        symbolSection->sh_link >= header.e_shnum) {
      continue;
    }

    const ElfW(Shdr) *stringSection = &sections[symbolSection->sh_link];
    ElfW(Sym) *symbols = malloc(symbolSection->sh_size);
    char *strings = malloc(stringSection->sh_size);
    if (!symbols || !strings ||
        !td_read_file(file, symbolSection->sh_offset,
                      symbols, symbolSection->sh_size) ||
        !td_read_file(file, stringSection->sh_offset,
                      strings, stringSection->sh_size)) {
      free(symbols);
      free(strings);
      continue;
    }

    size_t symbolCount = symbolSection->sh_size / sizeof(ElfW(Sym));
    for (size_t symbolIndex = 0; symbolIndex < symbolCount; symbolIndex++) {
      const ElfW(Sym) *symbol = &symbols[symbolIndex];
      if (symbol->st_name >= stringSection->sh_size || symbol->st_value == 0) {
        continue;
      }
      uintptr_t start = image->dlpi_addr + symbol->st_value;
      uintptr_t end = start + symbol->st_size;
      int exact = lookup->address == start;
      int enclosed = symbol->st_size > 0 &&
                     lookup->address >= start && lookup->address < end;
      if (!exact && !enclosed) {
        continue;
      }

      const char *name = strings + symbol->st_name;
      if (name[0] == '\0') {
        continue;
      }
      int score = (exact ? 2 : 1) + (strstr(name, "TW") ? 2 : 0);
      if (score > bestScore) {
        snprintf(lookup->name, lookup->capacity, "%s", name);
        lookup->found = 1;
        bestScore = score;
      }
    }

    free(symbols);
    free(strings);
  }

  free(sections);
  fclose(file);
  return 1;
}
#endif

const char *td_symbol_name(const void *address) {
  if (!address) {
    return 0;
  }

  Dl_info info;
  if (dladdr(address, &info) != 0 && info.dli_sname) {
    return info.dli_sname;
  }

#if defined(__linux__)
  static _Thread_local char name[4096];
  TDSymbolLookup lookup = {
      .address = (uintptr_t)address,
      .name = name,
      .capacity = sizeof(name),
      .found = 0,
  };
  dl_iterate_phdr(td_lookup_symbol_in_image, &lookup);
  return lookup.found ? name : 0;
#else
  return 0;
#endif
}
