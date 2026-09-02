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

@test "instala el enlace, la config, la linea del zshrc y no-title" {
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/claude-account" ]
  [ -f "$HOME/.config/claude-ghostty-router/routes.conf" ]
  grep -q "router.zsh" "$HOME/.zshrc"
  grep -q "no-title" "$CAR_GHOSTTY_CONF"
}

@test "es idempotente: dos instalaciones dejan una sola linea en el zshrc" {
  "$CAR_ROOT/install.sh" --yes
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  [ "$(grep -c 'router.zsh' "$HOME/.zshrc")" -eq 1 ]
}

@test "nunca pisa una routes.conf existente" {
  mkdir -p "$HOME/.config/claude-ghostty-router"
  printf 'profile mio ~/.claude\n' > "$HOME/.config/claude-ghostty-router/routes.conf"
  "$CAR_ROOT/install.sh" --yes
  run cat "$HOME/.config/claude-ghostty-router/routes.conf"
  [ "$output" = "profile mio ~/.claude" ]
}

@test "respalda la config de Ghostty antes de tocarla" {
  "$CAR_ROOT/install.sh" --yes
  [ -f "$CAR_GHOSTTY_CONF.bak" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF.bak"
  [ "$output" = "0" ]
}

@test "uninstall revierte enlace, linea y no-title" {
  "$CAR_ROOT/install.sh" --yes
  run "$CAR_ROOT/install.sh" --uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/claude-account" ]
  run grep -c "router.zsh" "$HOME/.zshrc"
  [ "$output" = "0" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
}

@test "uninstall conserva routes.conf: es del usuario" {
  "$CAR_ROOT/install.sh" --yes
  "$CAR_ROOT/install.sh" --uninstall --yes
  [ -f "$HOME/.config/claude-ghostty-router/routes.conf" ]
}
