/*
 * simple_shaping_gdi.h - what GDI32_API's inline externals include. On Windows it is
 * <windows.h>; elsewhere there is no GDI, and every GDI32_API body answers 0, so
 * font realization through GDI fails and the macOS and Linux backend (posix/) is
 * used instead. It holds no state of its own (see GDI32_API's class note).
 */
#ifndef SIMPLE_SHAPING_GDI_H
#define SIMPLE_SHAPING_GDI_H
#ifdef _WIN32
#include <windows.h>
#include <string.h>
#endif
#endif
