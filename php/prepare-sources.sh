#!/bin/sh
# SPDX-FileCopyrightText: 2026 [ernolf] Raphael Gradenwitz <raphael.gradenwitz@googlemail.com>
# SPDX-License-Identifier: MIT
#
# Prepares the patched sources of one PHP minor for install-php-extensions, which
# takes a directory with the package.xml and the source of an extension.
#
#   php/prepare-sources.sh <minor> <directory>
#
# Each directory of php/patches/<minor> is named after its extension and holds a
# file source with the URL of a source tarball and its sha256, and the patches,
# *.patch, applied in the order of their names with patch -p1 in the directory of
# the source. The patched source of each extension ends up in <directory>/<extension>.
# A minor without a directory of its own leaves <directory> empty.

set -eu

minor=$1
dest=$2
patches="$(dirname "$0")/patches/$minor"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$dest"
for dir in "$patches"/*/; do
  [ -f "${dir}source" ] || continue
  e=$(basename "$dir")
  line=$(grep -v '^#' "${dir}source" | head -1)
  url=${line%% *}
  sha=${line##* }
  x="$work/$e"
  mkdir -p "$x"
  curl -fsSL --retry 3 -o "$x.tar.gz" "$url" && printf '%s  %s\n' "$sha" "$x.tar.gz" | sha256sum -c --quiet \
    || { echo "::error::${dir}source: $url could not be fetched or does not match its sha256"; exit 1; }
  tar -xzf "$x.tar.gz" -C "$x"
  top=$(find "$x" -mindepth 1 -maxdepth 1 -type d)
  if [ -z "$top" ] || [ "$(printf '%s\n' "$top" | wc -l)" -ne 1 ]; then
    echo "::error::${dir}source: $url holds no single source directory"
    exit 1
  fi
  # A PECL tarball keeps package.xml beside its source directory, a GitHub tarball
  # inside it.
  [ ! -f "$x/package.xml" ] || mv "$x/package.xml" "$top/"
  for p in "$dir"*.patch; do
    [ -f "$p" ] || continue
    patch -d "$top" -p1 --forward --quiet < "$p" || { echo "::error::$p does not apply to $url"; exit 1; }
  done
  # The package.xml of a PECL release records the md5sum of every file, and pecl
  # refuses a file that a patch changed. The sha256 of the tarball and the
  # reviewed patches already pin the source.
  [ ! -f "$top/package.xml" ] || sed -i 's/ md5sum="[0-9a-f]*"//' "$top/package.xml"
  mv "$top" "$dest/$e"
done
