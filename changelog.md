This is the changelog for compton-tde-x


=================================================================================
Version 1.0 - initial release

Mostly code optimizations:

*   **Size Optimization**: 
    - Hardcoded aggressive optimization flags (`-O2`, `-flto`, `-fvisibility=hidden`, etc.) to minimize binary size.
    - Stripped section headers (requires `sstrip` or standard `strip`) to achieve a binary size of **~200KB** (vs ~250KB stock).
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
=================================================================================






=================================================================================
Version 2.0

Dual-Kawase Blur Support:

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
=================================================================================






=================================================================================
Version 2.1 (never released)

Mostly code optimizations:

### Fade Performance (Window/Menu Appear / Disappear)

Blur invocation is conditionally controlled by `!(w->fade && w->opacity != w->opacity_tgt)`

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

### Others:

- Buffer deallocation (`glDeleteFramebuffers`, `glDeleteTextures`, `glDeleteProgram`) in `glx_destroy_blur_kawase` is strict and executed on every configuration switch → No memory leaks
- All logic relies on:
  - Integer arithmetic
  - Precomputed binary-sized registers (`scale <<= 1`)
  - 1:1 mapped OpenGL floating-point operations
=================================================================================






=================================================================================
Version 3.0

Enhanced Window Condition Matching and Native Software Cursor for Mixed-DPI Supersampling:

## PCRE2 Match Data Fix (`c2.c`)

During the PCRE1 → PCRE2 migration I introduced a crash in the regex matching path (`~=` operator):
 `pcre2_match()` requires a valid `pcre2_match_data *` block — it cannot be `NULL`. The original PCRE1 API (`pcre_exec`) accepted `NULL` for its optional `extra` argument, but PCRE2 does not allow NULL here. After migration, the `NULL` placeholder was kept, causing a segfault whenever a PCRE2 regex condition (`~=`) was evaluated...
--> Added `pcre2_match_data *regex_pcre_match` to `c2_l_t`; allocated via `pcre2_match_data_create_from_pattern()` after compilation and freed in `c2_free()`, so the match block is now passed correctly to every `pcre2_match()` call.

## New Predefined Condition Targets (`c2.h`, `c2.c`)

Two new predefined targets backported from picom:

| Target | Type | Description |
|--------|------|-------------|
| `group_focused` | boolean | True if any window in the same leader group as the current window is focused. Uses the existing `ps->active_leader` tracking. |
| `urgent` | boolean | True if the window has the `XUrgencyHint` flag set in its `WM_HINTS` property. Read on-demand via `XGetWMHints()`. |

**Example:**
```ini
opacity-rule = [ "80:group_focused = 0", "100:urgent = 1" ];
```

## PID-Based Window Class Inheritance (`compton.c`, `common.h`)

Applications like Chrome/Electron/Chromium create popup, menu, tooltip, and overlay windows as `override-redirect` X11 windows. These transient windows frequently do **not** have `WM_CLASS` set directly on them, even when the main application window does :-( This caused conditions like `class_i *= 'chrome'` in `shadow-exclude` or `blur-background-exclude` to silently fail for all popup/menu windows from those applications ! For exeample, chrome auxiliary windows were listed with an empty class `()`, while the main browser window had `WM_CLASS = ("google-chrome", "Google-chrome")`.

Th fix: (`win_get_class()` — `compton.c`): When `WM_CLASS` is not found on an `override-redirect` window, two fallback mechanisms are attempted in order:
 - **`WM_TRANSIENT_FOR` inheritance**: If the window declares a parent via `WM_TRANSIENT_FOR`, and that parent window is a tracked compton window with a resolved class, the parent's `class_instance` and `class_general` are inherited.
 - 2.  **`_NET_WM_PID` inheritance** (primary fix for Chrome/Electron): The window's `_NET_WM_PID` is read (via the new `ps->atom_pid` atom). All windows currently tracked in `ps->list` are scanned for a window with the **same PID** that already has `WM_CLASS` resolved (reading PID from `client_win` to correctly handle WM-reparented windows). When a PID-sibling is found, its class is inherited by the classless popup window.

So now, popup and menu windows from Chrome, Chromium, and Electron applications are now automatically matched by `class_i`/`class_g` conditions.

**Example**:
```ini
shadow-exclude = [ "class_i *= 'chrome'" ];
blur-background-exclude = [ "class_i *= 'chrome'" ];
```

## Native Software Cursor for Mixed-DPI Supersampling (`--sw-cursor` / `sw-cursor = true`)

When using multiple monitors with different scaling factors (e.g. 4K at 2.0x and 1080p at 1.0x), the only perfect way to scale X11 is via XRandR supersampling (scaling the output framebuffer). However, certain video drivers (like NVIDIA) have a bug where the hardware mouse cursor "flickers" or disappears on one of the screens because the hardware cursor overlay plane clashes with the scaled XRandR coordinates.

To "fix" this exact situation, Compton-TDE 3.0 introduces a native software cursor.

You can enable it by running `compton-tde --sw-cursor` or by adding `sw-cursor = true;` to your `compton.conf` file.

### Technical Explanation & CPU/GPU Cost

When enabled, Compton hides the X11 hardware cursor and draws the cursor itself as an OpenGL texture mixed directly into your screen's video stream *before* it gets sent to the monitor. This completely bypasses the X11 Server bugs, NVIDIA driver quirks, and XRandR scaling mismatches that cause tearing, flickering, and scaling differences across multiple monitors!

- **CPU usage explanation**:
  - *Hardware cursor*: 0% CPU. Purely handled by the display controller chip.
  - *Software Cursor (our solution)*: Wakes up compton 250 times a second (4ms poll via `XQueryPointer`). This consumes ~1% max. of a single CPU core when moving the mouse, and 0% when idle. Negligible on any processor from the last 15/20 year.
- **GPU usage explanation**:
  - *Hardware cursor*: 0% GPU. It's drawn as a hardware overlay *after* the GPU has finished rendering the frame.
  - *Software Cursor*: Forces compton to composite an extra frame (drawing 2 OpenGL triangles with transparency) every time the mouse moves by 1 pixel. This requires little memory bandwidth to swap the screen buffers. It might consume 1% to 4% of a VERY old integrated GPU, but is absolutely invisible on average/modern hardware. VRAM usage is essentially zero (~16KB for the cursor texture).
- **The "Heaviness" tradeoff**:
  - So, technically (mathematically ^^) it is infinitely "heavier" than the hardware cursor because I replaced a 100% hardware-accelerated zero-cost operation with a full software/OpenGL composite loop... 
  - However, in practical terms: `compton` is ALREADY compositing the entire screen. Asking it to draw ONE extra 48x48 icon on top takes less than 0.1 milliseconds per frame for the GPU (probably even less)... I personnaly think it's perfectly acceptable for the massive benefit of perfect sync (NO flickering) across scaled monitors .
=================================================================================





=================================================================================
Version 4.0

Performance & Reliability:


## Reliability Fixes

### Strict-Aliasing UB in `get_window_transparency_filter_*` (§4.8)
Four functions used `*(long *)data` to read an `unsigned char *` returned by `XGetWindowProperty`.
This violates C99 strict-aliasing rules and produces incorrect code with `-fstrict-aliasing` (active by default).
The Atom value was never actually used — the functions only checked for property *existence* — so the cast was removed entirely, leaving only the `XFree` call.
Also fixed: `data` now initialised to `NULL` before `XGetWindowProperty`, so the error-path `XFree` is safe.

### Unbounded X11 Tree Recursion in `determine_window_*` (§4.3 + §1.2)
Four functions traversed the entire X11 window tree recursively without any depth limit,
causing potential stack overflows on deep trees (e.g. Electron/Chrome).
Each public function now delegates to a single generic helper `determine_win_prop_impl(ps, w, pred, depth)`,
which accepts a `win_prop_fn_t` function pointer and stops at `DETERMINE_WIN_MAX_DEPTH = 3` levels.
This also fixed a minor `XFree` leak: early `return True` inside the children loop previously skipped freeing the `XQueryTree`-allocated array.

### `win_update_prop_int` Undefined Behaviour (§4.1)
The function silently truncated a `long` (8 B on x86_64) into a `uint32_t` target without an explicit cast,
left `*target` uninitialised when `size` matched neither `sizeof(uint32_t)` nor `sizeof(long)`,
and wrote `-1` into unsigned targets without a semantically unambiguous cast.
Fixed: explicit `(uint32_t)raw` and `(long)-1` casts; a `memset` fallback for the unknown-size path.

### `greyscale_picture` Resource Leak (§4.2)
In `win_paint_win`, `greyscale_picture` was only freed inside the `else` branch of `if (!tmp_picture)`.
When `xr_build_picture` returned `None` for `tmp_picture`, `greyscale_picture` was silently leaked.
Fixed: `free_picture(&greyscale_picture)` moved unconditionally after the `if/else` block.
Bonus: the redundant `if (reg_clip && tmp_picture)` guard simplified to `if (reg_clip)`.

### `normalize_conv_kern` Division by Zero (§4.5)
With `-ffast-math` active (set in the build flags), dividing by zero produces `+Inf` instead of trapping.
If the convolution kernel sums to zero (degenerate input), all `XDoubleToFixed` calls would overflow.
Fixed: guard `if (sum < 1e-10 && sum > -1e-10) return;` before `1.0 / sum`.

### `mstrcpy` NULL Pointer Dereference (§7)
`mstrcpy` called `strlen(src)` unconditionally. The call `mstrcpy(setlocale(LC_NUMERIC, NULL))` is a
concrete crash risk because `setlocale` can return `NULL`.
Fixed: `if (!src) return NULL;` added at the top of `mstrcpy`, matching the `strdup` contract.

## Performance Optimisations

### O(1) `find_win` via Hash Table (§1.1)
`find_win` previously performed an O(n) linear scan of `ps->list` on every X event
(each `PropertyNotify`, `DamageNotify`, `FocusIn/Out`, etc. triggers one or more lookups).
Replaced with a 256-bucket open-hash table `win_ht[256]` in `session_t`, indexed by `Window & 0xFF`.
X11 XIDs are sequential low integers, so the low byte distributes well.
Each `win` gains one `ht_next` pointer for collision chaining.
Helpers `win_ht_insert`/`win_ht_remove` maintain the table in sync with `ps->list` at the
three mutation sites (`add_win`, `finish_destroy_win`, teardown).
Expected gain: **–15 to –40 % CPU** on X-event-heavy workloads.

### Blur Kernel Renormalization Cache (§1.3)
`win_blur_background` recomputed `factor_center` and re-ran `memcpy + normalize_conv_kern`
on every frame, even when the window's opacity had not changed.
A `last_factor_center` float field was added to `struct _win` (initialized to –1, no padding waste).
The renormalization loop is now skipped when `|factor_center – last_factor_center| < 1e-6`.

### Shadow Region via Region Cache (§1.4)
The shadow border clipping in `paint_all` used `XFixesCreateRegion` + `free_region` (= `XFixesDestroyRegion`),
issuing one X server round-trip allocation/deallocation per visible shadow per frame.
Replaced with `rc_create_region` / `XFixesSetRegion` / `rc_destroy_region` to route through the existing region cache.

### `ignore_t` Circular Ring Buffer (§1.5)
`set_ignore` allocated a new `ignore_t` node via `malloc` for every X request that needed to be silenced
(XDamageSubtract, XCompositeNameWindowPixmap, etc.) — potentially dozens per frame.
Replaced with a static `ignore_buf[128]` ring buffer (`head_idx` / `tail_idx`) in `session_t`.
Zero heap allocations on the hot path. The old `ignore_head`/`ignore_tail` linked-list fields and
the `session_destroy` free-loop were removed.

## Binary Size Reduction

### Factorize `determine_window_*` (§2)
The four `determine_window_*_impl` functions were structurally identical, differing only in
which `get_window_*` predicate they called.
Merged into one generic `determine_win_prop_impl(ps, w, pred, depth)` with a `win_prop_fn_t`
function-pointer parameter. Each public wrapper is now a trivial one-liner.
Estimated reduction: **~350 bytes** of deduplicated machine code.

### `shadow_width`/`shadow_height` → `uint16_t` (§2.1)
Both fields were `int` (4 B each). Changed to `uint16_t` (2 B each), grouped naturally alongside
the existing `int16_t shadow_dx/dy` and `uint16_t widthb/heightb` fields in `struct _win`.
No padding introduced. Maximum representable shadow dimension: 65 535 px.
Gain: **–4 bytes per managed window**.

### Cache Urgency Property (WM_HINTS) (§5.1)
Modified `c2_match_once_leaf` to use a cached `urgency` field in `struct win` instead of making blocking `XGetWMHints` calls inside the window matching loop. The cache is updated upon receiving `PropertyNotify` events.
Significant reduction in synchronous X server round-trips during condition evaluation.

### O(1) Client Window Lookup (§1.2)
Implemented a secondary hash table (`clt_ht`) in `session_t` to map `client_win` IDs to their respective `win` structures. This replaces the previous O(n) linear scan in `find_toplevel()`.
Constant-time lookup for window property events.

### Cached Frame Parent for `find_toplevel2` (§3.1)
`find_toplevel2()` now utilizes a cached `frame_parent` field, populated once during window creation and updated on `ReparentNotify`. This avoids expensive recursive `XQueryTree` traversals.

### `struct win` Packing & Alignment (§4B)
Reorganized the `win` structure to group boolean flags and 16-bit fields together. By eliminating internal fragmentation and padding, the size of each window structure is reduced by **~12-16 bytes**, improving cache locality.

## Robustness & Security Audit (§5)

Systematic audit of the entire codebase for undefined behavior, unchecked allocations,
format-string bugs, and potential buffer overflows. All 16 items below have zero
risk of behavioral regression (no user-visible semantics change).

### `CPY_FDS` → Stack-Allocated `fd_set` Copies (§5.2/§2.3)
The `CPY_FDS` macro in `fds_poll()` allocated 3 `fd_set` via `malloc()` on every
`select()` call (the mainloop hot path), and checked for NULL *after* `memcpy` —
an undefined behavior if `malloc` returned `NULL`.
Replaced with stack-allocated `fd_set` copies: zero allocations, zero UB.

### `find_client_win()` Depth Bound (§5.1)
The only remaining unbounded recursive DFS in the codebase. A deep X11 window
hierarchy (e.g. Chrome/Electron) could cause a stack overflow.
Split into `find_client_win_impl(ps, w, depth)` with `FIND_CLIENT_WIN_MAX_DEPTH=8`.

### `fds_insert_select()` fd Bound Check (§5.3)
`assert(fd <= FD_SETSIZE)` was disabled in production (`-DNDEBUG`), allowing
`FD_SET` to write out of bounds if a file descriptor exceeded `FD_SETSIZE`.
Replaced with a runtime check that returns `false`.
`exit(1)` on OOM also replaced with `return false`.

### `mstrextend()` NULL Init (§5.5)
When `*psrc1` was `NULL`, `crealloc` acted like `malloc` (returning uninitialized
memory), then `strcat` searched for a null terminator in garbage — UB.
Now uses `strcpy` for the initial case.

### Missing `malloc` Checks (§5.4/§5.6)
- `make_gaussian_map()`: added `if (!c) return NULL`.
- `presum_gaussian()`: NULL checks on both `shadow_corner` and `shadow_top`;
  cleans up and returns safely on failure.
- `ev_expose()`: safe realloc pattern (tmp pointer) preventing memory leak + NULL deref.

### `strtok(getenv())` UB Fix (§5.10)
`strtok()` modifies its argument in-place; calling it directly on the return
value of `getenv("XDG_CONFIG_DIRS")` is UB per POSIX. Now copies via `mstrcpy()`.

### Debug `printf` Format Bugs (§5.7/§5.8)
- `calc_opacity()`: `printf_dbgf` format expected `%lx` but no argument was provided.
- `win_determine_fade()`: `w->fade ? w->fade : NULL` passed `NULL` as `%d`.

### `opacity_int` Clamp (§5.11)
`opacity_int` in `make_shadow()` was not bounds-checked. If `opacity` was out of
[0, 1], indices into `shadow_corner[]`/`shadow_top[]` would overflow.
Now clamped to [0, 25].

### `register_cm()` Buffer (§5.9)
Buffer size for `_NET_WM_CM_S%d` was computed via fragile manual digit-counting
+ `malloc`. Replaced with a fixed `char buf[32]` stack buffer.

### `win_build_shadow()` Return Type (§5.12)
`return None;` in a `bool` function. `None` is `0L`, so it compiled, but was
semantically wrong. Changed to `return false`.

## CPU Micro-Optimizations (§6)

### `ev_property_notify()` Lookup Dedup (§6.1)
Each `PropertyNotify` event triggered up to 6+ separate `find_win()`/`find_toplevel()`
calls for the same `ev->window`. Now caches `w_frame` and `w_top` at function entry.

### `restack_win()` Single-Pass (§6.2)
The old implementation scanned `ps->list` twice (unhook + rehook). Merged into
a single traversal that locates both `w` and `new_above` simultaneously.
Handles the pointer-stale edge case when `prev_new == &w->next`.

### PID-Cached Class Inheritance (§6.3)
`win_get_class()` scanned every window with an `XGetWindowProperty` round-trip per
candidate to match `_NET_WM_PID`. Added `cached_pid` field to `struct _win`;
the scan now compares in-memory values — zero X11 round-trips.

## Binary Size Reduction (§7)

### `get_window_*` Unification (§7.1)
Four structurally-identical `get_window_{transparency_filter_greyscale,
transparency_filter_greyscale_blended, transparent_to_desktop,
transparent_to_black}` functions replaced by one generic
`get_window_atom_prop_exists(ps, w, atom)` + four one-liner wrappers.
Saves ~**200 bytes**.

### Predefined Kernels as `XFixed[]` (§7.2)
The `CONV_KERN_PREDEF` table stored 8 convolution kernels as large text strings
(up to ~500 B each for 11×11 gaussian) parsed at runtime via recursive
`strtod` calls. Replaced with `static const XFixed[]` arrays whose values are
compile-time constant-folded via `XDoubleToFixed()`. Saves ~**800 bytes** of
`.rodata` and eliminates startup CPU cost.

## RAM Optimization (§8)

### `usage_text` Conditioned (§8.1)
~4 KB of static usage text is now compiled out when `-DCOMPTON_MINIMAL` is defined.
A one-liner fallback points the user to `man compton-tde`.


## OpenGL Backend (`opengl.c`) Fixes

### Spurious `double` Casts in `glx_render_` (Fix A)
In the hot texture coordinate computation loop, four `GLfloat` assignments used intermediate
`(double)` casts on integer expressions, forcing a two-step `int→double→float` FPU conversion.
Changed to direct `(GLfloat)` casts — one conversion, no precision change.

### `glUniform` Uploads Skipped When Unchanged (Fix D)
`glx_blur_dst` previously called `glUniform1f` for `offset_x`, `offset_y`, and `factor_center`
unconditionally on every blurred window per frame.
Added `last_offset_x`, `last_offset_y`, `last_factor_center` cache fields to `glx_blur_pass_t`.
Uploads are now skipped when the value is identical to the last-uploaded one.
In practice: `texfac_x/y` only change when the window is resized; `factor_center` changes only
when opacity changes. On a stable desktop, all three are skipped every frame.

## Additional Optimisations & Fixes

### Branchless `run_fade` Animation
Replaced branching paths inside the `run_fade` loop with pure C branchless execution. This coaxes the compiler into generating `cmov`/`csel` instructions, reducing CPU branch-misprediction penalties in high-framerate environments without resorting to inline assembly.

### XRender `VisualFormat` Caching
Replaced multiple sequential `XRenderFindVisualFormat` property lookups that generated synchronous X11 protocol waits during window resize/recreation phases, caching the format globally.

### PCRE Regex `strlen` Elimination
To optimise condition matching, the `c2_l_t` struct was expanded to cache `ptnstr_len` directly at construction, eliminating redundant `strlen` calls inside the central O(n) regex evaluation loop.

### Blur Pass GPU Micro-Optimizations
- Eliminated synchronous `glIsEnabled(GL_SCISSOR_TEST / GL_STENCIL_TEST)` queries entirely by mirroring the hardware state in `glx_session_t`, averting pipeline synchronization stalls.
- Added heuristics to entirely skip GPU blur passes for fully opaque windows (`>= 99%`) or infinitesimally small regions (`< 100px`), recovering lost GPU frame-time on invisible blur operations.

### Memory Guardrails & Safe GLX Binding
- Enforced a strict maximum of `128` on `shadow_radius` to prevent quadratic RAM allocations and OOM crashes from extreme configurations.
- Introduced explicit defensive `!ptex` texture validations inside `win_paint_win` and OpenGL rendering functions, ensuring that `glx_bind_pixmap` texture binding failures degrade gracefully into unblurred frames instead of triggering a Segmentation Fault.
=================================================================================


