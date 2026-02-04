# Compton-TDE Optimized Build

This is an optimized build of the compton compositor for Trinity Desktop Environment (TDE).

## Optimization Strategy

Aggressive but still safe build flags to achieve a binary that is both **faster** and **smaller** than the stock TDE build.

### Compilation Flags
*   **`-O2`**: Used as the stable base (standard TDE uses this, keping it to avoid `-O3` code bloat).
*   **`-flto`** (Target specific): Link Time Optimization. Enabling this allows the compiler to optimize across translation units, inlining functions where appropriate and reducing final binary size.
*   **`-ffast-math`**: Enables aggressive floating-point optimizations. This improves performance for shadow and fade calculations which rely heavily on math operations.
*   **`-fvisibility=hidden`**: Hides internal symbols, reducing the dynamic symbol table size and improving load times.

### Linker Optimizations
*   **`-Wl,--gc-sections`**: Garbage Collect Sections. Combined with `-fdata-sections -ffunction-sections`, this removes any code or data that is not actually used by the application, significantly reducing binary size.
*   **`sstrip`**: Using `sstrip` (super-strip) instead of standard `strip` removes absolutely everything from the ELF binary that isn't strictly required for execution (section headers, etc.), shaving off the last few kilobytes.

### Fixes & Features
*   **OpenGL Backend**: Explicitly enabled (`-DWITH_OPENGL=ON`) to ensure hardware acceleration is available.
*   **Bug Fix**: Patched a critical `use-after-free` crash in `c2.c` (legacy TDE bug I think).
    *   *Issue*: The original code freed a string (`tstr`) and then immediately accessed it for validity checks, leading to potential crashes during config parsing.
    *   *Fix*: Reordered the logic to ensure the string is only freed *after* it has been used. This improves stability, especially with complex configurations.
*   **Regex Support**: Enabled PCRE2 for advanced window matching rules.

## Results
*   **Binary Size**: ~160KB (Optimized)
*   **Package Size**: ~60KB (.deb)

## Build Instructions
To reproduce this build:
```bash
cmake . -DWITH_LIBCONFIG=ON -DWITH_OPENGL=ON -DWITH_PCRE2=ON -DWITH_XRENDER=ON -DWITH_XFIXES=ON -DWITH_XCOMPOSITE=ON -DWITH_XDAMAGE=ON
make compton-tde
./create_deb.sh
```
