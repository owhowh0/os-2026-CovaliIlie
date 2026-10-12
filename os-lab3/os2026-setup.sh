#!/usr/bin/env bash
# OS 2026 (UTM, FCIM/FAF) - laptop setup for the labs
#
# Installs everything the labs need on a Linux laptop, downloads xv6 into
# ~/xv6-riscv, builds it and boots it once to prove it works.
#
#   bash os2026-setup.sh          install + build + test
#   bash os2026-setup.sh --check  only test what is already there
#
# Supported: Ubuntu / Debian / Mint / Pop!_OS (apt), Fedora (dnf),
# Arch / Manjaro / EndeavourOS (pacman), openSUSE (zypper).
# Safe to run more than once. It never deletes your work in ~/xv6-riscv.

set -u

XV6_URL="https://github.com/mit-pdos/xv6-riscv.git"
XV6_REV="06aad25"          # revision the labs were tested on
XV6_DIR="$HOME/xv6-riscv"

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'
ok()   { echo "${G}[ OK ]${N} $*"; }
warn() { echo "${Y}[WARN]${N} $*"; }
fail() { echo "${R}[FAIL]${N} $*"; }
step() { echo; echo "${B}==> $*${N}"; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# ---------------------------------------------------------------- distro
. /etc/os-release 2>/dev/null || true
FAMILY=""
case " ${ID:-} ${ID_LIKE:-} " in
  *" arch "*|*" manjaro "*)          FAMILY=arch ;;
  *" fedora "*|*" rhel "*)           FAMILY=fedora ;;
  *" opensuse"*|*" suse "*|*" sles "*) FAMILY=suse ;;
  *" debian "*|*" ubuntu "*)         FAMILY=debian ;;
esac
echo "${B}OS 2026 setup${N}  system: ${PRETTY_NAME:-unknown}  family: ${FAMILY:-unknown}"

# ---------------------------------------------------------------- install
install_packages() {
  case "$FAMILY" in
    debian)
      $SUDO apt-get update -y || return 1
      QEMU_PKG=qemu-system-misc
      if apt-cache show qemu-system-riscv >/dev/null 2>&1; then QEMU_PKG=qemu-system-riscv; fi
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
        git make gcc build-essential gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu \
        "$QEMU_PKG" man-db cron python3 bc ;;
    fedora)
      $SUDO dnf install -y git make gcc gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu \
        qemu-system-riscv man-db cronie python3 bc ;;
    arch)
      $SUDO pacman -Sy --needed --noconfirm git make gcc riscv64-elf-gcc riscv64-elf-binutils \
        qemu-system-riscv man-db cronie python bc ;;
    suse)
      $SUDO zypper --non-interactive install git make gcc cross-riscv64-gcc14 cross-riscv64-binutils \
        qemu-extra man cron python3 bc ;;
    *)
      fail "Unknown distribution. Install by hand: git, make, gcc, a riscv64 cross gcc, qemu-system-riscv64."
      return 1 ;;
  esac
}

qemu_ok() {   # true if qemu-system-riscv64 exists and is 7.2 or newer
  command -v qemu-system-riscv64 >/dev/null 2>&1 || return 1
  local v; v="$(qemu-system-riscv64 --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  local ma="${v%%.*}" mi="${v#*.}"
  [ "${ma:-0}" -gt 7 ] || { [ "${ma:-0}" -eq 7 ] && [ "${mi:-0}" -ge 2 ]; }
}

# Ubuntu 22.04 / Mint 21 / Debian 11 ship QEMU 6.x, too old for current xv6
# (it uses the Sstc timer extension). Build a recent QEMU, RISC-V target only.
build_qemu() {
  local QVER=8.2.7
  warn "your QEMU is too old for xv6, building QEMU $QVER (RISC-V only, about 5 to 10 minutes)"
  if [ "$FAMILY" = debian ]; then
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y ninja-build pkg-config libglib2.0-dev \
      libpixman-1-dev python3-venv flex bison wget xz-utils || return 1
  fi
  local W; W="$(mktemp -d)"
  ( cd "$W" && wget -q "https://download.qemu.org/qemu-$QVER.tar.xz" && tar xf "qemu-$QVER.tar.xz" \
    && cd "qemu-$QVER" && ./configure --target-list=riscv64-softmmu --prefix=/usr/local \
         --disable-docs --disable-werror >/tmp/os2026-qemu.log 2>&1 \
    && make -j"$(nproc)" >>/tmp/os2026-qemu.log 2>&1 \
    && $SUDO make install >>/tmp/os2026-qemu.log 2>&1 ) || { tail -20 /tmp/os2026-qemu.log; return 1; }
  rm -rf "$W"; hash -r
  ok "QEMU $QVER installed in /usr/local/bin"
}

# The xv6 Makefile looks for riscv64-unknown-elf-, riscv64-elf-, riscv64-linux-gnu-
# and riscv64-unknown-linux-gnu-. openSUSE names its compiler differently.
find_prefix() {
  for p in riscv64-unknown-elf- riscv64-elf- riscv64-linux-gnu- riscv64-unknown-linux-gnu- riscv64-suse-linux-; do
    if command -v "${p}gcc" >/dev/null 2>&1; then echo "$p"; return 0; fi
  done
  return 1
}

if [ $CHECK_ONLY -eq 0 ]; then
  step "1/4  Installing packages (your password may be asked once)"
  if install_packages; then ok "packages installed"; else fail "package install failed, read the messages above"; exit 1; fi
  if ! qemu_ok; then build_qemu || { fail "could not build QEMU, show this screen to the assistant"; exit 1; }; fi
fi

# ---------------------------------------------------------------- tools
step "2/4  Checking the tools"
ERR=0
for t in git make gcc bash grep sed awk; do
  if command -v $t >/dev/null 2>&1; then ok "$t"; else fail "$t missing"; ERR=1; fi
done
PREFIX="$(find_prefix || true)"
if [ -n "$PREFIX" ]; then ok "RISC-V compiler: ${PREFIX}gcc"; else fail "no RISC-V cross compiler found"; ERR=1; fi
if command -v qemu-system-riscv64 >/dev/null 2>&1; then
  QV="$(qemu-system-riscv64 --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  ok "QEMU $QV"
  if ! qemu_ok; then fail "QEMU $QV is too old (xv6 needs 7.2 or newer), run the script without --check"; ERR=1; fi
else
  fail "qemu-system-riscv64 missing"; ERR=1
fi
if [ "$PREFIX" = "riscv64-suse-linux-" ]; then
  export TOOLPREFIX="$PREFIX"
  grep -q "TOOLPREFIX=" "$HOME/.bashrc" 2>/dev/null || echo "export TOOLPREFIX=$PREFIX" >> "$HOME/.bashrc"
fi
[ $ERR -eq 0 ] || { fail "fix the missing tools, then run this script again"; exit 1; }

# ---------------------------------------------------------------- xv6
step "3/4  xv6 in $XV6_DIR"
if [ -d "$XV6_DIR/.git" ]; then
  ok "already present, left as it is (your work is safe)"
elif [ $CHECK_ONLY -eq 1 ]; then
  fail "$XV6_DIR does not exist, run the script without --check"; exit 1
else
  git clone -q "$XV6_URL" "$XV6_DIR" || { fail "git clone failed (internet?)"; exit 1; }
  git -C "$XV6_DIR" -c advice.detachedHead=false checkout -q "$XV6_REV" \
    && git -C "$XV6_DIR" switch -q -c lab \
    && ok "downloaded, revision $XV6_REV, branch lab"
fi

# ---------------------------------------------------------------- build + boot
step "4/4  Building xv6 and booting it once"
cd "$XV6_DIR" || exit 1
if make -s kernel/kernel fs.img >/tmp/os2026-build.log 2>&1; then
  ok "build"
else
  fail "build failed, last lines of /tmp/os2026-build.log:"; tail -15 /tmp/os2026-build.log; exit 1
fi
# Ctrl-A X at the end makes QEMU quit, so no QEMU is left holding fs.img
OUT="$( (sleep 10; echo ls; sleep 3; printf '\001x') | timeout -k 5 60 make qemu CPUS=1 2>&1 )"
if echo "$OUT" | grep -q "README"; then
  ok "xv6 booted and ran ls"
  echo
  echo "${G}${B}All set.${N} Start xv6 with:  ${B}cd ~/xv6-riscv && make qemu${N}"
  echo "Leave xv6 with: Ctrl-A, then X."
else
  fail "xv6 did not answer. Last lines:"; echo "$OUT" | tail -15; exit 1
fi
