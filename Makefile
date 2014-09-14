PACKAGE          ?= mozilla-gnome-keyring
VERSION          ?= $(shell git describe --tags --match '[0-9]*' 2>/dev/null || date +dev-%s)
# if these are empty, we will attempt to auto-detect correct values
#XUL_VER_MIN      ?=
#XUL_VER_MAX      ?=
# package distribution variables
FULLNAME         ?= $(PACKAGE)-$(VERSION)
ARCHIVENAME      ?= $(FULLNAME)


# xulrunner tools. use := so we don't execute on every use of the variable
XUL_PKG_NAME     ?= $(shell (pkg-config --atleast-version=2 libxul && echo libxul) \
                         || (pkg-config libxul2                    && echo libxul2))
XUL_PKG_NAME     := $(XUL_PKG_NAME)

# compilation flags

# if pkgconfig file for libxul is available, use it
ifneq ($(XUL_PKG_NAME),)
XUL_CFLAGS       := `pkg-config --cflags $(XUL_PKG_NAME)`
XUL_LDFLAGS      := `pkg-config --libs $(XUL_PKG_NAME)`
XPCOM_ABI_FLAGS  := `pkg-config --libs-only-L $(XUL_PKG_NAME) | sed -e 's/-L\(\S*\).*/-Wl,-rpath=\1/' | sed -n -e 'p;s/^\(.*\)-devel\(.*\)\/lib$$/\1\2/gp'`
endif

GNOME_CFLAGS     := `pkg-config --cflags gnome-keyring-1`
GNOME_LDFLAGS    := `pkg-config --libs gnome-keyring-1`
CXXFLAGS         += -Wall -fno-rtti -fno-exceptions -fPIC -std=gnu++0x -D__STDC_LIMIT_MACROS
LDFLAGS          +=

# if auto-detection fails, fall back to these values
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

build-xpi: config.vars
ifndef HAVE_CONFIG_VARS
# set build-environment variables properly in a sub-make
	. ./$<; \
	$(MAKE) -f $(lastword $(MAKEFILE_LIST)) $(XPI_TARGET)
else
	$(MAKE) -f $(lastword $(MAKEFILE_LIST)) $(XPI_TARGET)
endif

SHELL_EXPORT := $(foreach v,CXX XUL_CFLAGS XUL_LDFLAGS XPCOM_ABI_FLAGS GNOME_CFLAGS GNOME_LDFLAGS CXXFLAGS LDFLAGS,$(v)="$($(v))")
CXX_MACRO_EXPORT := $(foreach v,HAVE_NSILMS_INITWITHFILE_1 HAVE_NSILMS_INITALIZE_MUTABLEHANDLE HAVE_NSILMS_TERMINATE_MUTABLEHANDLE HAVE_NSILMS_GETALLENCRYPTEDLOGINS HAVE_MOZGLUE,-D$(v)="$($(v))")

config.vars: config.sh GnomeKeyring.h xpcom_abi.cpp Makefile
	$(SHELL_EXPORT) sh $^ > $@

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

$(TARGET): GnomeKeyring.cpp GnomeKeyring.h
	$(CXX) $< -o $@ -shared $(CXX_MACRO_EXPORT) \
	    $(XUL_CFLAGS) $(XUL_LDFLAGS) $(GNOME_CFLAGS) $(GNOME_LDFLAGS) $(CXXFLAGS) $(LDFLAGS)
	chmod +x $@

tarball:
	git archive --format=tar \
	    --prefix=$(FULLNAME)/ HEAD \
	    | gzip - > $(ARCHIVENAME).tar.gz

.PHONY: clean-all clean
clean:
	rm -f $(TARGET)
	rm -f $(XPI_TARGET)
	rm -f -r xpi

clean-all: clean
	rm -f *.xpi
	rm -f *.tar.gz
	rm -f config.vars xpcom_abi
