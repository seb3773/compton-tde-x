# Compton-TDE Optimized Standalone Build: compton-tde-X

This is an **optimized build** of the compton compositor for Trinity Desktop Environment (TDE).
It has been decoupled from the core TDE build system to ensure portability across different Trinity versions and Linux distributions.

## Key Features

*   **Standalone Build**: Uses a standard `CMakeLists.txt` that depends only on system libraries (X11, OpenGL, libconfig, etc.), not on TDE internal macros. This ensures it compiles on any machine with the required dev packages.
*   **Portability**: Automatically detects the version of `libconfig` (legacy vs modern) and adapts the source code accordingly.
*   **Size Optimization**: 
    - Hardcoded aggressive optimization flags (`-O2`, `-flto`, `-fvisibility=hidden`, etc.) to minimize binary size.
    - Stripped section headers (requires `sstrip` or standard `strip`) to achieve a binary size of **~175KB** (vs ~250KB stock).
*   **Silent Build**: Optional `-DWITH_SILENT_BUILD=ON` flag to remove all console logging strings, saving ~20KB.
*   **Code Optimization**:
    - **Region Cache**: Implemented a stack-based cache for `XFixesCreateRegion`, aligned to 64-byte cache lines to reduce X server round-trips.
    - **Picture Format Cache**: Cached `XRenderFindVisualFormat` lookups for hot paths, reducing function call overhead.
    - **Disable Debug Logging**: Configured `printf_dbg` to compile to no-ops when not debugging.
    - **Compiler Hints**: Added `HOT`/`COLD` attributes and `likely`/`unlikely` branch prediction hints.
    - **Structure Packing**: Reordered `struct _win` members to eliminate padding, improving cache testing.
    - **Data Types**: Switched to `float` for shadow convolution and `uint16_t` for coordinates to reduce memory usage.
    - **Code Refactoring**: Implemented generic `FREE` macros and merged duplicate window property update functions to reduce binary size.
    - **SIMD Shadows**: SSE2-vectorized `sum_gaussian` for ~4x faster shadow blur computation on large kernels.
    - **Integer Fading**: Replaced `double` arithmetic in `run_fade` with `uint64_t` to avoid FPU overhead.
    - **OpenGL Extension Caching**: Cached `glXQueryExtensionsString`/`glGetString` results to avoid repeated X calls.
    - **OpenGL Memory Leak Fix**: Fixed `get_fbconfig_from_visualinfo` leaking FBConfigs array.
    - **OpenGL Shader Build**: Optimized shader string building with cached lengths and `sprintf` return values.
    - **Monotonic Clock**: Replaced `gettimeofday` with `clock_gettime(CLOCK_MONOTONIC_COARSE)` for faster timing.
*   **Configuration**: Full support for `libconfig` parsing and PCRE2 regex is included.
*   **OpenGL Backend**: Explicitly enabled (`-DWITH_OPENGL=ON`) to ensure hardware acceleration is available.
*   **Bug Fix**: Patched a critical `use-after-free` crash in `c2.c` (legacy TDE bug I think).
    *   *Issue*: The original code freed a string (`tstr`) and then immediately accessed it for validity checks, leading to potential crashes during config parsing.
    *   *Fix*: Reordered the logic to ensure the string is only freed *after* it has been used. This improves stability, especially with complex configurations.


# Version 2.0 – Dual-Kawase Blur Support

Version 2.0 introduces the Dual-Kawase blur method for background blurring, inspired by the implementation found in [picom](https://github.com/yshui/picom).

## What is Dual-Kawase Blur?

Dual-Kawase blur is a multi-pass blur technique widely used in real-time rendering.
It works by repeatedly downscaling the source image to smaller framebuffers and then upscaling it back while applying linear sampling.
This approach provides a visually smooth and high-quality blur while being significantly more efficient than traditional Gaussian blur, especially on older or constrained GPUs.

Dual-Kawase is particularly well suited for compositors because it offers:

- Good visual quality at low sample cost
- Predictable performance
- Excellent scalability depending on blur strength and resolution

---

## Technical Notes – v2.0

### Fade Performance (Window/Menu Appear / Disappear)

Blur invocation is now conditionally controlled by `!(w->fade && w->opacity != w->opacity_tgt)`

This condition is the most reliable way to detect whether the compositor is currently animating a window.
As a result, no blur is computed during fade animations, saving a large amount of GPU resources, and the visual blur effect is still correctly applied once the fade-in completes.
(Static semi-transparent windows continue to benefit from background blur)

This avoids unnecessary blur passes during transitions while preserving visual consistency.

### CPU / VRAM Optimizations in Kawase Blur

The original implementation resized FBO textures using `glTexImage2D` on every invocation.
This has been replaced with a natural upscaling strategy: VRAM allocation only occurs when the current window size exceeds the largest previously processed size (`tw > kawase_tex_w`).
In practice, this avoids ~99% of costly GPU memory reallocations.

Additional optimizations:

- Hardware texture sampling is handled directly via `GL_LINEAR`
- Screen copies are performed natively from VRAM to VRAM using `glCopyTexSubImage2D`, this approach is about as close to the metal as you can reasonably get on OpenGL 2.x, both in terms of performance and efficiency

### Other Notes

- Buffer deallocation (`glDeleteFramebuffers`, `glDeleteTextures`, `glDeleteProgram`) in `glx_destroy_blur_kawase` is strict and executed on every configuration switch → No memory leaks detected
- All logic relies on:
  - Integer arithmetic
  - Precomputed binary-sized registers (`scale <<= 1`)
  - 1:1 mapped OpenGL floating-point operations

The result is a blur implementation that is both highly optimized and predictable in resource usage, even on older hardware.

---

## A Few Words About Compton-TDE, XDamage and Dual-Kawase

The original architecture of Compton (on which Compton-TDE is based) was designed around the X11 XDamage extension.
Compton-TDE continuously computes an `XserverRegion` (damage region, `reg_paint`). Whenever a window moves, a cursor blinks, or a menu opens, Compton only sends to the GPU the exact pixel region that has changed.
This damage-based composition model is what makes Compton-TDE extremely lightweight in terms of CPU and GPU usage.

In more recent versions of picom, an explicit option `use-damage = true/false` was introduced to allow disabling this behavior, this was necessary because some buggy graphics drivers (such as very old NVIDIA drivers or certain hybrid GPU drivers) handle region-based composition poorly and may produce visual artifacts. So, when `use-damage = false`, picom forces a full-screen redraw on every frame, regardless of the actual damaged area.
While this can be a workaround on problematic systems, it is extremely resource-hungry and strongly discouraged from a performance standpoint.

When implementing the Dual-Kawase blur method in Compton-TDE-x, it was crucial to ensure full compatibility with the compositor's native XDamage handling. The original Kawase algorithm implementations typically assume a full-screen or full-window pass, which leads to graphical artifacts like "miniature screen" effect when XDamage restricts the rendering to smaller bounding boxes like tooltips or menus. So, the rendering loop was adapted to seamlessly integrate with XDamage:

**Orthogonal Projection Mapping:** instead of dynamically altering the `glViewport` to match the size of downsampled passes, the viewport is strictly kept at the global orthogonal projection (`ps->root_width x ps->root_height`): this prevents vertex coordinates from being scaled improperly when `P_PAINTREG_START()` restricts the drawing area to a damaged sub-rectangle (`crect`).

**Dynamic Texture Coordinate Translation:** during the final upsampling pass (rendering the blurred result back to the screen), the texture coordinates (UVs) must be mathematically translated to match the damaged region offset, since XDamage passes a sub-region `crect` relative to the window bounds `(dx, dy)`, the UVs are mapped dynamically using:

```c
const GLfloat s0 = (crect.x - dx) * ((float)sw / width);
const GLfloat s1 = (crect.x + crect.width - dx) * ((float)sw / width);
```

This guarantees that the rendered `GL_QUADS` perfectly aligns the blurred texture slice with the exact physical pixels of the damaged screen area.

**Correct Bottom-Up Y-Axis Alignment:** OpenGL texture Y-coordinates (V) originate from the bottom (`V=0`), while window server coordinates originate from the top. To prevent the damaged regions from rendering the blur upside down or reading from the wrong offset, the texture V-coordinates are inverted using the formula:

```c
const GLfloat t1 = sh - (crect.y - dy) * ((float)sh / height);                  // Top V
const GLfloat t0 = sh - ((crect.y + crect.height) - dy) * ((float)sh / height);  // Bottom V
```

**VRAM-Efficient Upscale Allocation:** to prevent continuous frame-by-frame reallocation of Framebuffer Objects (FBO) when XDamage sizes fluctuate rapidly, the texture buffers (`g->kawase_textures[i]`) are sized using a "high-water mark" approach (`tw > g->kawase_tex_w[i]`). The GPU only allocates VRAM when a newly damaged window is larger than any previously blurred window, practically eliminating reallocation overhead.

For reference, here is how picom operates today compared to the implementation used in Compton-TDE-x:
Instead of patching coordinate calculations as done here, the picom developers completely rewrote the OpenGL rendering path (`glx_render` and related code).
They abandoned the use of `GL_TEXTURE_RECTANGLE` textures (used by Compton to read pixels in absolute 1:1 coordinates) in favor of standard `GL_TEXTURE_2D` textures with normalized texture coordinates ranging from `0.0` to `1.0`.
With this approach, the GPU itself handles perspective calculations and the stretching of XDamage rectangles, as a result, picom no longer needs to manually compute which fraction of the screen a sub-menu or damaged region (`crect`) represents.

Picom also introduced a sophisticated system of rewritten backends (such as the modern GLX backend or XRender): when picom detects damage (`use-damage` enabled), it builds what it calls a Render Pipeline:
The damaged rectangle of a window is extracted / The window is split into a set of rendering "metadata" / The background is then passed through the blur stage.
As a result, picom's Kawase shader was rewritten to directly consume normalized `0.0 → 1.0` buffer coordinates, without needing to know whether the pixel belongs to a small menu or a large window.

Regarding VRAM usage (`pass_tx_w > kawase_tex_w`), picom uses the exact same strategy as the implementation in compton-tde-x: a high-water mark logic. If the requested texture is larger than the cached one, the old texture is destroyed and a new one is allocated, if a small menu appears on top of a previously blurred large window, the large texture is reused without any reallocation.

In summary, picom rewrote the entire graphics engine from scratch to rely on more modern OpenGL conventions, delegating most of the mathematical work to the graphics driver.
Compton-TDE-x, on the other hand, preserves Compton's ultra-lightweight native rendering engine (legacy OpenGL), while mathematically injecting the orthogonal projection correction required by the Dual-Kawase algorithm.
This approach can potentially consume even less overall RAM than picom, as the OpenGL engine does not embed the multiple abstraction layers that picom has accumulated over time, at the cost of a more specialized architecture, optimized for this specific use case: TDE. :-)



## Requirements

Ensure you have the development packages for:
*   X11 (libX11, libXcomposite, libXdamage, libXrender, libXfixes, libXrandr, libXinerama, libXext)
*   OpenGL (libGL)
*   PkgConfig
*   **libconfig-dev** (Required for config file support)
*   **dbus-1-dev**
*   **libpcre2-dev**

## Build Instructions

### Install Dependencies

On Debian/Ubuntu-based systems, run:
```bash
./install_deps.sh
```

This will install all required development packages automatically.

### Configure and Build

1.  **Configure**:
    Run cmake. You can enable/disable features using `-DWITH_...`.
    The build is configured to strictly require features like `libconfig` by default.

    ```bash
    cmake . -DWITH_LIBCONFIG=ON -DWITH_OPENGL=ON -DWITH_PCRE2=ON \
            -DWITH_XRENDER=ON -DWITH_XFIXES=ON -DWITH_XCOMPOSITE=ON \
            -DWITH_XDAMAGE=ON
    ```

    *Optimization flags are automatically applied by the CMake configuration.*

    **For smallest binary size (recommended)**, add `-DWITH_SILENT_BUILD=ON`:
    ```bash
    cmake . -DWITH_LIBCONFIG=ON -DWITH_OPENGL=ON -DWITH_PCRE2=ON \
            -DWITH_XRENDER=ON -DWITH_XFIXES=ON -DWITH_XCOMPOSITE=ON \
            -DWITH_XDAMAGE=ON -DWITH_SILENT_BUILD=ON
    ```

    *Note: The CMake configuration automatically detects and uses the best available linker (gold > lld > standard ld).*

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

## Linker Optimization

The build system automatically detects and uses the best available linker:

### Available Linkers (in order of preference):

1.  **Gold Linker** (`binutils-gold`):
    - **Recommended for optimal binary size**
    - Uses Identical Code Folding (ICF) to merge identical functions
    - Produces binaries ~15-20% smaller than standard ld
    - Automatically used if `ld.gold` is available

2.  **LLD Linker** (`lld`):
    - Fast linker from the LLVM project
    - Good optimization, faster than gold
    - Used if gold is not available but lld is

3.  **Standard GNU Linker** (`ld`):
    - Fallback option
    - Works on all systems but produces larger binaries
    - Used if neither gold nor lld are available

### Expected Binary Sizes:

| Configuration | Approximate Size | Notes |
|---------------|-----------------|-------|
| Standard ld + logging | 200-210KB | Baseline |
| Gold linker + logging | 180-190KB | ~15% smaller |
| Gold linker + silent build | 175-180KB | No console logging |
| Gold linker + silent + sstrip | **170-175KB** | **Optimal** |

*Note: The `install_deps.sh` script will offer to install `binutils-gold` and `elfkickers` (for `sstrip`) for optimal results.*

## Packaging

To create a Debian package (`.deb`):

1.  **Build the project first** (follow the instructions above). The binary `compton-tde` must exist.
2.  Run the packaging script:
    ```bash
    ./create_deb.sh
    ```
    This will generate a `.deb` package in the current directory (e.g., `compton-tde_1.0_amd64.deb`).

## Cleanup

To clean up all build artifacts :  
```bash
make clean
rm -rf CMakeFiles CMakeCache.txt cmake_install.cmake Makefile compton_config.h package_build
```

## Sample Configuration

For reference, I've included my personal configuration in `myconfig/.compton-tde.conf`. This config provides Windows 10-like shadows and includes workarounds for display issues with certain applications (Chrome, Electron apps, etc.). Feel free to use it as a starting point for your own setup.
