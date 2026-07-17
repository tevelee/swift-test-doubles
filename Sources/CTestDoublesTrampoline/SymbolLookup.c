#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "TestDoublesTrampoline.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#if defined(__APPLE__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif
#endif

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
  int exactOnly;
  int found;
} TDSymbolLookup;

typedef struct TDNamedSymbolLookup {
  const char *name;
  size_t nameLength;
  const void *address;
} TDNamedSymbolLookup;

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
      if (!exact && (lookup->exactOnly || !enclosed)) {
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

static int td_lookup_symbol_address_in_image(struct dl_phdr_info *image,
                                             size_t imageInfoSize,
                                             void *context) {
  (void)imageInfoSize;
  TDNamedSymbolLookup *lookup = context;
  const char *path = image->dlpi_name;
  if (!path || path[0] == '\0') {
    path = "/proc/self/exe";
  }
  FILE *file = fopen(path, "rb");
  if (!file) {
    return 0;
  }

  ElfW(Ehdr) header;
  if (!td_read_file(file, 0, &header, sizeof(header)) ||
      memcmp(header.e_ident, ELFMAG, SELFMAG) != 0 ||
      header.e_shentsize != sizeof(ElfW(Shdr))) {
    fclose(file);
    return 0;
  }

  size_t sectionsSize = (size_t)header.e_shnum * sizeof(ElfW(Shdr));
  ElfW(Shdr) *sections = malloc(sectionsSize);
  if (!sections || !td_read_file(file, header.e_shoff, sections, sectionsSize)) {
    free(sections);
    fclose(file);
    return 0;
  }

  for (ElfW(Half) sectionIndex = 0; sectionIndex < header.e_shnum;
       sectionIndex++) {
    const ElfW(Shdr) *symbolSection = &sections[sectionIndex];
    if ((symbolSection->sh_type != SHT_SYMTAB &&
         symbolSection->sh_type != SHT_DYNSYM) ||
        symbolSection->sh_entsize != sizeof(ElfW(Sym)) ||
        symbolSection->sh_link >= header.e_shnum) {
      continue;
    }
    const ElfW(Shdr) *stringSection = &sections[symbolSection->sh_link];
    ElfW(Sym) *symbols = malloc(symbolSection->sh_size);
    char *strings = malloc(stringSection->sh_size);
    if (!symbols || !strings ||
        !td_read_file(file, symbolSection->sh_offset, symbols,
                      symbolSection->sh_size) ||
        !td_read_file(file, stringSection->sh_offset, strings,
                      stringSection->sh_size)) {
      free(symbols);
      free(strings);
      continue;
    }

    size_t symbolCount = symbolSection->sh_size / sizeof(ElfW(Sym));
    for (size_t symbolIndex = 0; symbolIndex < symbolCount; symbolIndex++) {
      const ElfW(Sym) *symbol = &symbols[symbolIndex];
      if (symbol->st_name >= stringSection->sh_size || symbol->st_value == 0 ||
          symbol->st_shndx == SHN_UNDEF) {
        continue;
      }
      size_t remaining = stringSection->sh_size - symbol->st_name;
      const char *name = strings + symbol->st_name;
      if (lookup->nameLength >= remaining ||
          memcmp(name, lookup->name, lookup->nameLength) != 0 ||
          name[lookup->nameLength] != '\0') {
        continue;
      }
      uintptr_t address = symbol->st_value;
      if (symbol->st_shndx != SHN_ABS) {
        address += image->dlpi_addr;
      }
      lookup->address = (const void *)address;
      free(symbols);
      free(strings);
      free(sections);
      fclose(file);
      return 1;
    }
    free(symbols);
    free(strings);
  }

  free(sections);
  fclose(file);
  return 0;
}
#endif

#if defined(__APPLE__) && defined(__LP64__)
static void td_visit_symbols_in_image(const struct mach_header_64 *header,
                                      intptr_t slide,
                                      TDLocalSymbolVisitor visitor,
                                      void *context) {
  const struct symtab_command *symtab = 0;
  const struct segment_command_64 *linkedit = 0;
  const uint8_t *commandBytes = (const uint8_t *)(header + 1);
  for (uint32_t index = 0; index < header->ncmds; index++) {
    const struct load_command *command =
        (const struct load_command *)commandBytes;
    if (command->cmd == LC_SYMTAB) {
      symtab = (const struct symtab_command *)command;
    } else if (command->cmd == LC_SEGMENT_64) {
      const struct segment_command_64 *segment =
          (const struct segment_command_64 *)command;
      if (strcmp(segment->segname, SEG_LINKEDIT) == 0) {
        linkedit = segment;
      }
    }
    commandBytes += command->cmdsize;
  }
  if (!symtab || !linkedit) {
    return;
  }

  uintptr_t linkeditBase = (uintptr_t)slide + linkedit->vmaddr -
                           linkedit->fileoff;
  const struct nlist_64 *symbols =
      (const struct nlist_64 *)(linkeditBase + symtab->symoff);
  const char *strings = (const char *)(linkeditBase + symtab->stroff);
  for (uint32_t index = 0; index < symtab->nsyms; index++) {
    const struct nlist_64 *symbol = &symbols[index];
    if (symbol->n_un.n_strx == 0 || symbol->n_value == 0 ||
        (symbol->n_type & N_STAB) != 0 ||
        (symbol->n_type & N_TYPE) != N_SECT) {
      continue;
    }
    const char *name = strings + symbol->n_un.n_strx;
    if (!name[0]) {
      continue;
    }
    if (strstr(name, "TRTA") &&
        !visitor(name, (const void *)((uintptr_t)slide + symbol->n_value),
                 context)) {
      return;
    }
  }
}
#endif

#if defined(__linux__)
typedef struct TDLocalSymbolVisit {
  TDLocalSymbolVisitor visitor;
  void *context;
  int shouldContinue;
} TDLocalSymbolVisit;

static int td_visit_symbols_in_elf_image(struct dl_phdr_info *image,
                                         size_t imageInfoSize,
                                         void *rawVisit) {
  (void)imageInfoSize;
  TDLocalSymbolVisit *visit = rawVisit;
  const char *path = image->dlpi_name;
  if (!path || path[0] == '\0') {
    path = "/proc/self/exe";
  }
  FILE *file = fopen(path, "rb");
  if (!file) {
    return 0;
  }

  ElfW(Ehdr) header;
  if (!td_read_file(file, 0, &header, sizeof(header)) ||
      memcmp(header.e_ident, ELFMAG, SELFMAG) != 0 ||
      header.e_shentsize != sizeof(ElfW(Shdr))) {
    fclose(file);
    return 0;
  }
  size_t sectionsSize = (size_t)header.e_shnum * sizeof(ElfW(Shdr));
  ElfW(Shdr) *sections = malloc(sectionsSize);
  if (!sections || !td_read_file(file, header.e_shoff, sections, sectionsSize)) {
    free(sections);
    fclose(file);
    return 0;
  }

  for (ElfW(Half) sectionIndex = 0;
       sectionIndex < header.e_shnum && visit->shouldContinue;
       sectionIndex++) {
    const ElfW(Shdr) *symbolSection = &sections[sectionIndex];
    if ((symbolSection->sh_type != SHT_SYMTAB &&
         symbolSection->sh_type != SHT_DYNSYM) ||
        symbolSection->sh_entsize != sizeof(ElfW(Sym)) ||
        symbolSection->sh_link >= header.e_shnum) {
      continue;
    }
    const ElfW(Shdr) *stringSection = &sections[symbolSection->sh_link];
    ElfW(Sym) *symbols = malloc(symbolSection->sh_size);
    char *strings = malloc(stringSection->sh_size);
    if (!symbols || !strings ||
        !td_read_file(file, symbolSection->sh_offset, symbols,
                      symbolSection->sh_size) ||
        !td_read_file(file, stringSection->sh_offset, strings,
                      stringSection->sh_size)) {
      free(symbols);
      free(strings);
      continue;
    }
    size_t symbolCount = symbolSection->sh_size / sizeof(ElfW(Sym));
    for (size_t symbolIndex = 0;
         symbolIndex < symbolCount && visit->shouldContinue;
         symbolIndex++) {
      const ElfW(Sym) *symbol = &symbols[symbolIndex];
      if (symbol->st_name >= stringSection->sh_size || symbol->st_value == 0 ||
          symbol->st_shndx == SHN_UNDEF) {
        continue;
      }
      const char *name = strings + symbol->st_name;
      if (name[0] && strstr(name, "TRTA")) {
        visit->shouldContinue = visit->visitor(
            name, (const void *)(image->dlpi_addr + symbol->st_value),
            visit->context);
      }
    }
    free(symbols);
    free(strings);
  }
  free(sections);
  fclose(file);
  return visit->shouldContinue ? 0 : 1;
}
#endif

static const char *td_lookup_symbol_name(const void *address, int exactOnly) {
  if (!address) {
    return 0;
  }

  Dl_info info;
  if (dladdr(address, &info) != 0 && info.dli_sname &&
      (!exactOnly || info.dli_saddr == address)) {
    return info.dli_sname;
  }

#if defined(__linux__)
  static _Thread_local char name[4096];
  TDSymbolLookup lookup = {
      .address = (uintptr_t)address,
      .name = name,
      .capacity = sizeof(name),
      .exactOnly = exactOnly,
      .found = 0,
  };
  dl_iterate_phdr(td_lookup_symbol_in_image, &lookup);
  return lookup.found ? name : 0;
#else
  return 0;
#endif
}

const char *td_symbol_name(const void *address) {
  return td_lookup_symbol_name(address, 0);
}

const char *td_exact_symbol_name(const void *address) {
  return td_lookup_symbol_name(address, 1);
}

const void *td_symbol_address(const char *name) {
  if (!name || name[0] == '\0') {
    return 0;
  }
  const void *address = dlsym(RTLD_DEFAULT, name);
  if (address) {
    return address;
  }
#if defined(__linux__)
  TDNamedSymbolLookup lookup = {
      .name = name,
      .nameLength = strlen(name),
      .address = 0,
  };
  dl_iterate_phdr(td_lookup_symbol_address_in_image, &lookup);
  return lookup.address;
#else
  return 0;
#endif
}

void td_visit_local_symbols(TDLocalSymbolVisitor visitor, void *context) {
  if (!visitor) {
    return;
  }
#if defined(__APPLE__) && defined(__LP64__)
  uint32_t imageCount = _dyld_image_count();
  for (uint32_t index = 0; index < imageCount; index++) {
    const struct mach_header *header = _dyld_get_image_header(index);
    if (header && header->magic == MH_MAGIC_64) {
      td_visit_symbols_in_image((const struct mach_header_64 *)header,
                                _dyld_get_image_vmaddr_slide(index), visitor,
                                context);
    }
  }
#elif defined(__linux__)
  TDLocalSymbolVisit visit = {
      .visitor = visitor,
      .context = context,
      .shouldContinue = 1,
  };
  dl_iterate_phdr(td_visit_symbols_in_elf_image, &visit);
#else
  (void)context;
#endif
}

const void *td_sign_function_pointer(const void *pointer,
                                     uint16_t discriminator) {
#if defined(__APPLE__) && __has_feature(ptrauth_calls)
  return ptrauth_sign_unauthenticated(pointer, ptrauth_key_function_pointer,
                                      discriminator);
#else
  (void)discriminator;
  return pointer;
#endif
}

const void *td_sign_async_function_pointer(const void *pointer,
                                           uint16_t discriminator) {
#if defined(__APPLE__) && __has_feature(ptrauth_calls)
  return ptrauth_sign_unauthenticated(
      pointer, ptrauth_key_process_dependent_data, discriminator);
#else
  (void)discriminator;
  return pointer;
#endif
}

static uint64_t td_rotate_left(uint64_t value, unsigned count) {
  return (value << count) | (value >> (64 - count));
}

static void td_sip_round(uint64_t *v0, uint64_t *v1, uint64_t *v2,
                         uint64_t *v3) {
  *v0 += *v1;
  *v1 = td_rotate_left(*v1, 13);
  *v1 ^= *v0;
  *v0 = td_rotate_left(*v0, 32);
  *v2 += *v3;
  *v3 = td_rotate_left(*v3, 16);
  *v3 ^= *v2;
  *v0 += *v3;
  *v3 = td_rotate_left(*v3, 21);
  *v3 ^= *v0;
  *v2 += *v1;
  *v1 = td_rotate_left(*v1, 17);
  *v1 ^= *v2;
  *v2 = td_rotate_left(*v2, 32);
}

static uint64_t td_load_little_endian64(const uint8_t *bytes) {
  uint64_t value = 0;
  for (unsigned index = 0; index < 8; index++) {
    value |= (uint64_t)bytes[index] << (index * 8);
  }
  return value;
}

static uint64_t td_stable_sip_hash(const uint8_t *bytes, size_t length) {
  static const uint8_t key[16] = {
      0xb5, 0xd4, 0xc9, 0xeb, 0x79, 0x10, 0x4a, 0x79,
      0x6f, 0xec, 0x8b, 0x1b, 0x42, 0x87, 0x81, 0xd4,
  };
  uint64_t k0 = td_load_little_endian64(key);
  uint64_t k1 = td_load_little_endian64(key + 8);
  uint64_t v0 = UINT64_C(0x736f6d6570736575) ^ k0;
  uint64_t v1 = UINT64_C(0x646f72616e646f6d) ^ k1;
  uint64_t v2 = UINT64_C(0x6c7967656e657261) ^ k0;
  uint64_t v3 = UINT64_C(0x7465646279746573) ^ k1;
  size_t offset = 0;
  while (offset + 8 <= length) {
    uint64_t message = td_load_little_endian64(bytes + offset);
    v3 ^= message;
    td_sip_round(&v0, &v1, &v2, &v3);
    td_sip_round(&v0, &v1, &v2, &v3);
    v0 ^= message;
    offset += 8;
  }
  uint64_t tail = (uint64_t)length << 56;
  for (size_t index = 0; offset + index < length; index++) {
    tail |= (uint64_t)bytes[offset + index] << (index * 8);
  }
  v3 ^= tail;
  td_sip_round(&v0, &v1, &v2, &v3);
  td_sip_round(&v0, &v1, &v2, &v3);
  v0 ^= tail;
  v2 ^= 0xff;
  for (unsigned index = 0; index < 4; index++) {
    td_sip_round(&v0, &v1, &v2, &v3);
  }
  return v0 ^ v1 ^ v2 ^ v3;
}

uint16_t td_generic_function_discriminator(uint16_t parameterCount,
                                           bool hasResult) {
  char spelling[4096];
  int length = snprintf(spelling, sizeof(spelling), "function:%u:",
                        parameterCount);
  if (length < 0 || (size_t)length >= sizeof(spelling)) {
    return 0;
  }
  for (uint16_t index = 0; index < parameterCount; index++) {
    int written = snprintf(spelling + length, sizeof(spelling) - (size_t)length,
                           "-indirect:");
    if (written < 0 || (size_t)written >= sizeof(spelling) - (size_t)length) {
      return 0;
    }
    length += written;
  }
  int written = snprintf(spelling + length, sizeof(spelling) - (size_t)length,
                         "%u:", hasResult ? 1 : 0);
  if (written < 0 || (size_t)written >= sizeof(spelling) - (size_t)length) {
    return 0;
  }
  length += written;
  if (hasResult) {
    written = snprintf(spelling + length, sizeof(spelling) - (size_t)length,
                       "-indirect:");
    if (written < 0 || (size_t)written >= sizeof(spelling) - (size_t)length) {
      return 0;
    }
    length += written;
  }
  uint64_t hash = td_stable_sip_hash((const uint8_t *)spelling, (size_t)length);
  return (uint16_t)(hash % UINT16_MAX) + 1;
}

uint16_t td_function_discriminator(const uint8_t *spelling, size_t length) {
  if (!spelling) {
    return 0;
  }
  uint64_t hash = td_stable_sip_hash(spelling, length);
  return (uint16_t)(hash % UINT16_MAX) + 1;
}
