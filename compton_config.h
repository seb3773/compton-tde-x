// #include "config.h"

// Whether to enable PCRE2 regular expression support in blacklists, enabled by default
#define CONFIG_REGEX_PCRE2 1
// Whether to enable JIT support of libpcre2. This may cause problems on PaX kernels.
#define CONFIG_REGEX_PCRE2_JIT 1

// Whether to enable parsing of configuration files using libconfig.
#define CONFIG_LIBCONFIG 1
// Whether we are using a legacy version of libconfig (1.3.x).
/* #undef CONFIG_LIBCONFIG_LEGACY */

// Whether to enable DRM VSync support
/* #undef CONFIG_VSYNC_DRM */

// Whether to enable DBus support with libdbus.
#define CONFIG_DBUS 1
// Whether to enable condition support.
#define CONFIG_C2 1

// Whether to enable X Sync support.
#define CONFIG_XSYNC 1

// Whether to enable OpenGL support
#define CONFIG_VSYNC_OPENGL 1
// Whether to enable GLX GLSL support
#define CONFIG_VSYNC_OPENGL_GLSL 1
// Whether to enable GLX FBO support
#define CONFIG_VSYNC_OPENGL_FBO 1
// Whether to enable GLX Sync support.
#define CONFIG_GLX_SYNC 1

// Whether to enable Xranr support
#define CONFIG_XRANDR 1
// Whether to enable Xinerama support
#define CONFIG_XINERAMA 1
