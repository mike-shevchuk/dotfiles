# Verkada через Anthropic Managed Agent — гайд (PUN-1650)

Керування Managed Agents-сесією, яка має **прямий доступ до Verkada**, через justfile-модуль
[`.justdir/verkada.just`](./verkada.just).
Linear: <https://linear.app/punchrescue/issue/PUN-1650>

---

## TL;DR — happy path

```bash
# 1. надіслати інструкцію агенту (дефолт: список камер, БЕЗ thumbnails)
just verkada-send sesn_XXXXXXXX

# 2. дивитись події 60 c — агент викликає /token → /cameras/v1/devices
just verkada-stream sesn_XXXXXXXX 60
```

Ключ `ANTHROPIC_API_KEY` підтягується автоматично з **AWS Secrets Manager** і **ніколи не друкується**
(ні в чат, ні в scrollback — банер показує лише ім'я `$ANTHROPIC_API_KEY`).

---

## Передумови

| Що | Перевірка |
|---|---|
| Робочі AWS-креди (той самий доступ, що `jb2b secret-keys`) | `aws sts get-caller-identity` |
| `jq`, `curl` | `command -v jq curl` |
| `fzf` (лише для `verkada-secrets`) | `command -v fzf` |
| Дійсний `sesn_…` | див. [Troubleshooting → 404](#404-session-not-found) |

`ANTHROPIC_API_KEY` живе в AWS Secrets Manager `/dev/rescue-serverless` (**не** в `~/dotfiles/.env`).

---

## Команди

| Рецепт | Що робить |
|---|---|
| `just verkada-send [session] [text]` | POST однієї `user.message` події в сесію. Дефолт `text` = «список Verkada-девайсів, без thumbnails». |
| `just verkada-stream [session] [max_time]` | SSE-стрім подій. `max_time=0` (дефолт) = без таймауту, Ctrl-C щоб спинити; `60` = вікно 60 c. |
| `just verkada-env [keys]` | Тягне ключі з AWS у **0600**-файл `/tmp/verkada-session.env` для `source` у поточну сесію. Дефолт — `ANTHROPIC_API_KEY`. |
| `just verkada-env-clean` | Видалити `/tmp/verkada-session.env`. |
| `just verkada-secrets` | `fzf` по **іменах** ключів; на вибір показує лише **замасковане** значення `abcd…wxyz`. |
| `just verkada-ls` | Діагностика: список agents + sessions, які бачить ключ (щоб знайти валідний `sesn_…`). |

---

## Як резолвиться ключ

`verkada-send` / `verkada-stream` шукають `ANTHROPIC_API_KEY` **у такому порядку**:

1. `$ANTHROPIC_API_KEY` вже в оточенні
2. **AWS Secrets Manager** `/dev/rescue-serverless` (на ambient-кредах)
3. `~/dotfiles/.env` — останній фолбек, у **ізольованому subshell**

> ⚠️ **Чому AWS перший, а не `.env`:** `~/dotfiles/.env` експортує **застарілі** `AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN`.
> Якщо `source .env` зробити **перед** `aws`, ці мертві креди перебивають робочі і `aws` тихо падає → порожній ключ.
> Тому AWS тягнеться першим, а `.env` — у subshell, щоб його `AWS_*` не витекли.

Значення ніколи не друкується. У `━━━ curl ━━━` банері стоїть ім'я `$ANTHROPIC_API_KEY` (як у `todo-today` з `$TODOIST_TOKEN`).

---

## Створити env для Linux-сесії

```bash
just verkada-env                              # тільки ANTHROPIC_API_KEY
just verkada-env "ANTHROPIC_API_KEY OPENAI_API_KEY"
source /tmp/verkada-session.env               # завантажує у ПОТОЧНУ оболонку
just verkada-env-clean                        # прибрати файл, коли готово
```

Значення йдуть **лише у 0600-файл**, не в stdout.

---

## Перегляд secrets

```bash
just verkada-secrets      # fzf по іменах → Enter показує abcd…wxyz (108 chars), НІКОЛИ повне значення
```

Це той самий blob, що `jb2b secret-keys` / `just secret-keys` у rescue-serverless.

---

## Troubleshooting

### `FAIL — could not resolve ANTHROPIC_API_KEY`
Раніше причиною були застарілі `AWS_*` у `~/dotfiles/.env` (див. врізку вище) — вже пофіксено (AWS-first).
Якщо все одно порожньо → онови/переавторизуй AWS-креди й перевір `aws sts get-caller-identity`.

### 404 `Session not found`
Плюмбінг ОК (авторизація + запит працюють), але `sesn_…` **не існує для цього ключа** — прострочена,
видалена, або створена **іншим** Anthropic-ключем/workspace, ніж той, що в AWS.

**Що робити:**
```bash
just verkada-ls                     # які agents/sessions бачить ключ (валідні id)
# або створи свіжу сесію в Console і:
just verkada-send sesn_НОВИЙ
```
Якщо `verkada-ls` нічого не показує — ключ у AWS не з того workspace, що володіє сесією.

### `just secret-keys` → «does not contain recipe», а `jb2b` працює
`just` читає файл `justfile`; приватні рецепти лежать у gitignored `justfile.v2` (його бере `jb2b`).
У rescue-serverless додано `import '.just_dir_2/secrets.just'` у комітнутий `fast/justfile`, тож
`just secret-keys` / `secret-get` / `secret-pick` тепер працюють нарівні з `jb2b`.
(Цілий `justfile.v2` імпортувати **не можна** — конфлікт `set shell`.)

---

## Безпека

- Ключ ніколи не потрапляє в чат/scrollback; банер маскує його як `$ANTHROPIC_API_KEY`.
- `verkada-env` пише файл `0600`; `verkada-secrets` показує лише імена/маску.
- ⚠️ `~/dotfiles/.env` містить **застарілі** `AWS_*` — не source-ити перед `aws` (модуль це вже враховує).
- `verkada-send` дефолтом **не** тягне thumbnails/футедж — лише перелік девайсів.

---

## Запуск із власного терміналу

Модуль живе на гілці `worktree-pun-1650-verkada`. Щоб запустити з будь-де:

```bash
just --justfile /Users/mikeshevchuk/dotfiles/.claude/worktrees/pun-1650-verkada/justfile verkada-send sesn_XXXX
```

У сесії з Claude Code можна виконати у своєму терміналі через префікс `!`:

```
! just --justfile /Users/mikeshevchuk/dotfiles/.claude/worktrees/pun-1650-verkada/justfile verkada-ls
```
