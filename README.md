# lsw

Аналог WSL для Linux: лёгкие headless-виртуалки на QEMU/KVM, управляемые одной bash-утилитой.
Гости: **Ubuntu** (26.04 / 24.04), **Arch**, **Windows 10**. Без GUI, вход через терминал (ssh).

## Установка

**Ubuntu 24.04+ / Debian 12+:**
```sh
gh release download -R Kolpachkov/lsw -p 'lsw-ubuntu.tar.gz'
tar xzf lsw-ubuntu.tar.gz && cd lsw && ./install.sh   # потом перелогиниться
```

**Arch:**
```sh
sudo pacman -S --needed qemu-base libisoburn socat
git clone https://github.com/Kolpachkov/lsw ~/lsw && ln -s ~/lsw/lsw ~/.local/bin/lsw
```

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

Если ты стоишь внутри общей папки, `lsw shell` откроется в той же папке гостя, как в WSL.

Сеть: гость выходит в интернет через user-mode NAT, а **сервисы хоста на `localhost` доступны ему по `10.0.2.2`**.
Не держи на `127.0.0.1` хоста ничего без пароля, если запускаешь в VM недоверенный код.

Файлы: `~/.local/share/lsw/vms/<имя>/` (диск, `vm.conf`, логи, сокеты QMP и консоли),
базовые образы кешируются в `~/.local/share/lsw/cache/`.

## Пользователь и пароль

Логин — твой `$USER`, пароль по умолчанию такой же (`--password` при установке), он лежит в `vms/<имя>/password`.
В Linux ssh по паролю выключен, пароль нужен только для `lsw console`. Не используй в пароле `' | & <`.

## Windows: подробности

- Нужен свой ISO Windows 10 ([официальная загрузка Microsoft](https://www.microsoft.com/software-download/windows10)).
  Язык установки определяется по `sources/lang.ini`.
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
