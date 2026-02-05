cmake_minimum_required(VERSION 3.1)
project(compton-tde C)

# Find necessary packages
find_package(PkgConfig REQUIRED)
find_package(X11 REQUIRED)

# Options
option(WITH_XRENDER "Enable XRender support" ON)
option(WITH_XFIXES "Enable XFixes support" ON)
option(WITH_XDAMAGE "Enable XDamage support" ON)
option(WITH_XCOMPOSITE "Enable XComposite support" ON)
option(WITH_OPENGL "Enable usage of OpenGL for VSync and other effects" ON)
option(WITH_PCRE2 "Enable PCRE2 regex support" ON)
option(WITH_LIBCONFIG "Enable libconfig support" ON)
option(WITH_XINERAMA "Enable Xinerama support" ON)
option(WITH_XRANDR "Enable XRandr support" ON)
option(WITH_DBUS "Enable DBus support" ON)
option(WITH_SILENT_BUILD "Disable all console logging (printf_err/xerror)" OFF)

if(WITH_SILENT_BUILD)
    add_definitions(-DDISABLE_LOGGING)
endif()

if(NOT WITH_XRENDER)
    message(FATAL_ERROR "xrender support is needed to build compton-tde. Pass -DWITH_XRENDER=ON")
endif()
if(NOT WITH_XFIXES)
    message(FATAL_ERROR "xfixes support is needed to build compton-tde. Pass -DWITH_XFIXES=ON")
endif()

# Find Libraries
if(WITH_OPENGL)
    find_package(OpenGL REQUIRED)
    pkg_check_modules(GL REQUIRED gl)
endif()

# User confirmed libconfig-dev is installed
if(WITH_LIBCONFIG)
    pkg_check_modules(LIBCONFIG REQUIRED libconfig)
    if(LIBCONFIG_VERSION VERSION_LESS 1.4)
        add_definitions(-DCONFIG_LIBCONFIG_LEGACY)
    endif()
endif()

if(WITH_PCRE2)
    pkg_check_modules(LIBPCRE2 REQUIRED libpcre2-8)
endif()

if(WITH_DBUS)
    pkg_check_modules(DBUS REQUIRED dbus-1)
endif()

# check for extensions
if(WITH_XCOMPOSITE AND NOT X11_Xcomposite_FOUND)
    pkg_check_modules(XCOMPOSITE xcomposite)
endif()
if(WITH_XDAMAGE AND NOT X11_Xdamage_FOUND)
    pkg_check_modules(XDAMAGE xdamage)
endif()
if(WITH_XRANDR AND NOT X11_Xrandr_FOUND)
    pkg_check_modules(XRANDR xrandr)
endif()
if(WITH_XINERAMA AND NOT X11_Xinerama_FOUND)
    pkg_check_modules(XINERAMA xinerama)
endif()

# Configuration variables
set(CONFIG_XSYNC ON)
if(WITH_OPENGL)
    set(CONFIG_VSYNC_OPENGL ON)
    set(CONFIG_VSYNC_OPENGL_GLSL ON)
    set(CONFIG_VSYNC_OPENGL_FBO ON)
    set(CONFIG_GLX_SYNC ON)
endif()
if(WITH_LIBCONFIG)
    set(CONFIG_LIBCONFIG ON)
endif()
if(WITH_PCRE2)
    set(CONFIG_REGEX_PCRE2 ON)
    set(CONFIG_REGEX_PCRE2_JIT ON)
endif()
if(WITH_XINERAMA)
    set(CONFIG_XINERAMA ON)
endif()
if(WITH_XRANDR)
    set(CONFIG_XRANDR ON)
endif()
set(CONFIG_DBUS ON)
set(CONFIG_C2 ON)

configure_file(compton_config.h.cmake compton_config.h)

# Sources
set(compton_SRCS compton.c)
if(WITH_OPENGL)
    list(APPEND compton_SRCS opengl.c)
endif()
list(APPEND compton_SRCS dbus.c c2.c)

# Optimization Flags
# Compiler Flags
set(OPT_CFLAGS "-std=c99 -D_DEFAULT_SOURCE -DNDEBUG -g0 -O2 -fstrict-aliasing -flto=2 -ffunction-sections -fdata-sections -fno-ident -fno-plt -fno-asynchronous-unwind-tables -fno-unwind-tables -fomit-frame-pointer -fno-stack-protector -fno-math-errno -ffast-math -fvisibility=hidden -fmerge-all-constants -Wno-deprecated-declarations")
add_definitions(${OPT_CFLAGS})

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OPT_CFLAGS}")

# Include Directories
include_directories(
    ${CMAKE_BINARY_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
    ${X11_INCLUDE_DIR}
)

if(WITH_LIBCONFIG)
    include_directories(${LIBCONFIG_INCLUDE_DIRS})
endif()
if(WITH_DBUS)
    include_directories(${DBUS_INCLUDE_DIRS})
endif()
if(WITH_PCRE2)
    include_directories(${LIBPCRE2_INCLUDE_DIRS})
endif()
if(WITH_OPENGL)
    include_directories(${OPENGL_INCLUDE_DIR})
endif()

# Libraries
set(compton_LIBRARIES m ${X11_LIBRARIES})

if(WITH_XRENDER)
    list(APPEND compton_LIBRARIES ${X11_Xrender_LIB})
endif()
if(WITH_XFIXES)
    list(APPEND compton_LIBRARIES ${X11_Xfixes_LIB})
endif()
if(WITH_XCOMPOSITE)
    list(APPEND compton_LIBRARIES ${X11_Xcomposite_LIB})
endif()
if(WITH_XDAMAGE)
    list(APPEND compton_LIBRARIES ${X11_Xdamage_LIB})
endif()
if(WITH_XINERAMA)
    list(APPEND compton_LIBRARIES ${X11_Xinerama_LIB})
endif()
if(WITH_XRANDR)
    list(APPEND compton_LIBRARIES ${X11_Xrandr_LIB})
endif()
if(WITH_XEXT)
    list(APPEND compton_LIBRARIES ${X11_Xext_LIB})
endif()

if(WITH_OPENGL)
    list(APPEND compton_LIBRARIES ${OPENGL_LIBRARIES})
    list(APPEND compton_LIBRARIES ${GL_LIBRARIES})
endif()
if(WITH_LIBCONFIG)
    list(APPEND compton_LIBRARIES ${LIBCONFIG_LIBRARIES})
endif()
if(WITH_PCRE2)
    list(APPEND compton_LIBRARIES ${LIBPCRE2_LIBRARIES})
endif()
if(WITH_DBUS)
    list(APPEND compton_LIBRARIES ${DBUS_LIBRARIES})
endif()

add_executable(compton-tde ${compton_SRCS})
target_link_libraries(compton-tde ${compton_LIBRARIES})

# Linker Flags
set(OPT_LDFLAGS "-Wl,--relax -Wl,-z,norelro -flto=2 -fuse-ld=gold -Wl,--gc-sections,--build-id=none,--as-needed,--strip-all,-O1,--icf=all,--compress-debug-sections=zlib -s")
set_target_properties(compton-tde PROPERTIES LINK_FLAGS "${OPT_LDFLAGS}")

install(TARGETS compton-tde DESTINATION bin)
