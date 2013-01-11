PACKAGE          ?= mozilla-gnome-keyring
VERSION          ?= $(shell git describe --tags 2>/dev/null || date +dev-%s)
# if these are empty, we will attempt to auto-detect correct values
#XUL_VER_MIN      ?=
#XUL_VER_MAX      ?=
# package distribution variables
FULLNAME         ?= $(PACKAGE)-$(VERSION)
ARCHIVENAME      ?= $(FULLNAME)


# xulrunner tools. use = not ?= so we don't execute on every invocation
XUL_PKG_NAME     ?= $(shell (pkg-config --atleast-version=2 libxul && echo libxul) \
                         || (pkg-config libxul2                    && echo libxul2))
XUL_PKG_NAME     := $(XUL_PKG_NAME)

# compilation flags

# if pkgconfig file for libxul is available, use it
ifneq ($(XUL_PKG_NAME),)
XUL_CFLAGS       := `pkg-config --cflags $(XUL_PKG_NAME)`
XUL_LDFLAGS      := `pkg-config --libs $(XUL_PKG_NAME)`
XPCOM_ABI_FLAGS  += `pkg-config --libs-only-L $(XUL_PKG_NAME) | sed -e 's/-L\(\S*\).*/-Wl,-rpath=\1/' | sed -n -e 'p;s/^\(.*\)-devel\(.*\)\/lib$$/\1\2/gp'`
endif

GNOME_CFLAGS     := `pkg-config --cflags gnome-keyring-1`
GNOME_LDFLAGS    := `pkg-config --libs gnome-keyring-1`
CXXFLAGS         += -Wall -fno-rtti -fno-exceptions -fPIC -std=gnu++0x -D__STDC_LIMIT_MACROS
LDFLAGS          +=

# work around mozilla bug #763327
NEED_HASHFUNC    = $(shell echo '\#include "mozilla/HashFunctions.h"'| \
                     $(CXX) $(XUL_CFLAGS) $(CXXFLAGS) -o /dev/null -shared -x c++ -w -fdirectives-only - \
                     && echo true || echo false)
# determine xul version from "mozilla-config.h" include file
XUL_VERSION      = $(shell echo '\#include "mozilla-config.h"'| \
                     $(CXX) $(XUL_CFLAGS) $(CXXFLAGS) -shared -x c++ -w -E -fdirectives-only - | \
                     sed -n -e 's/\#[[:space:]]*define[[:space:]]\+MOZILLA_VERSION[[:space:]]\+\"\(.*\)\"/\1/gp')
XUL_VER_MIN      ?= `echo $(XUL_VERSION) | sed -r -e 's/([^.]+\.[^.]+).*/\1/g'`
XUL_VER_MAX      ?= `echo $(XUL_VERSION) | sed -rn -e 's/([^.]+).*/\1.*/gp'`
# if auto-detect but xulrunner is not available, fall back to these values
XUL_VER_MIN_     ?= 10.0.1
XUL_VER_MAX_     ?= 10.*


# platform-specific handling
# lazy variables, instantiated properly in a sub-make since make doesn't
# support dynamically adjusting the dependency tree during its run
PLATFORM         ?= unknown

TARGET           ?= libgnomekeyring.so
TARGET           := $(TARGET)
XPI_TARGET       := $(FULLNAME).xpi
BUILD_FILES      := \
xpi/platform/$(PLATFORM)/components/$(TARGET) \
xpi/install.rdf \
xpi/chrome.manifest \
xpi/defaults/preferences/gnome-keyring.js \
xpi/chrome/skin/hicolor/seahorse.svg


.PHONY: all build build-xpi tarball
all: build

build: build-xpi

build-xpi: xpcom_abi
ifeq "$(PLATFORM)" "unknown"
# set PLATFORM properly in a sub-make
	PLATFORM=$$(./xpcom_abi) && \
	$(MAKE) -f $(lastword $(MAKEFILE_LIST)) $(XPI_TARGET) PLATFORM=$${PLATFORM}
else
	$(MAKE) -f $(lastword $(MAKEFILE_LIST)) $(XPI_TARGET)
endif

$(XPI_TARGET): $(BUILD_FILES)
	cd xpi && zip -rq ../$@ *

xpi/platform/%/components/$(TARGET): $(TARGET)
	mkdir -p $(@D)
	cp -a $< $@

xpi/install.rdf: install.rdf Makefile
	mkdir -p xpi
	XUL_VER_MIN=$(XUL_VER_MIN); \
	XUL_VER_MAX=$(XUL_VER_MAX); \
	sed -e 's	$${PLATFORM}	'$(PLATFORM)'	g' \
	    -e 's	$${VERSION}	'$(VERSION)'	g' \
	    -e 's	$${XUL_VER_MIN}	'"$${XUL_VER_MIN:-$(XUL_VER_MIN_)}"'	g' \
	    -e 's	$${XUL_VER_MAX}	'"$${XUL_VER_MAX:-$(XUL_VER_MAX_)}"'	g' \
	    $< > $@

xpi/chrome.manifest: chrome.manifest Makefile
	mkdir -p xpi
	sed -e 's	$${PLATFORM}	'$(PLATFORM)'	g' \
	    -e 's	$${TARGET}	'$(TARGET)'	g' \
	    $< > $@

xpi/defaults/preferences/gnome-keyring.js: gnome-keyring.js
	mkdir -p xpi/defaults/preferences
	cp -a $< $@

xpi/chrome/skin/hicolor/seahorse.svg: seahorse.svg
	mkdir -p xpi/chrome/skin/hicolor
	cp -a $< $@

$(TARGET): GnomeKeyring.cpp GnomeKeyring.h Makefile
	$(CXX) $< -o $@ -shared \
	    $(XUL_CFLAGS) $(XUL_LDFLAGS) $(GNOME_CFLAGS) $(GNOME_LDFLAGS) $(CXXFLAGS) $(LDFLAGS)
	chmod +x $@

xpcom_abi: xpcom_abi.cpp HashFunctions.cpp Makefile
ifeq "$(NEED_HASHFUNC)" "true"
	$(CXX) $< -o $@ $(XUL_CFLAGS) $(XUL_LDFLAGS) $(XPCOM_ABI_FLAGS) $(CXXFLAGS) $(LDFLAGS) $(word 2,$^)
else
	$(CXX) $< -o $@ $(XUL_CFLAGS) $(XUL_LDFLAGS) $(XPCOM_ABI_FLAGS) $(CXXFLAGS) $(LDFLAGS)
endif

tarball:
	git archive --format=tar \
	    --prefix=$(FULLNAME)/ HEAD \
	    | gzip - > $(ARCHIVENAME).tar.gz

.PHONY: clean-all clean
clean:
	rm -f $(TARGET)
	rm -f $(XPI_TARGET)
	rm -f xpcom_abi
	rm -f -r xpi

clean-all: clean
	rm -f *.xpi
	rm -f *.tar.gz
