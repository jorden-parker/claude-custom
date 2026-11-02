fetch_user() {
  local user_id="$1"
  case "$user_id" in
    1) echo "ada" ;;
    2) echo "grace" ;;
    *) echo "unknown" ;;
  esac
}
