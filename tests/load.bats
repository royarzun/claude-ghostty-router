setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/resolve.sh"
}

@test "carga perfiles y rutas en arrays paralelos" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/uno work"
  car_load_config "$CAR_CONF"
  [ "${#CAR_P_NAME[@]}" -eq 2 ]
  [ "${CAR_P_NAME[0]}" = "personal" ]
  [ "${CAR_P_DIR[1]}" = "$HOME/.claude-work" ]
  [ "${CAR_P_GLOB[1]}" = "*@empresa.com" ]
  [ "${CAR_P_COLOR[1]}" = "#8fbc5a" ]
  [ "${CAR_P_TINT[1]}" = "#171b12" ]
  [ "${CAR_P_TINT[0]}" = "-" ]
  [ "${#CAR_R_PATH[@]}" -eq 1 ]
  [ "${CAR_R_PROFILE[0]}" = "work" ]
}

@test "rechaza una ruta que apunta a un perfil inexistente" {
  write_conf "profile personal ~/.claude" "route ~/repos/uno fantasma"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"fantasma"* ]]
}

@test "rechaza perfiles duplicados" {
  write_conf "profile personal ~/.claude" "profile personal ~/.otro"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicado"* ]]
}

@test "rechaza una config sin ningun perfil" {
  write_conf "# solo comentarios"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ningun perfil"* ]]
}

@test "propaga el error de sintaxis del parser" {
  write_conf "basura aqui"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
}
