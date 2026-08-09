#!/system/bin/sh
set -e
MODDIR=${0%/*}
. "$MODDIR/../lib/common.sh"
. "$MODDIR/../lib/pif_preferred.sh"

log_i "PIF" "Starting PIF fingerprint update"

: "${PIF_DIR:=$MODULES_BASE/playintegrityfix}"

if [ ! -d "$PIF_DIR" ] || [ ! -f "$PIF_DIR/module.prop" ]; then
  log_e "PIF" "Play Integrity Fix not found at $PIF_DIR"
  exit 1
fi

_NAME=$(grep "^name=" "$PIF_DIR/module.prop" | cut -d= -f2-)
log_i "PIF" "Detected: $_NAME"

_pif_apply_preferred() {
  _prefs=$(cfg_get pif_preferred_devices '')
  if [ -z "$_prefs" ]; then
    _legacy_p=$(cfg_get pif_preferred_product '')
    _legacy_m=$(cfg_get pif_preferred_model '')
    [ -n "$_legacy_p" ] && _prefs="${_legacy_m}|${_legacy_p}"
    unset _legacy_p _legacy_m
  fi
  [ -n "$_prefs" ] || return 1

  _choice=$(pif_choose_preferred "$_prefs") || _choice=""
  if [ -z "$_choice" ]; then
    log_w "PIF" "No preferred devices left, falling back to random"
    unset _prefs _choice
    return 1
  fi

  _dest=$(pif_prop_dest "$_NAME")
  _pref_model="${_choice%\|*}"
  _pref_product="${_choice##*\|}"
  _applied=0
  case "$_pref_product" in
    imported:*)
      _imp_id="${_pref_product#imported:}"
      log_i "PIF" "Using imported device: $_pref_model ($_imp_id)"
      if pif_apply_imported "$_imp_id" "$_dest"; then
        _pif_model="$_pref_model"
        _applied=1
      else
        log_w "PIF" "Failed to apply imported device $_imp_id"
      fi
      unset _imp_id
      ;;
    *)
      log_i "PIF" "Using preferred device: $_pref_model ($_pref_product)"
      check_network || { log_e "PIF" "No internet connection"; exit 1; }
      case "$_NAME" in
        *Fork*)
          if MODEL="$_pref_model" PRODUCT="$_pref_product" sh "$PIF_DIR/autopif4.sh" >/dev/null 2>&1; then
            _pif_model=$(pif_prop_get "$_dest" MODEL)
            [ -n "$_pif_model" ] || _pif_model="$_pref_model"
            _applied=1
          else
            log_w "PIF" "Fork autopif4 failed for $_pref_product"
          fi
          ;;
        *)
          if pif_apply_github_prop "$_pref_product" "$_dest"; then
            _pif_model=$(pif_prop_get "$_dest" MODEL)
            _applied=1
          else
            log_w "PIF" "Failed to fetch GitHub prop for $_pref_product"
          fi
          ;;
      esac
      ;;
  esac
  [ -n "$_pif_model" ] && log_i "PIF" "Selected Device: $_pif_model"
  unset _pref_model _pref_product _choice _prefs _dest _pif_model
  [ "$_applied" = "1" ] || { unset _applied; return 1; }
  unset _applied
  return 0
}

case "$_NAME" in
  *INJECT*)
    if ! _pif_apply_preferred; then
      check_network || { log_e "PIF" "No internet connection"; exit 1; }
      sh "$PIF_DIR/autopif_ota.sh" 2>/dev/null || true
      _pif_out=$(sh "$PIF_DIR/autopif.sh" 2>/dev/null) || log_w "PIF" "autopif.sh failed"
      _pif_model=$(echo "$_pif_out" | grep '^MODEL=' | head -1 | sed 's/^MODEL=//')
      [ -n "$_pif_model" ] && log_i "PIF" "Selected Device: $_pif_model"
      unset _pif_out _pif_model
    fi
    ;;
  *Fork*)
    if ! _pif_apply_preferred; then
      check_network || { log_e "PIF" "No internet connection"; exit 1; }
      _pif_out=$(sh "$PIF_DIR/autopif4.sh" -m 2>/dev/null) || log_w "PIF" "autopif4.sh failed"
      _pif_model=$(echo "$_pif_out" | grep '^MODEL=' | head -1 | sed 's/^MODEL=//')
      [ -n "$_pif_model" ] && log_i "PIF" "Selected Device: $_pif_model"
      unset _pif_out _pif_model
    fi
    ;;
  *Hybrid*)
    log_i "PIF" "Hybrid manages fingerprints itself, skipping"
    ;;
  *)
    log_e "PIF" "Unknown module '$_NAME', can't update"
    log_w "PIF" "Use Play Integrity Fix [INJECT] or Play Integrity Fork"
    exit 1
    ;;
esac

unset _NAME
log_i "PIF" "PIF fingerprint updating complete"
exit 0
