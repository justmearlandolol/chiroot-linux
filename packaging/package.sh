#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version' Cargo.toml | head -1 | cut -d'"' -f2)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    DEB_ARCH=amd64
    RPM_ARCH=x86_64
    APPIMAGE_ARCH=x86_64
    ;;
  aarch64|arm64)
    DEB_ARCH=arm64
    RPM_ARCH=aarch64
    APPIMAGE_ARCH=aarch64
    ;;
  *)
    DEB_ARCH="$ARCH"
    RPM_ARCH="$ARCH"
    APPIMAGE_ARCH="$ARCH"
    ;;
esac

BIN=target/release/chiroot
if [ ! -x "$BIN" ]; then
  echo "binary tidak ditemukan, jalankan: cargo build --release"
  exit 1
fi

DIST="$ROOT/dist"
BUILD="$ROOT/build/pkg"
rm -rf "$BUILD" "$DIST"
mkdir -p "$DIST" "$BUILD"

ICONS="$BUILD/icons"
PKGROOT="$BUILD/pkgroot"

make_icons() {
  mkdir -p "$ICONS"
  for s in 16 32 48 64 128 256 512; do
    if command -v rsvg-convert >/dev/null 2>&1; then
      rsvg-convert -w "$s" -h "$s" assets/chiroot.svg -o "$ICONS/chiroot-$s.png"
    elif command -v convert >/dev/null 2>&1; then
      convert assets/chiroot.png -resize "${s}x${s}" "$ICONS/chiroot-$s.png"
    else
      cp assets/chiroot.png "$ICONS/chiroot-$s.png"
    fi
  done
}

make_pkgroot() {
  mkdir -p "$PKGROOT/usr/bin"
  mkdir -p "$PKGROOT/usr/share/applications"
  mkdir -p "$PKGROOT/usr/share/pixmaps"
  mkdir -p "$PKGROOT/usr/share/icons/hicolor/scalable/apps"
  mkdir -p "$PKGROOT/usr/share/icons/hicolor/64x64/apps"
  cp "$BIN" "$PKGROOT/usr/bin/chiroot"
  chmod 755 "$PKGROOT/usr/bin/chiroot"
  cp packaging/chiroot.desktop "$PKGROOT/usr/share/applications/chiroot.desktop"
  cp assets/chiroot.svg "$PKGROOT/usr/share/icons/hicolor/scalable/apps/chiroot.svg"
  cp "$ICONS/chiroot-64.png" "$PKGROOT/usr/share/icons/hicolor/64x64/apps/chiroot.png"
  cp "$ICONS/chiroot-64.png" "$PKGROOT/usr/share/pixmaps/chiroot.png"
  for s in 16 32 48 128 256 512; do
    mkdir -p "$PKGROOT/usr/share/icons/hicolor/${s}x${s}/apps"
    cp "$ICONS/chiroot-$s.png" "$PKGROOT/usr/share/icons/hicolor/${s}x${s}/apps/chiroot.png"
  done
}

make_deb() {
  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "dpkg-deb tidak ada, skip deb"
    return
  fi
  STAGE="$BUILD/deb"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/DEBIAN"
  cp -a "$PKGROOT/usr" "$STAGE/"
  cat > "$STAGE/DEBIAN/control" <<EOF
Package: chiroot
Version: $VERSION
Section: sound
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Chiroot <admin@chiroot.my.id>
Depends: libwebkit2gtk-4.1-0, libgtk-3-0
Description: Chiroot Free Audio Player Tanpa Iklan
 Aplikasi desktop Chiroot untuk Linux.
EOF
  dpkg-deb --build --root-owner-group "$STAGE" "$DIST/chiroot-${DEB_ARCH}.deb" >/dev/null
  echo "deb: dist/chiroot-${DEB_ARCH}.deb"
}

make_rpm() {
  if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "rpmbuild tidak ada, skip rpm"
    return
  fi
  RPMROOT="$BUILD/rpmbuild"
  rm -rf "$RPMROOT"
  mkdir -p "$RPMROOT/BUILD" "$RPMROOT/BUILDROOT" "$RPMROOT/RPMS" "$RPMROOT/SOURCES" "$RPMROOT/SPECS" "$RPMROOT/SRPMS"
  SPEC="$RPMROOT/SPECS/chiroot.spec"
  sed -e "s/^Version:.*/Version: $VERSION/" -e "s/^BuildArch:.*/BuildArch: $RPM_ARCH/" packaging/chiroot.spec > "$SPEC"
  rpmbuild -bb "$SPEC" \
    --define "_topdir $RPMROOT" \
    --define "_sourcedir $PKGROOT" \
    --target "$RPM_ARCH" >/dev/null
  RPM_FILE="$(find "$RPMROOT/RPMS" -name 'chiroot-*.rpm' | head -1)"
  if [ -n "$RPM_FILE" ]; then
    cp "$RPM_FILE" "$DIST/chiroot-${RPM_ARCH}.rpm"
    echo "rpm: dist/chiroot-${RPM_ARCH}.rpm"
  fi
}

make_tarball() {
  T="$BUILD/chiroot-linux-$ARCH"
  rm -rf "$T"
  mkdir -p "$T"
  cp "$PKGROOT/usr/bin/chiroot" "$T/chiroot"
  cp packaging/chiroot.desktop "$T/chiroot.desktop"
  cp packaging/install.sh "$T/install.sh"
  cp assets/chiroot.png "$T/chiroot.png"
  cp assets/chiroot.svg "$T/chiroot.svg"
  cp README.md "$T/README.md" 2>/dev/null || true
  chmod 755 "$T/chiroot" "$T/install.sh"
  tar -czf "$DIST/chiroot-linux-${ARCH}.tar.gz" -C "$BUILD" "chiroot-linux-$ARCH"
  echo "tarball: dist/chiroot-linux-${ARCH}.tar.gz"
}

make_appimage() {
  APPDIR="$BUILD/Chiroot.AppDir"
  rm -rf "$APPDIR"
  mkdir -p "$APPDIR/usr/bin"
  mkdir -p "$APPDIR/usr/share/applications"
  mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
  cp "$PKGROOT/usr/bin/chiroot" "$APPDIR/usr/bin/chiroot"
  cp packaging/chiroot.desktop "$APPDIR/chiroot.desktop"
  cp packaging/chiroot.desktop "$APPDIR/usr/share/applications/chiroot.desktop"
  cp packaging/AppRun "$APPDIR/AppRun"
  cp assets/chiroot.svg "$APPDIR/usr/share/icons/hicolor/scalable/apps/chiroot.svg"
  cp "$ICONS/chiroot-256.png" "$APPDIR/chiroot.png"
  cp "$ICONS/chiroot-256.png" "$APPDIR/.DirIcon"
  chmod 755 "$APPDIR/AppRun" "$APPDIR/usr/bin/chiroot"
  TOOL="$BUILD/appimagetool"
  if [ ! -x "$TOOL" ]; then
    curl -fsSL -o "$TOOL" \
      https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage \
      || { echo "appimagetool tidak bisa didownload, skip AppImage"; return; }
    chmod +x "$TOOL"
  fi
  ARCH="$APPIMAGE_ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" -n "$APPDIR" \
    "$DIST/Chiroot-${APPIMAGE_ARCH}.AppImage" >/dev/null 2>&1 \
    || { echo "appimagetool gagal, skip AppImage"; return; }
  echo "appimage: dist/Chiroot-${APPIMAGE_ARCH}.AppImage"
}

make_checksums() {
  cp packaging/install.sh "$DIST/install.sh"
  chmod 755 "$DIST/install.sh"
  cd "$DIST"
  rm -f SHA256SUMS
  for f in *; do
    if [ "$f" != "SHA256SUMS" ]; then
      sha256sum "$f" >> SHA256SUMS
    fi
  done
  cd "$ROOT"
}

make_icons
make_pkgroot
make_deb
make_rpm
make_tarball
make_appimage
make_checksums

echo ""
echo "selesai, isi dist/:"
ls -la "$DIST"
