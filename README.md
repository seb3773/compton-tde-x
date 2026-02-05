# Compton-TDE Optimized Standalone Build

This is a **standalone, optimized build** of the compton compositor for Trinity Desktop Environment (TDE).
It has been decoupled from the core TDE build system to ensure portability across different Trinity versions and Linux distributions.

## Key Features

*   **Standalone Build**: Uses a standard `CMakeLists.txt` that depends only on system libraries (X11, OpenGL, libconfig, etc.), not on TDE internal macros. This ensures it compiles on any machine with the required dev packages.
*   **Portability**: Automatically detects the version of `libconfig` (legacy vs modern) and adapts the source code accordingly.
*   **Size Optimization**: 
    - Hardcoded aggressive optimization flags (`-O2`, `-flto`, `-fvisibility=hidden`, etc.) to minimize binary size.
    - Stripped section headers (requires `sstrip` or standard `strip`) to achieve a binary size of **~175KB** (vs ~250KB stock).
*   **Silent Build**: Optional `-DWITH_SILENT_BUILD=ON` flag to remove all console logging strings, saving ~20KB.
*   **Code Optimization**:
    - **Region Cache**: Implemented a stack-based cache for `XFixesCreateRegion` to reduce X server round-trips.
    - **Picture Format Cache**: Cached `XRenderFindVisualFormat` lookups for hot paths, reducing function call overhead.
    - **Disable Debug Logging**: Configured `printf_dbg` to compile to no-ops when not debugging.
    - **Compiler Hints**: Added `HOT`/`COLD` attributes and `likely`/`unlikely` branch prediction hints.
    - **Structure Packing**: Reordered `struct _win` members to eliminate padding, improving cache testing.
    - **Data Types**: Switched to `float` for shadow convolution and `uint16_t` for coordinates to reduce memory usage.
    - **Code Refactoring**: Implemented generic `FREE` macros and merged duplicate window property update functions to reduce binary size.
*   **Configuration**: Full support for `libconfig` parsing and PCRE2 regex is included.
*   **OpenGL Backend**: Explicitly enabled (`-DWITH_OPENGL=ON`) to ensure hardware acceleration is available.
*   **Bug Fix**: Patched a critical `use-after-free` crash in `c2.c` (legacy TDE bug I think).
    *   *Issue*: The original code freed a string (`tstr`) and then immediately accessed it for validity checks, leading to potential crashes during config parsing.
    *   *Fix*: Reordered the logic to ensure the string is only freed *after* it has been used. This improves stability, especially with complex configurations.

## Requirements

Ensure you have the development packages for:
*   X11 (libX11, libXcomposite, libXdamage, libXrender, libXfixes, libXrandr, libXinerama, libXext)
*   OpenGL (libGL)
*   PkgConfig
*   **libconfig-dev** (Required for config file support)
*   **dbus-1-dev**
*   **libpcre2-dev**

## Build Instructions

1.  **Configure**:
    Run cmake. You can enable/disable features using `-DWITH_...`.
    The build is configured to strictly require features like `libconfig` by default.

    ```bash
    cmake . -DWITH_LIBCONFIG=ON -DWITH_OPENGL=ON -DWITH_PCRE2=ON \
            -DWITH_XRENDER=ON -DWITH_XFIXES=ON -DWITH_XCOMPOSITE=ON \
            -DWITH_XDAMAGE=ON
    ```

    *Optimization flags are automatically applied by the CMake configuration.*

2.  **Build**:
    ```bash
    make compton-tde
    ```

3.  **Optimize Size (Optional but Recommended)**:
    If you have `sstrip` installed (from `elfkickers`):
    ```bash
    sstrip compton-tde
    ```
    Otherwise use standard strip:
    ```bash
    strip --strip-all compton-tde
    ```

4.  **Install**:
    ```bash
    sudo make install
    # OR manually copy compton-tde to your bin path
    ```

## Packaging

To create a Debian package (`.deb`):

1.  **Build the project first** (follow the instructions above). The binary `compton-tde` must exist.
2.  Run the packaging script:
    ```bash
    ./create_deb.sh
    ```
    This will generate a `.deb` package in the current directory (e.g., `compton-tde_1.0_amd64.deb`).

## Cleanup

To clean up all build artifacts (recommended before committing to git):

```bash
make clean
rm -rf CMakeFiles CMakeCache.txt cmake_install.cmake Makefile compton_config.h package_build
```
