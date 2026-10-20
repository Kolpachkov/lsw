#!/usr/bin/env bash
# Установщик lsw для Ubuntu 22.04+ / Debian 12+ / Arch.
#   ./install.sh               — поставить зависимости и lsw в ~/.local/bin; если рядом есть
#                                офлайн-набор (offline/ubuntu-XX.04/), пакеты ставятся из него без интернета
#   ./install.sh --online      — игнорировать офлайн-набор, ставить из интернета
#   ./install.sh --arm64       — ещё и эмулятор ARM для arm64-гостей (lsw install ubuntu --arch arm64)
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

OFFLINE='' ARM=''
for a in "$@"; do
	case $a in
	--uninstall)
		rm -f "$PREFIX/bin/lsw"
		rm -rf "$PREFIX/share/doc/lsw"
		info "lsw удалён. Виртуалки и образы остались в ~/.local/share/lsw (rm -rf, если не нужны)"
		exit 0
		;;
	--online) OFFLINE=no ;;
	--offline) OFFLINE=1 ;;
	--arm64) ARM=1 ;;
	*) die "неизвестный параметр: $a (--online, --arm64, --uninstall)" ;;
	esac
done
# офлайн-набор подхватывается сам, если он есть для этой системы
. /etc/os-release
if [[ -z $OFFLINE ]] && { [[ -f $SRC/offline/ubuntu-${VERSION_ID:-}/Packages.gz ]] || [[ -f $SRC/offline/arch/lsw-offline.db ]]; }; then
	OFFLINE=1
fi
[[ $OFFLINE == no ]] && OFFLINE=''

[[ -f $SRC/lsw ]] || die "рядом с install.sh нет файла lsw"
[[ $(uname -m) == x86_64 ]] || die "поддерживается только x86_64"
# shellcheck disable=SC1091
. /etc/os-release
info "система: ${PRETTY_NAME:-unknown}"
grep -qE 'vmx|svm' /proc/cpuinfo ||
	warn "процессор не сообщает о VT-x/AMD-V — включи виртуализацию в BIOS, иначе VM будут очень медленными"

# ---------- Debian / Ubuntu ----------

apt_install() {
	# --no-install-recommends, чтобы не тянуть GTK/SDL: нам нужен только headless QEMU
	local pkgs=(qemu-system-x86 qemu-utils ipxe-qemu seabios xorriso socat openssh-client curl iproute2 samba)
	local opts=() repo tmp=''
	if [[ -n $OFFLINE ]]; then
		repo=$SRC/offline/ubuntu-${VERSION_ID:-}
		[[ -f $repo/Packages.gz ]] ||
			die "в наборе нет пакетов для ${PRETTY_NAME:-этой системы} (ждал $repo). Есть: $(ls "$SRC/offline" 2>/dev/null | tr '\n' ' ')"
		# только локальный репозиторий; уже установленное (в т.ч. более новое) apt не трогает
		tmp=$(mktemp -d)
		mkdir -p "$tmp/lists/partial"
		echo "deb [trusted=yes] file:$repo ./" >"$tmp/sources.list"
		opts=(-o "Dir::Etc::SourceList=$tmp/sources.list" -o Dir::Etc::SourceParts=/dev/null
			-o "Dir::State::Lists=$tmp/lists" -o APT::Sandbox::User=root)
		info "офлайн-репозиторий: $repo"
	fi
	$SUDO apt-get "${opts[@]}" update -qq
	[[ -z $ARM ]] || pkgs+=(qemu-system-arm qemu-efi-aarch64)
	if apt-cache "${opts[@]}" show 7zip >/dev/null 2>&1; then pkgs+=(7zip); else pkgs+=(p7zip-full); fi
	if apt-cache "${opts[@]}" show virtiofsd >/dev/null 2>&1; then
		pkgs+=(virtiofsd)
	else
		warn "нет пакета virtiofsd (он есть с Ubuntu 24.04 / Debian 12) — общие папки в Linux-гостях работать не будут"
	fi
	info "ставлю: ${pkgs[*]}"
	$SUDO env DEBIAN_FRONTEND=noninteractive apt-get "${opts[@]}" install -y -qq --no-install-recommends "${pkgs[@]}"
	# lsw запускает свой smbd для Windows-гостей; системная служба samba не нужна
	$SUDO systemctl disable --now smbd nmbd >/dev/null 2>&1 || true
	[[ -z $tmp ]] || rm -rf "$tmp"
}

# ---------- Arch ----------

pacman_install() {
	local pkgs=(qemu-base libisoburn socat 7zip openssh curl iproute2 samba)
	[[ -z $ARM ]] || pkgs+=(qemu-system-aarch64 edk2-aarch64)
	if [[ -n $OFFLINE ]]; then
		local repo=$SRC/offline/arch conf
		[[ -f $repo/lsw-offline.db ]] || die "в наборе нет пакетов для Arch (ждал $repo)"
		conf=$(mktemp)
		cat >"$conf" <<EOF
[options]
Architecture = auto
SigLevel = Never
[lsw-offline]
Server = file://$repo
EOF
		info "офлайн-репозиторий: $repo"
		warn "пакеты из набора могут быть новее системы — pacman обновит и их зависимости"
		$SUDO pacman -Sy --config "$conf"
		$SUDO pacman -S --needed --noconfirm --config "$conf" "${pkgs[@]}"
		$SUDO rm -f /var/lib/pacman/sync/lsw-offline.db
		rm -f "$conf"
	else
		$SUDO pacman -S --needed --noconfirm "${pkgs[@]}"
	fi
	$SUDO systemctl disable --now smb nmb >/dev/null 2>&1 || true
}

if command -v apt-get >/dev/null; then
	apt_install
elif command -v pacman >/dev/null; then
	pacman_install
else
	die "поддерживаются Ubuntu/Debian (apt) и Arch (pacman)"
fi

# ---------- сам lsw ----------

mkdir -p "$PREFIX/bin"
if [[ -d $SRC/.git ]]; then
	# из git-клона — ссылка, чтобы git pull сразу обновлял lsw
	ln -sfn "$SRC/lsw" "$PREFIX/bin/lsw"
else
	rm -f "$PREFIX/bin/lsw"
	install -m755 "$SRC/lsw" "$PREFIX/bin/lsw"
fi
[[ -f $SRC/README.md ]] && install -Dm644 "$SRC/README.md" "$PREFIX/share/doc/lsw/README.md"
info "lsw установлен в $PREFIX/bin/lsw"

relogin=''
if [[ ! -w /dev/kvm ]]; then
	if [[ -e /dev/kvm ]]; then
		$SUDO usermod -aG kvm "${SUDO_USER:-$USER}"
		relogin=1
		warn "добавил ${SUDO_USER:-$USER} в группу kvm — перелогинься (или: newgrp kvm)"
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
  lsw install ubuntu armbox --arch arm64   # нужен ./install.sh --arm64
  lsw
EOF
