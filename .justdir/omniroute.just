# OmniRoute — запасний шлюз для Claude Code, коли закінчились токени Anthropic
#
#   jg omni                         — меню (gum) → дія → модель (fzf)
#   jg omni claude                  — Claude Code через OmniRoute, модель через fzf
#   jg omni claude auto             — те саме, одразу з моделлю
#   jg omni test ddgw/claude-haiku-4-5
#
#   Дії: claude · status · test · models · start · stop · dashboard · kiro
#
# Claude Code ──(OMNIROUTE_API_KEY з ~/dotfiles/.env)──> OmniRoute 127.0.0.1:20128 ──> DuckDuckGo / Kiro / ...
# omniroute запускаємо з ~ : він читає .env з поточної теки.

# підключені й робочі провайдери; після `omni kiro` додай сюди kiro
omni_live := "^(combo|duckduckgo-web)$"
omni_utils := env_var('HOME') / "code/b2b/rescue-serverless/backend/src/lambdas/api/fast/.just_dir_2/_utils.just"

# OmniRoute: дія + модель аргументами, або вибір через gum/fzf
[group('omniroute')]
omni action="" model="":
    #!/usr/bin/env bash
    set -uo pipefail
    URL=http://127.0.0.1:20128
    KEY=$(grep '^OMNIROUTE_API_KEY=' ~/dotfiles/.env | cut -d= -f2-)
    up() { lsof -nP -iTCP:20128 -sTCP:LISTEN >/dev/null 2>&1; }
    models_json() {
        echo "━━━ xh ━━━  xh -b --ignore-stdin GET $URL/v1/models \"Authorization:Bearer \$OMNIROUTE_API_KEY\"" >&2
        xh -b --ignore-stdin GET $URL/v1/models "Authorization:Bearer $KEY" 2>/dev/null
    }
    # ponytail: live providers hardcoded in omni_live (CLI has no JSON provider list)
    live_models() {
        models_json | jq -r --arg live "{{omni_live}}" '.data[] | select(.owned_by | test($live))
            | "\(.id)\t\(if .owned_by == "combo" then "combo (зараз усі → безкоштовна DuckDuckGo)" else .owned_by end)\(if .id == "ddgw/claude-haiku-4-5" then "  ✔ перевірена" else "" end)"' | sort
    }
    # shared tested picker: first TAB-field on stdout, Esc → exit 1
    pick_model() {
        echo "━━━ just ━━━  just --justfile {{omni_utils}} _pick модель" >&2
        # Claude Code always sends tools; auto/* combos reject them ("no target supports tool calling")
        if [ "$1" = claude ]; then live_models | grep -v $'\tcombo'
        else printf 'auto\t★ OmniRoute сам бере робочу модель\n'; live_models; fi \
          | just --justfile "{{omni_utils}}" --working-directory ~ _pick "модель"
    }
    start() {
        up && { echo "→ сервер уже працює" >&2; return 0; }
        echo "━━━ omniroute ━━━  cd ~ && omniroute serve --daemon --no-open --no-tray" >&2
        (cd ~ && omniroute serve --daemon --no-open --no-tray 2>&1 | grep -E '✔|✖|SECURITY|rror' >&2)
        for _ in $(seq 1 20); do up && break; sleep 1; done  # daemon reports started before the port is bound
        up && echo "  OK" >&2 || { echo "  FAIL — сервер не слухає :20128" >&2; return 1; }
    }
    test_model() {
        echo "━━━ xh ━━━  xh -b --ignore-stdin --timeout 60 POST $URL/v1/chat/completions \"Authorization:Bearer \$OMNIROUTE_API_KEY\" model=$1 'messages:=[{\"role\":\"user\",\"content\":\"reply OK\"}]' max_tokens:=20" >&2
        local s=$(date +%s) r ans
        r=$(xh -b --ignore-stdin --timeout 60 POST $URL/v1/chat/completions "Authorization:Bearer $KEY" \
            model="$1" 'messages:=[{"role":"user","content":"reply OK"}]' max_tokens:=20 2>/dev/null)
        ans=$(echo "$r" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
        if [ -n "$ans" ]; then echo "  OK ($(( $(date +%s)-s ))s, $(echo "$r" | jq -r '.model // "?"')) → $ans" >&2
        else echo "  FAIL — $(echo "$r" | jq -r '.error.message // .' 2>/dev/null | head -c 300)" >&2
             echo "  Перевірена модель: jg omni test ddgw/claude-haiku-4-5" >&2; return 1; fi
    }

    act="{{action}}"; m="{{model}}"
    if [ -z "$act" ]; then
        act=$(gum choose --header "OmniRoute ❯ що робимо?" \
            "claude    — запустити Claude Code через OmniRoute (продовжить розмову)" \
            "status    — перевірити сервер, ключ і модель" \
            "test      — тестовий запит до моделі" \
            "models    — список робочих моделей" \
            "start     — запустити сервер" \
            "stop      — зупинити сервер" \
            "dashboard — відкрити дашборд у браузері" \
            "kiro      — підключити Kiro (безкоштовний Claude, OAuth)" </dev/tty) || exit 0
        act=${act%% *}
    fi
    case "$act" in claude|test) [ -n "$m" ] || m=$(pick_model "$act"); [ -n "$m" ] || exit 0 ;; esac
    echo "━━━ just ━━━  jg omni $act $m" >&2

    case "$act" in
      claude)
        up || start || exit 1
        export OMNIROUTE_API_KEY=$KEY
        cd "{{invocation_directory()}}"
        # --continue exits with "No conversation found" in a folder without history
        cont=(); ls ~/.claude/projects/$(pwd | sed 's#[/.]#-#g')/*.jsonl >/dev/null 2>&1 && cont=(--continue)
        echo "━━━ omniroute ━━━  cd $PWD && omniroute run claude --model $m --api-key-env OMNIROUTE_API_KEY -- ${cont[*]:-}" >&2
        exec omniroute run claude --model "$m" --api-key-env OMNIROUTE_API_KEY -- ${cont[@]+"${cont[@]}"} ;;
      status)
        echo "[1/3] сервер..." >&2
        addr=$(lsof -nP -iTCP:20128 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | sort -u)
        [ -n "$addr" ] || { echo "  FAIL — не запущений: jg omni start" >&2; exit 1; }
        case "$addr" in 127.0.0.1:*) echo "  OK ($addr — тільки цей Mac)" >&2 ;;
                        *) grep -q '^REQUIRE_API_KEY=true' ~/.omniroute/.env \
                             && echo "  OK ($addr — LAN, /v1 тільки з ключем, дашборд з логіном)" >&2 \
                             || echo "  WARN ($addr — LAN без ключа; додай REQUIRE_API_KEY=true у ~/.omniroute/.env)" >&2 ;; esac
        echo "[2/3] ключ..." >&2
        [ -n "$KEY" ] || { echo "  FAIL — немає OMNIROUTE_API_KEY у ~/dotfiles/.env (дашборд → API Keys)" >&2; exit 1; }
        n=$(models_json | jq -r '.data | length' 2>/dev/null)
        [ -n "$n" ] && [ "$n" != "null" ] && echo "  OK (${KEY:0:3}…, $n моделей)" >&2 || { echo "  FAIL — ключ не підходить (OmniRoute-ключ починається з sk-)" >&2; exit 1; }
        echo "[3/3] модель ${m:-auto}..." >&2
        test_model "${m:-auto}" && echo "✔ Готово: jg omni claude" >&2 ;;
      test)      test_model "$m" ;;
      models)    live_models | column -t -s $'\t' ;;
      start)     start ;;
      stop)      echo "━━━ omniroute ━━━  cd ~ && omniroute stop" >&2; cd ~ && omniroute stop ;;
      dashboard)
        lan=$(for i in en0 en1 en2 en3 en4 en5 en6 en7 en8; do ipconfig getifaddr $i 2>/dev/null && break; done)
        echo "  цей Mac:      $URL" >&2
        lsof -nP -iTCP:20128 -sTCP:LISTEN 2>/dev/null | grep -q '\*:20128' && [ -n "$lan" ] \
          && echo "  інший пристрій (та сама мережа): http://$lan:20128" >&2 \
          || echo "  інший пристрій: сервер слухає лише 127.0.0.1 (OMNIROUTE_SERVER_HOST=0.0.0.0 у ~/.omniroute/.env + restart)" >&2
        echo "━━━ open ━━━  open $URL" >&2; open $URL ;;
      kiro)      echo "━━━ omniroute ━━━  cd ~ && omniroute providers auth kiro" >&2; cd ~ && omniroute providers auth kiro ;;
      *)         echo "FAIL — невідома дія '$act'. Дії: claude status test models start stop dashboard kiro" >&2; exit 1 ;;
    esac
