#!/usr/bin/env python3
"""Inject CoreText null returns into the compiled boundary regression tests.

Build first: zig build test -Dtest-filter='CoreText boundary' -Demit-test-exe=true
Run: python3 test/coretext-null.py zig-out/bin/ghostty-test
Uses dyld interposition, so production wrappers need no test hooks.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


SHIM = r"""
#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>
#include <stdlib.h>
#include <string.h>

static int fault(const char *name) {
    const char *mode = getenv("ZASHIKI_CORETEXT_FAULT");
    return mode && strcmp(mode, name) == 0;
}
static CFStringRef display(CTFontRef font) {
    return fault("display") ? NULL : CTFontCopyDisplayName(font);
}
static CFStringRef string(CFAllocatorRef alloc, const UniChar *chars,
                         CFIndex length, CFAllocatorRef dealloc) {
    return fault("string") ? NULL : CFStringCreateWithCharactersNoCopy(
        alloc, chars, length, dealloc);
}
static CTTypesetterRef typesetter(CFAttributedStringRef str, CFDictionaryRef opts) {
    return fault("typesetter") ? NULL : CTTypesetterCreateWithAttributedStringAndOptions(str, opts);
}
static CTLineRef line(CTTypesetterRef setter, CFRange range) {
    return fault("line") ? NULL : CTTypesetterCreateLine(setter, range);
}
#define INTERPOSE(replacement, original) \
    __attribute__((used, section("__DATA,__interpose"))) \
    static const struct { const void *replace; const void *original; } \
    interpose_##replacement = { (const void *)replacement, (const void *)original };
INTERPOSE(display, CTFontCopyDisplayName)
INTERPOSE(string, CFStringCreateWithCharactersNoCopy)
INTERPOSE(typesetter, CTTypesetterCreateWithAttributedStringAndOptions)
INTERPOSE(line, CTTypesetterCreateLine)
"""


def main():
    binary = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="zashiki-coretext-null-") as tmp:
        source = Path(tmp) / "faults.c"
        library = Path(tmp) / "faults.dylib"
        source.write_text(SHIM)
        subprocess.run(
            ["xcrun", "clang", "-dynamiclib", str(source), "-o", str(library),
             "-framework", "CoreFoundation", "-framework", "CoreText"],
            check=True,
        )
        for mode in ("display", "string", "typesetter", "line"):
            print(f"CoreText null injection: {mode}", flush=True)
            env = dict(os.environ, DYLD_INSERT_LIBRARIES=str(library),
                       ZASHIKI_CORETEXT_FAULT=mode)
            subprocess.run([str(binary)], env=env, check=True, timeout=90)


if __name__ == "__main__":
    main()
