#!/usr/bin/env bash
# Установщик lsw для Ubuntu / Debian.
#   ./install.sh               — поставить зависимости и lsw в ~/.local/bin
#   ./install.sh --uninstall   — удалить lsw (VM в ~/.local/share/lsw не трогает)
#   PREFIX=/usr/local sudo -E ./install.sh — установить для всех
set -euo pipefail

SRC=$(dirname "$(readlink -f "$0")")
PREFIX=${PREFIX:-$HOME/.local}

info() { printf '\e[1;34m::\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m!!\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m!!\e[0m %s\n' "$*" >&2; exit 1; }

SUDO=sudo
[[ $EUID == 0 ]] && SUDO=

if [[ ${1:-} == --uninstall ]]; then
	rm -f "$PREFIX/bin/lsw"
	rm -rf "$PREFIX/share/doc/lsw"
	info "lsw удалён. Виртуалки и образы остались в ~/.local/share/lsw (rm -rf, если не нужны)"
	exit 0
fi

[[ -f $SRC/lsw ]] || die "рядом с install.sh нет файла lsw"
command -v apt-get >/dev/null || die "нужна Ubuntu/Debian (apt). На Arch: sudo pacman -S qemu-base libisoburn socat"
[[ $(uname -m) == x86_64 ]] || die "поддерживается только x86_64"

# shellcheck disable=SC1091
. /etc/os-release
info "система: ${PRETTY_NAME:-unknown}"

grep -qE 'vmx|svm' /proc/cpuinfo ||
	warn "процессор не сообщает о VT-x/AMD-V — включи виртуализацию в BIOS, иначе VM будут очень медленными"

# --no-install-recommends, чтобы не тянуть GTK/SDL: нам нужен только headless QEMU
pkgs=(qemu-system-x86 qemu-utils ipxe-qemu seabios xorriso socat openssh-client curl iproute2)
info "обновляю список пакетов"
$SUDO apt-get update -qq
if apt-cache show virtiofsd >/dev/null 2>&1; then
	pkgs+=(virtiofsd)
else
	warn "в репозиториях нет virtiofsd (нужна Ubuntu 24.04+ / Debian 12+)."
	warn "общая папка работать не будет — создавай VM с --no-share"
fi
info "ставлю: ${pkgs[*]}"
$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${pkgs[@]}"

install -Dm755 "$SRC/lsw" "$PREFIX/bin/lsw"
[[ -f $SRC/README.md ]] && install -Dm644 "$SRC/README.md" "$PREFIX/share/doc/lsw/README.md"
info "lsw установлен в $PREFIX/bin/lsw"

relogin=''
if [[ ! -w /dev/kvm ]]; then
	if [[ -e /dev/kvm ]]; then
		$SUDO usermod -aG kvm "${SUDO_USER:-$USER}"
		relogin=1
		warn "добавил $USER в группу kvm — перелогинься (или: newgrp kvm)"
	else
		warn "/dev/kvm нет: включи виртуализацию в BIOS (в облачной VM нужна nested virtualization)"
	fi
fi

case ":$PATH:" in
*":$PREFIX/bin:"*) ;;
*) if [[ $PREFIX == "$HOME/.local" ]] && grep -q '.local/bin' ~/.profile 2>/dev/null; then
	warn "~/.local/bin появится в PATH после перелогина"
else
	warn "$PREFIX/bin не в PATH — добавь: echo 'export PATH=\"$PREFIX/bin:\$PATH\"' >> ~/.bashrc"
fi ;;
esac

[[ -n $relogin ]] || "$PREFIX/bin/lsw" deps || true
cat <<EOF

Готово. Дальше:
  lsw install ubuntu
  lsw install arch
  lsw install windows --iso ~/Downloads/Win10.iso
  lsw
EOF
