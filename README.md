# lsw

Аналог WSL для Linux: лёгкие headless-виртуалки на QEMU/KVM, управляемые одной bash-утилитой.
Гости: **Ubuntu** (26.04 / 24.04), **Arch**, **Windows 10**, а также **Ubuntu arm64** под эмуляцией. Без GUI, вход через терминал (ssh).

## Установка

**Ubuntu 24.04+ / Debian 12+:**
```sh
gh release download -R Kolpachkov/lsw -p 'lsw-ubuntu.tar.gz'
tar xzf lsw-ubuntu.tar.gz && cd lsw && ./install.sh   # потом перелогиниться
```

**Ubuntu без интернета** — в релизе есть наборы со всеми пакетами (24.04 и 26.04).
Скачай на любой машине `lsw-offline-ubuntu-<версия>.tar.gz` под свою версию (`lsb_release -rs`), перенеси и:
```sh
tar xzf lsw-offline-ubuntu-24.04.tar.gz && cd lsw && ./install.sh   # пакеты ставятся из набора сами
```
Ставится только недостающее, уже установленные пакеты не трогаются. Образы VM в набор не входят:
для `lsw install ubuntu|arch` нужен интернет (или ISO: `lsw install ubuntu --iso …`).
Пересобрать наборы: `tools/build-offline.sh`.

**Arch:**
```sh
sudo pacman -S --needed qemu-base libisoburn socat 7zip
git clone https://github.com/Kolpachkov/lsw ~/lsw && ln -s ~/lsw/lsw ~/.local/bin/lsw
```

**Обновление:**
```sh
lsw upgrade --check           # есть ли новая версия
lsw upgrade                   # git-клон — git pull; установка из релиза — последний lsw-ubuntu.tar.gz
lsw upgrade --from lsw-offline-ubuntu-24.04.tar.gz   # без интернета, из перенесённого архива
```
Виртуалки, диски и настройки (`~/.local/share/lsw`) не трогаются, запущенные VM продолжают работать.
Если новой версии нужны новые пакеты, `lsw upgrade` скажет об этом; тогда запусти `./install.sh` из нового архива.

## Использование

```sh
lsw install ubuntu            # ~1 мин: cloud-образ + cloud-init, изолирована
lsw install arch
lsw install windows --iso ~/Downloads/Win10_22H2_Russian_x64.iso   # 15–40 мин без участия

lsw                           # shell в VM по умолчанию
lsw shell arch
lsw run ubuntu -- uname -a
lsw run windows -- Get-ComputerInfo
lsw list
lsw stop --all
```

## ARM (arm64)

```sh
./install.sh --arm64                     # или: sudo pacman -S qemu-system-aarch64 edk2-aarch64
                                         #      sudo apt install qemu-system-arm qemu-efi-aarch64
lsw install ubuntu armbox --arch arm64   # также ubuntu-24.04 / ubuntu-22.04
lsw run armbox -- uname -m                # aarch64
```

Настоящая ARM-машина (`virt`, UEFI, своё ядро и systemd) на официальном arm64 cloud-образе Ubuntu.
KVM для ARM на x86 не бывает, поэтому это **программная эмуляция** (многопоточный TCG):
в 5–10 раз медленнее нативной VM, первая загрузка с cloud-init — 5–15 минут. Для терминала, сборки
и тестов под arm64 хватает; общие папки (`--share`) работают так же, через virtiofs.
Только Ubuntu: у Arch Linux ARM нет cloud-образа, Windows on ARM не поддерживается.
Если нужно лишь запускать arm64-бинарники или собирать образы, легче `qemu-user-static` + binfmt
(`docker run --platform linux/arm64 …`).

## Как устроено

| | Linux | Windows 10 |
|---|---|---|
| Установка | официальный cloud-образ → копия qcow2 → cloud-init (пользователь, ключ, hostname) | ISO + собственный `autounattend.xml` на втором CD, BIOS, разметка MBR |
| Вход | ssh, ключ `~/.local/share/lsw/id_ed25519` | Win32-OpenSSH, по умолчанию PowerShell |
| Диск / сеть | virtio-blk, virtio-net | AHCI, e1000e (драйверы встроены, virtio-win не нужен) |
| Общая папка | по умолчанию нет; `--share DIR[:ro]` → `/mnt/host` через virtiofs | `\\10.0.2.4\qemu`, если на хосте стоит `samba` |
| Память | balloon с free-page-reporting: свободная память гостя возвращается хосту | — |
| Консоль | `lsw console` — ttyS0 | `lsw console` — SAC (EMS) на COM1 |

Сеть — user-mode (slirp), root не нужен. Наружу торчит только `127.0.0.1:<порт>` → гость:22.

## Изоляция и общие папки

По умолчанию VM **изолирована**: файлов хоста она не видит. Папку открывают явно:

```sh
lsw install ubuntu dev --share ~/Work        # чтение и запись
lsw share dev ~/Work/project:ro              # сменить: только чтение (запрет на стороне хоста, root гостя не обойдёт)
lsw share dev off                            # снова изолировать
lsw restart dev                              # изменения применяются после перезапуска
```

В госте папка смонтирована в `/mnt/host`, а в домашнем каталоге есть ссылка с тем же именем (`~/database` → `/mnt/host`).
Если ты стоишь внутри общей папки, `lsw shell` откроется в той же папке гостя, как в WSL.

Сеть: гость выходит в интернет через user-mode NAT, а **сервисы хоста на `localhost` доступны ему по `10.0.2.2`**.
Не держи на `127.0.0.1` хоста ничего без пароля, если запускаешь в VM недоверенный код.

Файлы: `~/.local/share/lsw/vms/<имя>/` (диск, `vm.conf`, логи, сокеты QMP и консоли),
базовые образы кешируются в `~/.local/share/lsw/cache/`.

## Ubuntu с ISO

Обычно ISO не нужен: `lsw install ubuntu` ставит ту же Ubuntu Server из cloud-образа за минуту.
Если нужен именно ISO (офлайн, точная версия), подходит только **Server** ISO:

```sh
lsw install ubuntu --iso ubuntu-22.04.5-live-server-amd64.iso   # VM назовётся ubuntu-2204
```

lsw достаёт из ISO ядро, грузит установщик с `autoinstall` и ответами через cloud-init seed,
показывает прогресс по серийной консоли (5–15 мин). Установщику на это время даётся минимум 4 ГБ RAM.
Итог — такая же VM, как из cloud-образа. Desktop ISO отклоняется: его установщик графический.

## Пользователь и пароль

Логин — твой `$USER`, пароль по умолчанию такой же (`--password` при установке), он лежит в `vms/<имя>/password`.
В Linux ssh по паролю выключен, пароль нужен только для `lsw console`. Не используй в пароле `' | & <`.

## Windows: подробности

- Нужен свой ISO Windows 10 ([официальная загрузка Microsoft](https://www.microsoft.com/software-download/windows10)).
  Язык установки определяется по `sources/lang.ini`.
- ISO Microsoft записаны в UDF, их читает только `7z` (пакет `7zip`). Без него lsw не проверит ISO и
  определит язык по имени файла (`ru_windows_…`, `…_Russian_…`), либо задай `--lang ru-RU`.
- Поддерживается Windows 10 любого билда, включая первый 10240. Windows 11 пока нет (нужны UEFI + TPM).
- Редакция выбирается generic-ключом Pro (установка без активации). Свой ключ — `--key`, другая редакция — `--edition N`
  (индекс в `install.wim`/`esd`, посмотреть: `wiminfo` из `wimlib`).
- Посмотреть экран установки, если что-то пошло не так: `lsw install windows --iso ... --vnc`, затем
  `vncviewer 127.0.0.1:59xx`.
- Если Windows виснет на загрузке (бывает с гибридными CPU Intel), попробуй `LSW_WIN_CPU=host lsw start windows` или
  `LSW_WIN_CPU=qemu64,+ssse3,+sse4.1,+sse4.2,+popcnt`.

## Работа с другими инструментами

```sh
lsw ssh-config >> ~/.ssh/config   # потом: scp file lsw-ubuntu:, rsync, VS Code Remote-SSH
```
