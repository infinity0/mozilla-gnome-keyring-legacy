#!/bin/sh
# Sets build-environment variables. Like ./configure but without the overhead.

SRC_GNOME_KEYRING_H="$1"
SRC_XPCOM_ABI_CPP="$2"

set -o errexit

XUL_VERSION=$(echo '#include "mozilla-config.h"'|
		${CXX} ${XUL_CFLAGS} ${CXXFLAGS} -shared -x c++ -w -E -fdirectives-only - |
		sed -n -e 's/\#[[:space:]]*define[[:space:]]\+MOZILLA_VERSION[[:space:]]\+\"\(.*\)\"/\1/gp')

XUL_VER_MIN=$(echo $XUL_VERSION | sed -r -e 's/([^.]+\.[^.]+).*/\1/g')
XUL_VER_MAX=$(echo $XUL_VERSION | sed -rn -e 's/([^.]+).*/\1.*/gp')

HAVE_NSILMS_GETISLOGGEDIN=$({ cat <<EOF; } | $CXX $XUL_CFLAGS $GNOME_CFLAGS $CXXFLAGS -x c++ -w -c -o /dev/null - 2>/dev/null && echo 1 || echo 0
#include "$SRC_GNOME_KEYRING_H"
NS_IMETHODIMP GnomeKeyring::GetIsLoggedIn(bool *aIsLoggedIn) { return NS_OK; }
EOF
)

HAVE_NSILMS_INITWITHFILE_2=$({ cat <<EOF; } | $CXX $XUL_CFLAGS $GNOME_CFLAGS $CXXFLAGS -x c++ -w -c -o /dev/null - 2>/dev/null && echo 1 || echo 0
#include "$SRC_GNOME_KEYRING_H"
NS_IMETHODIMP GnomeKeyring::InitWithFile(nsIFile *aInputFile, nsIFile *aOutputFile) { return NS_OK; }
EOF
)

HAVE_MOZ_BUG_956507=$({ cat <<EOF; } | $CXX $XUL_CFLAGS $GNOME_CFLAGS $CXXFLAGS -x c++ -w -c -o /dev/null - 2>/dev/null && echo 0 || echo 1
#include <nspr/prtypes.h>
#include "mozilla/Char16.h"
EOF
)

HAVE_MOZGLUE=$($CXX $XUL_CFLAGS $XUL_LDFLAGS $XPCOM_ABI_FLAGS $CXXFLAGS $LDFLAGS -lmozglue -shared -o /dev/null && echo 1 || echo 0)

if [ $HAVE_MOZGLUE = 1 ]; then
	XPCOM_ABI_FLAGS="$XPCOM_ABI_FLAGS -Wl,-whole-archive -lmozglue -Wl,-no-whole-archive"
fi
DST_XPCOM_ABI="$(dirname $0)/xpcom_abi"
$CXX $SRC_XPCOM_ABI_CPP -DHAVE_MOZ_BUG_956507="$HAVE_MOZ_BUG_956507" -o "$DST_XPCOM_ABI" \
  $XUL_CFLAGS $XUL_LDFLAGS $XPCOM_ABI_FLAGS $CXXFLAGS $LDFLAGS
PLATFORM="$("$DST_XPCOM_ABI")"

for var in XUL_VERSION XUL_VER_MIN XUL_VER_MAX PLATFORM \
  HAVE_NSILMS_GETISLOGGEDIN HAVE_NSILMS_INITWITHFILE_2 HAVE_MOZ_BUG_956507 HAVE_MOZGLUE; do
	eval val=\$$var
	echo export $var=$val
done;
echo export HAVE_CONFIG_VARS=1
