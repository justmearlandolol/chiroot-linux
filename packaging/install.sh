#!/bin/sh
set -e

APP=chiroot
DESKTOP_FILE=chiroot.desktop
PNG_ICON=chiroot.png
SVG_ICON=chiroot.svg
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE=install
PREFIX=/usr/local
USE_SUDO=1

print_help() {
  echo "Chiroot Linux installer"
  echo ""
  echo "Usage: sh install.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --user           install ke ~/.local tanpa root"
  echo "  --from-source    build dari source (butuh rust + libwebkit2gtk-4.1-dev)"
  echo "  --uninstall      hapus instalasi Chiroot"
  echo "  --help           tampilkan bantuan ini"
}

for arg in "$@"; do
  case "$arg" in
    --user)
      PREFIX="$HOME/.local"
      USE_SUDO=0
      ;;
    --from-source)
      MODE=source
      ;;
    --uninstall)
      MODE=uninstall
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      echo "option tidak dikenal: $arg"
      print_help
      exit 1
      ;;
  esac
done

as_root() {
  if [ "$USE_SUDO" = "1" ] && [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo "$@"
      return
    fi
    echo "butuh root, jalankan dengan sudo"
    exit 1
  fi
  "$@"
}

sys_run() {
  if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo "$@"
      return
    fi
    echo "butuh root untuk install dependency sistem"
    exit 1
  fi
  "$@"
}

detect_family() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
  else
    OS_ID=unknown
    OS_LIKE=""
  fi
  case "$OS_ID" in
    debian|ubuntu|linuxmint|pop|kali|raspbian|elementary|zorin|neon)
      FAMILY=debian
      ;;
    fedora|rhel|centos|rocky|almalinux|nobara|ol|scientific)
      FAMILY=fedora
      ;;
    arch|manjaro|endeavouros|garuda|artix|cachyos)
      FAMILY=arch
      ;;
    opensuse*|sles|sled|suse*)
      FAMILY=suse
      ;;
    void)
      FAMILY=void
      ;;
    gentoo|funtoo)
      FAMILY=gentoo
      ;;
    alpine)
      FAMILY=alpine
      ;;
    *)
      case " $OS_LIKE " in
        *debian*|*ubuntu*) FAMILY=debian ;;
        *fedora*|*rhel*|*centos*) FAMILY=fedora ;;
        *arch*) FAMILY=arch ;;
        *suse*) FAMILY=suse ;;
        *) FAMILY=unknown ;;
      esac
      ;;
  esac
}

install_deps() {
  detect_family
  echo "distro terdeteksi: $OS_ID ($FAMILY)"
  case "$FAMILY" in
    debian)
      sys_run apt-get update -qq || true
      sys_run apt-get install -y libwebkit2gtk-4.1-0 libgtk-3-0
      ;;
    fedora)
      sys_run dnf install -y webkit2gtk4.1 gtk3
      ;;
    arch)
      sys_run pacman -Sy --needed --noconfirm webkit2gtk-4.1 gtk3
      ;;
    suse)
      sys_run zypper --non-interactive install libwebkit2gtk-4_1-0 libgtk-3-0
      ;;
    void)
      sys_run xbps-install -Sy webkit2gtk gtk+3
      ;;
    gentoo)
      sys_run emerge --ask n net-libs/webkit-gtk x11-libs/gtk+
      ;;
    alpine)
      sys_run apk add webkit2gtk-4.1 gtk+3.0
      ;;
    *)
      echo "distro tidak dikenal, install manual: webkit2gtk-4.1 + gtk3"
      ;;
  esac
}

find_binary() {
  for c in "$SRC_DIR/$APP" "$SRC_DIR/bin/$APP" "$SRC_DIR/target/release/$APP" "$SRC_DIR/../target/release/$APP"; do
    if [ -x "$c" ]; then
      echo "$c"
      return
    fi
  done
  echo ""
}

find_asset() {
  for c in "$SRC_DIR/$1" "$SRC_DIR/assets/$1" "$SRC_DIR/packaging/$1" "$SRC_DIR/../assets/$1"; do
    if [ -f "$c" ]; then
      echo "$c"
      return
    fi
  done
  echo ""
}

build_from_source() {
  if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo tidak ditemukan, install Rust dulu: https://rustup.rs"
    exit 1
  fi
  detect_family
  case "$FAMILY" in
    debian)
      sys_run apt-get update -qq || true
      sys_run apt-get install -y build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
      ;;
    fedora)
      sys_run dnf install -y gcc pkgconf-pkg-config gtk3-devel webkit2gtk4.1-devel
      ;;
    arch)
      sys_run pacman -Sy --needed --noconfirm base-devel gtk3 webkit2gtk-4.1
      ;;
    suse)
      sys_run zypper --non-interactive install gcc make pkgconf-pkg-config gtk3-devel webkit2gtk4.1-devel
      ;;
    *)
      echo "install manual dev libs: gtk3 + webkit2gtk-4.1"
      ;;
  esac
  ROOT_DIR="$(cd "$SRC_DIR/.." && pwd)"
  if [ ! -f "$ROOT_DIR/Cargo.toml" ]; then
    echo "source tidak ditemukan di $ROOT_DIR"
    exit 1
  fi
  (cd "$ROOT_DIR" && cargo build --release)
  BIN_PATH="$ROOT_DIR/target/release/$APP"
  if [ ! -x "$BIN_PATH" ]; then
    echo "build gagal"
    exit 1
  fi
}

install_files() {
  BIN="$1"
  as_root install -Dm755 "$BIN" "$PREFIX/bin/$APP"
  DESKTOP_PATH="$(find_asset "$DESKTOP_FILE")"
  if [ -n "$DESKTOP_PATH" ]; then
    as_root install -Dm644 "$DESKTOP_PATH" "$PREFIX/share/applications/$DESKTOP_FILE"
  fi
  PNG_PATH="$(find_asset "$PNG_ICON")"
  SVG_PATH="$(find_asset "$SVG_ICON")"
  if [ -n "$PNG_PATH" ]; then
    as_root install -Dm644 "$PNG_PATH" "$PREFIX/share/icons/hicolor/64x64/apps/$APP.png"
    as_root install -Dm644 "$PNG_PATH" "$PREFIX/share/pixmaps/$APP.png"
  fi
  if [ -n "$SVG_PATH" ]; then
    as_root install -Dm644 "$SVG_PATH" "$PREFIX/share/icons/hicolor/scalable/apps/$APP.svg"
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    as_root update-desktop-database "$PREFIX/share/applications" >/dev/null 2>&1 || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    as_root gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
  fi
}

uninstall_files() {
  as_root rm -f "$PREFIX/bin/$APP"
  as_root rm -f "$PREFIX/share/applications/$DESKTOP_FILE"
  as_root rm -f "$PREFIX/share/icons/hicolor/64x64/apps/$APP.png"
  as_root rm -f "$PREFIX/share/icons/hicolor/scalable/apps/$APP.svg"
  as_root rm -f "$PREFIX/share/pixmaps/$APP.png"
  echo "Chiroot dihapus dari $PREFIX"
}

case "$MODE" in
  uninstall)
    uninstall_files
    ;;
  source)
    echo "build dari source..."
    build_from_source
    install_deps
    install_files "$BIN_PATH"
    echo "Chiroot terinstall di $PREFIX/bin/$APP"
    ;;
  install)
    BIN="$(find_binary)"
    if [ -z "$BIN" ]; then
      echo "binary $APP tidak ditemukan di $SRC_DIR"
      echo "jalankan dengan --from-source untuk build sendiri"
      exit 1
    fi
    install_deps
    install_files "$BIN"
    echo "Chiroot terinstall di $PREFIX/bin/$APP"
    echo "jalankan: chiroot"
    ;;
esac
