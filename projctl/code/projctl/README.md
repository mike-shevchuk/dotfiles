# projctl — лаунчер усіх твоїх проектів

Одне місце, щоб **запускати / зупиняти / дивитись стан** усіх проектів — вручну або автоматично при вході в систему.

Кожен проект має **однаковий інтерфейс** — `just start | stop | restart | status | logs | attach` — і працює у своїй **tmux-сесії**. `projctl` просто керує ними всіма разом.

---

## Швидкий старт

```bash
cd ~/code/projctl

just            # відкрити TUI-дашборд (головний спосіб користування)
just up         # fzf-вибір: позначити проекти (TAB) і стартувати (↵)
just up all     # запустити ВСІ без вибору
just status     # таблиця стану + порти
just down       # зупинити все
```

### (Опційно) аліас, щоб запускати звідусіль

Щоб не робити щоразу `cd ~/code/projctl`, додай у `~/.zshrc`:

```bash
alias pj='just --justfile ~/code/projctl/justfile --working-directory ~/code/projctl'
```

Тоді з будь-якої теки:

```bash
pj            # TUI
pj up         # запустити все
pj status     # стан
pj down       # зупинити все
```

---

## TUI-дашборд (`just`)

Запусти `just` без аргументів — відкриється інтерактивний список:

```
 ▶ ●  stt-host    :8069        ┌─ preview ──────────────────┐
   ○  alexa       :5050        │ ▌ stt-host                 │
   ○  telegram                 │   state:   ● running (pid …)│
   ○  smartbj                  │   port:    :8069 LISTEN     │
   ○  immich      :3003        │   ── recent tmux output ── │
                               │   INFO:stt:Result: …       │
                               └────────────────────────────┘
```

Керування:

| Клавіша | Дія |
|---------|-----|
| `↑` / `↓` | рухатись по списку |
| **`TAB`** | **поставити галочку** (вибрати проект; можна кілька) |
| **`↵` Enter** | відкрити меню дій для відмічених → **Start / Stop / Restart / Status / Logs / Attach** |
| `ESC` | вийти |

- `●` = запущено, `○` = зупинено; поруч — порт.
- Права панель (preview) показує **живий стан** проекту під курсором: чи працює, PID, чи слухає порт, і останні рядки логу з tmux.

> Потрібні `fzf` і `gum` (вже встановлені). Якщо їх нема — `just` покаже звичайну таблицю `status`.

---

## Команди в терміналі

```bash
just up                    # у терміналі → fzf-вибір проектів (TAB=позначити, ↵=старт)
just up all                # запустити ВСІ без вибору
just up stt-host smartbj   # запустити лише вказані
just up-all                # те саме, що 'up all'
just down                  # зупинити всі
just down immich           # зупинити лише вказані
just restart alexa         # перезапустити
just status                # таблиця: стан + порт по кожному
just list                  # показати реєстр проектів
just logs stt-host         # останній вивід із tmux-сесії
just attach smartbj        # приєднатись до tmux-сесії (Ctrl-b d — відʼєднатись)

DRY=1 just up              # dry-run: показати що зробиться, нічого не запускаючи
```

---

## Авто-старт при вході в систему

```bash
just install     # увімкнути авто-старт при вході
just uninstall   # прибрати авто-старт
```

`install` **сам визначає ОС**: на macOS ставить LaunchAgent, на Linux — systemd user service.
При вході один раз виконується `just up all`; далі кожен проект живе у своїй tmux-сесії.

**macOS** (`launchd`), лог у `~/code/projctl/projctl.log`:
```bash
launchctl list | grep projctl                                   # чи завантажено
launchctl unload ~/Library/LaunchAgents/com.mike.projctl.plist  # тимчасово вимкнути
launchctl load   ~/Library/LaunchAgents/com.mike.projctl.plist  # знову увімкнути
```

**Linux** (`systemd --user`):
```bash
systemctl --user status projctl.service     # стан
systemctl --user stop  projctl.service       # зупинити зараз
systemctl --user start projctl.service       # запустити зараз
journalctl --user -u projctl.service         # логи
```

---

## Кросплатформність (Mac + Linux)

Один і той самий `projctl` працює на обох ОС:

- **PATH** підбирається автоматично через `os()` — homebrew на Mac, `/usr/bin` тощо на Linux.
- **Шляхи в реєстрі** пишуться через `~` і розкриваються в рантаймі — переносяться між машинами.
- **Авто-старт** `just install` сам обирає механізм: LaunchAgent (Mac) або systemd (Linux).

Що зробити на новій машині:
1. Отримати projctl (він у dotfiles → `stow projctl`, або скопіювати теку).
2. Мати `just`, `tmux`, `fzf`, `gum` (і `docker`, якщо треба). На Linux — з пакетного менеджера чи `brew`.
3. **Створити свій реєстр** (він git-ignored): `cp registry.conf.example registry.conf`,
   далі наповнити командами `just add …` (або відредагувати файл).
4. `just install` — увімкнути авто-старт (launchd/systemd).

> **`registry.conf` — git-ignored і свій на кожній машині** (різні проекти/шляхи).
> Код і `registry.conf.example` — у git, єдині для всіх машин.
> `systemd`-юніт тримає сесії живими через `RemainAfterExit=yes`; якщо якийсь дистрибутив
> усе одно їх прибирає — додай `KillMode=none` у `projctl.service`.

---

## Які проекти в наборі

| Проект | Порт | tmux-сесія | Запуск |
|--------|------|-----------|--------|
| `stt-host` | 8069 | `stt-host` | uvicorn (HTTPS) |
| `alexa` | 5050 | `alexa` (+`ngrok`) | Flask + ngrok |
| `telegram` | — | `claude-bot` | poetry bot |
| `smartbj` | — | `smartbj` | uv bot |
| `immich` | 3003 | `immich` | docker compose |

Реєстр — у `justfile`, змінна `registry`, один рядок на проект:

```
name | /абсолютний/шлях | tmux-сесія | порт(опц.) | додаткові-сесії(опц.)
```

---

## Як додати новий проект (напр. flow debugger)

1. **Дай проекту стандартний інтерфейс.** Скопіюй блок рецептів із
   [`service.template.just`](./service.template.just) у `justfile` проекту й заповни 3 змінні:
   ```just
   session := "flowdbg"          # унікальне імʼя tmux-сесії
   port    := "9000"             # порт, або "" якщо нема
   run     := "python app.py"    # команда запуску (в tmux)
   ```
2. **Додай один рядок у реєстр** у `~/code/projctl/justfile`:
   ```
   flowdbg|/Users/mikeshevchuk/code/flow-debugger|flowdbg|9000|
   ```

Готово — `up`/`down`/`status`/TUI підхоплять його автоматично.

---

## Дрібниці, які варто знати

- **PATH:** рецепти явно додають системні bin-теки (через `os()`: homebrew на Mac,
  `/usr/bin` на Linux), щоб `just`/`tmux`/`docker` знаходились навіть при бідному оточенні
  launchd/systemd на логіні.
- **telegram** розблоковує keychain лише при ручному запуску (`[ -t 0 ]`), щоб авто-старт не завис на діалозі пароля.
- **immich** запускає `docker compose up` у tmux; `stop` шле Ctrl-C і робить `docker compose down`.
- Оригінальні `justfile` кожного проекту збережено поряд як `justfile.projctl-bak`.
