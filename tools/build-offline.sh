#!/usr/bin/env bash
# Сборка офлайн-наборов пакетов: install.sh подхватывает их сам, интернет не нужен.
# Каждый набор собирается в чистой VM нужной системы (через сам lsw) и содержит
# все зависимости целиком; install.sh ставит из него только недостающее.
#   tools/build-offline.sh                     — Ubuntu 24.04 и 26.04 (ubuntu-22.04, arch — по запросу)
#   tools/build-offline.sh ubuntu-24.04 arch   — выборочно
# Результат: dist/lsw-offline-<система>.tar.gz
set -euo pipefail

ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
LSW=$ROOT/lsw
OUT=$ROOT/dist/offline
info() { printf '\e[1;34m==>\e[0m %s\n' "$*" >&2; }

# в госте общая папка набора смонтирована в /mnt/host
UBUNTU_BUILDER='set -euo pipefail
cd /mnt/host
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dpkg-dev >/dev/null
pkgs="qemu-system-x86 qemu-utils ipxe-qemu seabios xorriso socat openssh-client curl iproute2 samba"
if apt-cache show 7zip >/dev/null 2>&1; then pkgs+=" 7zip"; else pkgs+=" p7zip-full"; fi
if apt-cache show virtiofsd >/dev/null 2>&1; then pkgs+=" virtiofsd"; fi
apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks \
	--no-replaces --no-enhances $pkgs | grep -E "^[a-z0-9]" | sort -u >packages.txt
xargs -a packages.txt -n 1 -P 8 apt-get download -qq 2>download-errors.txt || true
dpkg-scanpackages -m . /dev/null 2>/dev/null | gzip -9 >Packages.gz
echo "$(ls *.deb | wc -l) пакетов, $(du -sh . | cut -f1)"'

ARCH_BUILDER='set -euo pipefail
pkgs="qemu-base libisoburn socat 7zip openssh curl iproute2 samba"
sudo pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null
# пустая база: качаем полное дерево зависимостей, а не только недостающее в этой VM
sudo rm -rf /var/tmp/db /var/tmp/pkgs && sudo mkdir -p /var/tmp/db /var/tmp/pkgs
sudo pacman -Sy --dbpath /var/tmp/db >/dev/null
sudo pacman -Sw --noconfirm --dbpath /var/tmp/db --cachedir /var/tmp/pkgs $pkgs >/dev/null
cp /var/tmp/pkgs/*.pkg.tar.zst* /mnt/host/
cd /mnt/host
repo-add -q lsw-offline.db.tar.gz *.pkg.tar.zst
echo "$(ls *.pkg.tar.zst | wc -l) пакетов, $(du -sh . | cut -f1)"'

targets=("$@")
((${#targets[@]})) || targets=(ubuntu-24.04 ubuntu-26.04)

for t in "${targets[@]}"; do
	case $t in
	ubuntu-26.04) distro=ubuntu builder=$UBUNTU_BUILDER ;;
	ubuntu-*) distro=$t builder=$UBUNTU_BUILDER ;;
	arch) distro=arch builder=$ARCH_BUILDER ;;
	*) echo "неизвестная система: $t" >&2; exit 1 ;;
	esac
	vm=offline-${t//./}
	info "$t: VM $vm"
	rm -rf "${OUT:?}/$t" && mkdir -p "$OUT/$t"
	"$LSW" rm "$vm" -f >/dev/null 2>&1 || true
	"$LSW" install "$distro" "$vm" --cpus 4 --mem 4G --share "$OUT/$t" 2>&1 | grep -v '%' || true
	info "$t: собираю пакеты"
	"$LSW" run "$vm" -- bash -s <<<"$builder"
	"$LSW" rm "$vm" -f >/dev/null

	stage=$(mktemp -d)
	mkdir -p "$stage/lsw/offline"
	cp "$ROOT"/{lsw,install.sh,README.md} "$stage/lsw/"
	cp -r "$OUT/$t" "$stage/lsw/offline/"
	rm -f "$stage/lsw/offline/$t"/{packages.txt,download-errors.txt}
	tar -C "$stage" -czf "$ROOT/dist/lsw-offline-$t.tar.gz" lsw
	rm -rf "$stage"
	info "$t: dist/lsw-offline-$t.tar.gz ($(du -h "$ROOT/dist/lsw-offline-$t.tar.gz" | cut -f1))"
done
