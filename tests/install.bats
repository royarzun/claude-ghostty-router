setup() {
  load helper
  setup_fixture
  export ZDOTDIR="$HOME"
  mkdir -p "$HOME/.local/bin" "$HOME/Library/Application Support/com.mitchellh.ghostty"
  export CAR_GHOSTTY_CONF="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
  printf 'theme = Github Dark Default\n' > "$CAR_GHOSTTY_CONF"
  printf 'export ZSH="$HOME/.oh-my-zsh"\n' > "$HOME/.zshrc"
  unset CAR_CONF
}

# Deja la linea que ponian las versiones que sostenian un titulo de tab.
con_no_title() {
  printf 'theme = x\nshell-integration-features = cursor,no-title,path  # claude-ghostty-router\n' \
    > "$CAR_GHOSTTY_CONF"
}

@test "instala el enlace, la config, la linea del zshrc y el badge" {
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/claude-account" ]
  [ -f "$HOME/.config/claude-ghostty-router/routes.conf" ]
  grep -q "router.zsh" "$HOME/.zshrc"
  grep -q "claude-account statusline" "$HOME/.claude/settings.json"
  grep -q "claude-account statusline" "$HOME/.claude-work/settings.json"
}

@test "el statusLine apunta a una ruta absoluta" {
  # Claude Code puede arrancar con un PATH que no incluya ~/.local/bin.
  "$CAR_ROOT/install.sh" --yes
  run grep -c "$HOME/.local/bin/claude-account statusline" "$HOME/.claude/settings.json"
  [ "$output" = "1" ]
}

@test "es idempotente: dos instalaciones dejan una sola linea en el zshrc" {
  "$CAR_ROOT/install.sh" --yes
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  [ "$(grep -c 'router.zsh' "$HOME/.zshrc")" -eq 1 ]
  [ "$(grep -c 'statusLine' "$HOME/.claude/settings.json")" -eq 1 ]
}

@test "nunca pisa una routes.conf existente" {
  mkdir -p "$HOME/.config/claude-ghostty-router"
  printf 'profile mio ~/.claude\n' > "$HOME/.config/claude-ghostty-router/routes.conf"
  "$CAR_ROOT/install.sh" --yes
  run cat "$HOME/.config/claude-ghostty-router/routes.conf"
  [ "$output" = "profile mio ~/.claude" ]
}

@test "conserva lo que ya hubiera en el settings.json del perfil" {
  mkdir -p "$HOME/.claude"
  printf '{"model":"opus"}\n' > "$HOME/.claude/settings.json"
  "$CAR_ROOT/install.sh" --yes
  grep -q '"model": "opus"' "$HOME/.claude/settings.json"
  grep -q "statusLine" "$HOME/.claude/settings.json"
  [ -f "$HOME/.claude/settings.json.bak" ]
}

@test "no pisa un statusLine ajeno" {
  mkdir -p "$HOME/.claude"
  printf '{"statusLine":{"type":"command","command":"mi-script"}}\n' > "$HOME/.claude/settings.json"
  run "$CAR_ROOT/install.sh" --yes
  [[ "$output" == *"otro statusLine"* ]]
  run grep -c "mi-script" "$HOME/.claude/settings.json"
  [ "$output" = "1" ]
}

@test "no anade no-title a la config de Ghostty" {
  # El router ya no escribe el titulo: sostenerlo costaba el titulo de Ghostty.
  "$CAR_ROOT/install.sh" --yes
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
}

@test "ofrece revertir el no-title que dejo una version anterior" {
  con_no_title
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF.bak"
  [ "$output" = "1" ]
}

@test "uninstall revierte enlace, linea, badge y no-title" {
  con_no_title
  "$CAR_ROOT/install.sh" --yes
  con_no_title
  run "$CAR_ROOT/install.sh" --uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/claude-account" ]
  run grep -c "router.zsh" "$HOME/.zshrc"
  [ "$output" = "0" ]
  run grep -c "statusLine" "$HOME/.claude/settings.json"
  [ "$output" = "0" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
}

@test "uninstall conserva routes.conf: es del usuario" {
  "$CAR_ROOT/install.sh" --yes
  "$CAR_ROOT/install.sh" --uninstall --yes
  [ -f "$HOME/.config/claude-ghostty-router/routes.conf" ]
}

@test "no pisa en silencio un archivo ajeno en el destino del enlace" {
  printf '#!/bin/sh\necho ajeno\n' > "$HOME/.local/bin/claude-account"
  chmod +x "$HOME/.local/bin/claude-account"
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"claude-account"* ]]
  # El archivo ajeno sigue intacto
  run cat "$HOME/.local/bin/claude-account"
  [[ "$output" == *"ajeno"* ]]
}
