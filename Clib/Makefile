# POSIX build of the object simple_shaping.ecf expects on macOS and Linux.
# Usage: make -C Clib   (HarfBuzz, FriBidi, FreeType, fontconfig and cairo from
# Homebrew on macOS, from the system on Linux, found through pkg-config if present)
CC ?= cc
PKGS = harfbuzz fribidi freetype2 fontconfig cairo
PKG_CFLAGS := $(shell pkg-config --cflags $(PKGS) 2>/dev/null)
BREW := $(shell [ -d /opt/homebrew/include ] && echo /opt/homebrew)
ifeq ($(PKG_CFLAGS),)
ifneq ($(BREW),)
PKG_CFLAGS := -I$(BREW)/include -I$(BREW)/include/harfbuzz -I$(BREW)/include/fribidi -I$(BREW)/include/freetype2 -I$(BREW)/include/cairo
else
PKG_CFLAGS := -I/usr/include/harfbuzz -I/usr/include/fribidi -I/usr/include/freetype2 -I/usr/include/cairo
endif
endif
CFLAGS ?= -O2 -fPIC
CFLAGS += $(PKG_CFLAGS)

simple_shaping_posix.o: simple_shaping_posix.c simple_shaping_posix.h
	$(CC) $(CFLAGS) -c simple_shaping_posix.c -o simple_shaping_posix.o

clean:
	rm -f simple_shaping_posix.o

.PHONY: clean
