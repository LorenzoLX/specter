# shellcheck shell=sh
# Enabled backends only: teesim → Tricky Store / TEESimulator-RS → OMK.
#
# Keystore manager contract (set by detect_keystore_manager):
#   KSM              backend id: teesim | trickystore | omk | none
#   KSM_NAME         display name from the module's module.prop
#   KSM_DIR          the backend's data directory
#   KSM_KEYBOX       keybox file
#   KSM_TARGETS      target/app list file
#   KSM_CONFIG       main config file: security patch level lives here; for
#                    toml also the trust fields, for json also the profiles
#   KSM_FORMAT       file format of targets/config: txt | json | toml
#   KSM_PER_APP_MODES  1 when per-app !/? suffixes are meaningful (txt only)
#
# Feature scripts and the WebUI consume only this contract; nothing outside
# this file (plus the per-format helpers) knows backend-specific paths.

_ksm_auto_pick() {
  if module_enabled teesim >/dev/null; then
    printf '%s\n' teesim
  elif module_enabled tricky_store >/dev/null; then
    printf '%s\n' trickystore
  elif module_enabled "${OMK_MODULE##*/}" >/dev/null; then
    printf '%s\n' omk
  fi
}

ksm_enforce_singleton() {
  _kes_w=""
  case "$(cfg_get keystore_manager auto 2>/dev/null)" in
    teesim) module_enabled teesim >/dev/null && _kes_w=teesim ;;
    trickystore) module_enabled tricky_store >/dev/null && _kes_w=trickystore ;;
    omk) module_enabled "${OMK_MODULE##*/}" >/dev/null && _kes_w=omk ;;
  esac
  [ -n "$_kes_w" ] || _kes_w=$(_ksm_auto_pick)
  [ -n "$_kes_w" ] || { unset _kes_w; return 0; }

  if [ "$_kes_w" != teesim ] && module_enabled teesim >/dev/null; then
    module_disable teesim
    printf '%s\n' teesim
    log_i "KSM" "Disabled teesim (keystore conflict; using $_kes_w)"
  fi
  if [ "$_kes_w" != trickystore ] && module_enabled tricky_store >/dev/null; then
    module_disable tricky_store
    printf '%s\n' tricky_store
    log_i "KSM" "Disabled tricky_store (keystore conflict; using $_kes_w)"
  fi
  if [ "$_kes_w" != omk ] && module_enabled "${OMK_MODULE##*/}" >/dev/null; then
    module_disable "${OMK_MODULE##*/}"
    printf '%s\n' "${OMK_MODULE##*/}"
    log_i "KSM" "Disabled ${OMK_MODULE##*/} (keystore conflict; using $_kes_w)"
  fi
  unset _kes_w
}

detect_keystore_manager() {
  _dkm_override=$(cfg_get keystore_manager auto 2>/dev/null)
  case "$_dkm_override" in
    trickystore|teesim|omk) KSM=$_dkm_override ;;
    *)
      KSM=$(_ksm_auto_pick)
      [ -n "$KSM" ] || KSM=none
      ;;
  esac

  case "$KSM" in
    trickystore)
      KSM_NAME=$(_ts_prop)
      [ -n "$KSM_NAME" ] || KSM_NAME="Tricky Store"
      KSM_DIR="$TRICKY_DIR"
      KSM_KEYBOX="$TARGET_FILE"
      KSM_TARGETS="$TARGET_TXT"
      KSM_CONFIG="$SECURITY_PATCH_FILE"
      KSM_FORMAT="txt"
      KSM_PER_APP_MODES=1
      ;;
    teesim)
      KSM_NAME=$(_teesim_prop)
      [ -n "$KSM_NAME" ] || KSM_NAME="TEESimulator"
      KSM_DIR="$TEESIM_DIR"
      KSM_KEYBOX="$TEESIM_KEYBOX"
      KSM_TARGETS="$TEESIM_CONFIG"
      KSM_CONFIG="$TEESIM_CONFIG"
      KSM_FORMAT="json"
      KSM_PER_APP_MODES=0
      ;;
    omk)
      KSM_NAME="OhMyKeymint"
      KSM_DIR="$OMK_DIR"
      KSM_KEYBOX="$OMK_KEYBOX"
      KSM_TARGETS="$OMK_INJECTOR"
      KSM_CONFIG="$OMK_CONFIG"
      KSM_FORMAT="toml"
      KSM_PER_APP_MODES=0
      ;;
    *)
      KSM_NAME=""
      KSM_DIR=""
      KSM_KEYBOX=""
      KSM_TARGETS=""
      KSM_CONFIG=""
      KSM_FORMAT=""
      KSM_PER_APP_MODES=0
      ;;
  esac

  export KSM KSM_NAME KSM_DIR KSM_KEYBOX KSM_TARGETS KSM_CONFIG KSM_FORMAT KSM_PER_APP_MODES
  unset _dkm_override
}

ksm_available() {
  [ "$KSM" != "none" ] && [ -n "$KSM_DIR" ] && [ -d "$KSM_DIR" ]
}

# Explicit Tools for injector; keymint also auto-touches on trust field saves.
ksm_reload() {
  [ "$KSM" = "omk" ] || return 0
  mkdir -p "$OMK_RESTART_DIR" 2>/dev/null || true
  touch "$OMK_RESTART_DIR/restart.keymint" 2>/dev/null
}

ksm_reload_injector() {
  [ "$KSM" = "omk" ] || return 0
  mkdir -p "$OMK_RESTART_DIR" 2>/dev/null || true
  touch "$OMK_RESTART_DIR/restart.injector" 2>/dev/null
}

_ksm_inplace_from() {
  _kif_src="$1" _kif_dst="$2"
  [ -f "$_kif_dst" ] || { unset _kif_src _kif_dst; return 1; }
  cat "$_kif_src" > "$_kif_dst" || { unset _kif_src _kif_dst; return 1; }
  unset _kif_src _kif_dst
}

_ksm_strip_suffix() {
  _kss_line="$1"
  case "$_kss_line" in *!) _kss_line=${_kss_line%!} ;; *\?) _kss_line=${_kss_line%\?} ;; esac
  printf '%s' "$_kss_line"
  unset _kss_line
}

ksm_read_targets() {
  case "$KSM_FORMAT" in
    json)
      _teesim_read_apps "$KSM_TARGETS"
      ;;
    toml)
      [ -f "$KSM_TARGETS" ] || return 0
      _toml_read_scoop "$KSM_TARGETS"
      ;;
    *)
      [ -f "$KSM_TARGETS" ] || return 0
      while IFS= read -r _krt_line || [ -n "$_krt_line" ]; do
        [ -z "$_krt_line" ] && continue
        case "$_krt_line" in \[*\]) continue ;; esac
        _krt_base=$(_ksm_strip_suffix "$_krt_line")
        [ -n "$_krt_base" ] && printf '%s\n' "$_krt_base"
      done < "$KSM_TARGETS"
      unset _krt_line _krt_base
      ;;
  esac
}

ksm_read_targets_raw() {
  case "$KSM_FORMAT" in
    json) _teesim_read_apps "$KSM_TARGETS" default ;;
    toml) ksm_read_targets ;;
    *) [ -f "$KSM_TARGETS" ] && cat "$KSM_TARGETS" ;;
  esac
}

ksm_commit_targets() {
  _kct_src="$1"
  case "$KSM_FORMAT" in
    json)
      _teesim_commit_apps "$KSM_TARGETS" "$_kct_src" || {
        unset _kct_src
        return 1
      }
      ;;
    toml)
      _kct_tmp="${KSM_TARGETS}.pkgs.$$"
      : > "$_kct_tmp"
      while IFS= read -r _kct_line || [ -n "$_kct_line" ]; do
        [ -z "$_kct_line" ] && continue
        case "$_kct_line" in \[*\]) continue ;; esac
        _kct_base=$(_ksm_strip_suffix "$_kct_line")
        [ -n "$_kct_base" ] && printf '%s\n' "$_kct_base" >> "$_kct_tmp"
      done < "$_kct_src"
      _toml_write_scoop "$KSM_TARGETS" < "$_kct_tmp" || {
        rm -f "$_kct_tmp"
        unset _kct_line _kct_base _kct_tmp _kct_src
        return 1
      }
      rm -f "$_kct_tmp"
      unset _kct_line _kct_base _kct_tmp
      ;;
    *)
      rm -f "${KSM_TARGETS}.bak"
      [ -f "$KSM_TARGETS" ] && cp "$KSM_TARGETS" "${KSM_TARGETS}.bak"
      mv -f "$_kct_src" "$KSM_TARGETS"
      ;;
  esac
  unset _kct_src
}

# Commit a desired flat package list (one per line, optional !/? suffix) while
# preserving configuration the flat list cannot express:
#  - txt: [name.xml] keybox scoping sections and their member packages
#  - json: non-default TEESimulator profiles (only the default profile's apps
#    are managed; ksm_read_targets_raw already returns default-only)
#  - toml: no sections, same as ksm_commit_targets
ksm_commit_targets_merge() {
  _kcm_src="$1"
  case "$KSM_FORMAT" in
    txt)
      if [ -f "$KSM_TARGETS" ]; then
        _ksm_txt_merge "$_kcm_src" || { unset _kcm_src; return 1; }
      else
        ksm_commit_targets "$_kcm_src" || { unset _kcm_src; return 1; }
      fi
      ;;
    json) _teesim_commit_apps "$KSM_TARGETS" "$_kcm_src" || { unset _kcm_src; return 1; } ;;
    toml) ksm_commit_targets "$_kcm_src" || { unset _kcm_src; return 1; } ;;
  esac
  unset _kcm_src
}

# Rewrite target.txt from $1: packages keep their [name.xml] section
# membership, package lines take the desired suffix, deselected packages are
# dropped, new packages land in the default (pre-section) block.
_ksm_txt_merge() {
  _ktm_src="$1"
  _ktm_out="${KSM_TARGETS}.new.$$"
  awk -v srcfile="$_ktm_src" '
    BEGIN {
      while ((getline l < srcfile) > 0) {
        sub(/\r$/, "", l)
        if (l ~ /^[[:space:]]*$/ || l ~ /^[[:space:]]*\[/) continue
        base = l
        sub(/[!?][[:space:]]*$/, "", base)
        if (base == "") continue
        want[base] = l
        if (!(base in ordered)) { ordered[base] = 1; order[++n] = base }
      }
      close(srcfile)
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*\[/) { sect[++nsect] = line; next }
      if (line ~ /^[[:space:]]*$/ || line ~ /^[[:space:]]*#/) next
      base = line
      sub(/[!?][[:space:]]*$/, "", base)
      if ((base in want) && !(base in seen)) {
        seen[base] = 1
        if (nsect > 0) sec_of[base] = nsect
      }
    }
    END {
      for (i = 1; i <= n; i++) {
        if (order[i] in sec_of) continue
        print want[order[i]]
      }
      for (s = 1; s <= nsect; s++) {
        print sect[s]
        for (i = 1; i <= n; i++) {
          if ((order[i] in sec_of) && sec_of[order[i]] == s) print want[order[i]]
        }
      }
    }
  ' "$KSM_TARGETS" > "$_ktm_out" || {
    rm -f "$_ktm_out"
    unset _ktm_src _ktm_out
    return 1
  }
  rm -f "${KSM_TARGETS}.bak"
  cp "$KSM_TARGETS" "${KSM_TARGETS}.bak"
  mv -f "$_ktm_out" "$KSM_TARGETS" || {
    rm -f "$_ktm_out"
    unset _ktm_src _ktm_out
    return 1
  }
  unset _ktm_src _ktm_out
}

# Insert the lines from $2 into $1's default block, i.e. before the first
# [name.xml] section header (appended when no sections exist). Keeps new
# packages scoped to the default keybox instead of the last section.
_txt_insert_default() {
  _tid_file="$1" _tid_add="$2"
  [ -s "$_tid_add" ] || { unset _tid_file _tid_add; return 0; }
  _tid_tmp="${_tid_file}.new.$$"
  awk -v add="$_tid_add" '
    BEGIN { inserted = 0 }
    !inserted && /^[[:space:]]*\[/ {
      while ((getline l < add) > 0) { if (l != "") print l }
      close(add)
      inserted = 1
    }
    { print }
    END {
      if (!inserted) {
        while ((getline l < add) > 0) { if (l != "") print l }
        close(add)
      }
    }
  ' "$_tid_file" > "$_tid_tmp" || {
    rm -f "$_tid_tmp"
    unset _tid_file _tid_add _tid_tmp
    return 1
  }
  mv -f "$_tid_tmp" "$_tid_file" || {
    rm -f "$_tid_tmp"
    unset _tid_file _tid_add _tid_tmp
    return 1
  }
  unset _tid_file _tid_add _tid_tmp
}

# Wait up to $2 seconds (default 10) for $1 to appear.
_ksm_wait_file() {
  _kwf_file="$1" _kwf_tries="${2:-10}" _kwf_i=0
  while [ ! -f "$_kwf_file" ] && [ "$_kwf_i" -lt "$_kwf_tries" ]; do
    sleep 1
    _kwf_i=$((_kwf_i + 1))
  done
  [ -f "$_kwf_file" ]
  unset _kwf_file _kwf_tries _kwf_i
}

ksm_get_security_patch() {
  case "$KSM_FORMAT" in
    json)
      _teesim_get_boot_patch "$KSM_CONFIG"
      ;;
    toml)
      [ -f "$KSM_CONFIG" ] || return 1
      grep -E '^[ ]*security_patch[ ]*=' "$KSM_CONFIG" 2>/dev/null | head -1 |
        sed 's/.*=[ ]*"\([^"]*\)".*/\1/'
      ;;
    *)
      [ -f "$KSM_CONFIG" ] || return 1
      _kgsp=$(awk '
        /^[[:space:]]*\[/ { exit }
        /^[[:space:]]*boot=/ { sub(/^[[:space:]]*boot=/,""); sub(/[[:space:]]*$/,""); if ($0 != "") { print; exit } }
      ' "$KSM_CONFIG") || _kgsp=""
      if [ -z "$_kgsp" ]; then
        _kgsp=$(awk '
          /^[[:space:]]*\[/ { exit }
          /^[[:space:]]*all=/ { sub(/^[[:space:]]*all=/,""); sub(/[[:space:]]*$/,""); if ($0 != "") { print; exit } }
        ' "$KSM_CONFIG") || _kgsp=""
      fi
      [ -n "$_kgsp" ] || { unset _kgsp; return 1; }
      printf '%s\n' "$_kgsp"
      unset _kgsp
      ;;
  esac
}

ksm_set_security_patch() {
  _ksp_date="$1"
  case "$KSM_FORMAT" in
    json)
      _teesim_set_patch "$KSM_CONFIG" "$_ksp_date" || {
        unset _ksp_date
        return 1
      }
      ;;
    toml)
      _ksm_wait_file "$KSM_CONFIG" 10 || {
        log_w "KSM" "OMK config.toml not available yet, skip security patch"
        unset _ksp_date
        return 1
      }
      _toml_set_trust_key "$KSM_CONFIG" "security_patch" "\"$_ksp_date\"" || {
        unset _ksp_date
        return 1
      }
      ;;
    *)
      _ksp_vendor=$(getprop ro.vendor.build.security_patch 2>/dev/null || echo "")
      if [ -z "$_ksp_vendor" ] && [ -f /vendor/build.prop ]; then
        _ksp_vendor=$(grep '^ro.vendor.build.security_patch=' /vendor/build.prop 2>/dev/null |
          head -1 | cut -d= -f2 | tr -d '[:space:]') || _ksp_vendor=""
      fi
      [ -n "$_ksp_vendor" ] || _ksp_vendor="$_ksp_date"
      _ksp_yyyymm=$(printf '%s' "$_ksp_date" | cut -d'-' -f1-2 | tr -d '-')
      _ksp_tmp="${KSM_CONFIG}.new.$$"
      {
        printf 'system=%s\nboot=%s\nvendor=%s\n' "$_ksp_yyyymm" "$_ksp_date" "$_ksp_vendor"
        if [ -f "$KSM_CONFIG" ]; then
          # Keep per-package [pkg] sections and their contents untouched.
          awk '/^[[:space:]]*\[/ { emit = 1 } emit { print }' "$KSM_CONFIG"
        fi
      } > "$_ksp_tmp"
      if [ -f "$KSM_CONFIG" ]; then
        _ksm_inplace_from "$_ksp_tmp" "$KSM_CONFIG" || {
          rm -f "$_ksp_tmp"
          unset _ksp_date _ksp_vendor _ksp_yyyymm _ksp_tmp
          return 1
        }
        rm -f "$_ksp_tmp"
      else
        mv -f "$_ksp_tmp" "$KSM_CONFIG" || {
          rm -f "$_ksp_tmp"
          unset _ksp_date _ksp_vendor _ksp_yyyymm _ksp_tmp
          return 1
        }
      fi
      unset _ksp_vendor _ksp_yyyymm _ksp_tmp
      ;;
  esac
  unset _ksp_date
}

ksm_get_mode() {
  case "$KSM_FORMAT" in
    json) _teesim_get_mode "$KSM_TARGETS" ;;
    *) printf '' ;;
  esac
}

ksm_set_mode() {
  case "$KSM_FORMAT" in
    json) _teesim_set_mode "$KSM_TARGETS" "$1" ;;
    *) return 1 ;;
  esac
}

ksm_get_trust_field() {
  _kgt_key="$1"
  case "$KSM_FORMAT" in
    toml) _toml_get_trust_key "$KSM_CONFIG" "$_kgt_key" ;;
    *) printf '' ;;
  esac
  unset _kgt_key
}

ksm_set_trust_field() {
  _kst_key="$1" _kst_val="$2"
  case "$KSM_FORMAT" in
    toml)
      _ksm_wait_file "$KSM_CONFIG" 10 || {
        log_w "KSM" "OMK config.toml not available yet, skip trust field"
        unset _kst_key _kst_val
        return 1
      }
      case "$_kst_key" in
        os_version)
          _toml_set_trust_key "$KSM_CONFIG" "os_version" "$_kst_val"
          ;;
        vb_key|vb_hash)
          _toml_set_trust_key "$KSM_CONFIG" "$_kst_key" "\"$_kst_val\""
          ;;
      esac
      ksm_reload
      ;;
    *) return 1 ;;
  esac
  unset _kst_key _kst_val
}

# MODE "copy" keeps SRC; default "move" consumes it.
ksm_install_keybox() {
  _kik_src="$1" _kik_mode="${2:-move}"
  case "$KSM" in
    omk)
      _ksm_inplace_from "$_kik_src" "$KSM_KEYBOX" || {
        unset _kik_src _kik_mode
        return 1
      }
      [ "$_kik_mode" = "copy" ] || rm -f "$_kik_src"
      ;;
    teesim)
      mkdir -p "$TEESIM_DIR" 2>/dev/null
      if [ "$_kik_mode" = "copy" ]; then
        cp "$_kik_src" "$KSM_KEYBOX" || { unset _kik_src _kik_mode; return 1; }
      else
        mv "$_kik_src" "$KSM_KEYBOX" || { unset _kik_src _kik_mode; return 1; }
      fi
      _teesim_ensure_keybox_field "$TEESIM_CONFIG" || {
        unset _kik_src _kik_mode
        return 1
      }
      ;;
    *)
      mkdir -p "$(dirname "$KSM_KEYBOX")" 2>/dev/null
      if [ "$_kik_mode" = "copy" ]; then
        cp "$_kik_src" "$KSM_KEYBOX" || { unset _kik_src _kik_mode; return 1; }
      else
        mv "$_kik_src" "$KSM_KEYBOX" || { unset _kik_src _kik_mode; return 1; }
      fi
      ;;
  esac
  unset _kik_src _kik_mode
}

# -- TOML helpers (private) --
# Deliberately minimal: only understands the two shapes Specter needs to
# read/write (a top-level `scoop = [...]` array and a `KEY = VALUE` line
# inside a `[trust]` table), not the full TOML grammar.

_toml_read_scoop() {
  _trs_file="$1"
  [ -f "$_trs_file" ] || return 0
  awk '
    BEGIN { capture = 0 }
    {
      line = $0
      if (!capture) {
        if (line ~ /^[ ]*scoop[ ]*=/) {
          capture = 1
          sub(/^[ ]*scoop[ ]*=[ ]*/, "", line)
        } else {
          next
        }
      }
      while (match(line, /"[^"]*"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
      if (line ~ /\]/) capture = 0
    }
  ' "$_trs_file"
}

# stdin packages → rewrite scoop in FILE; leave other keys alone.
_toml_write_scoop() {
  _tws_file="$1"
  [ -f "$_tws_file" ] || { unset _tws_file; return 1; }

  _tws_block="${_tws_file}.block.$$"
  {
    printf 'scoop = [\n'
    while IFS= read -r _tws_pkg || [ -n "$_tws_pkg" ]; do
      [ -z "$_tws_pkg" ] && continue
      printf '  "%s",\n' "$_tws_pkg"
    done
    printf ']\n'
  } > "$_tws_block"

  _tws_tmp="${_tws_file}.new.$$"

  if grep -Eq '^[ ]*scoop[ ]*=' "$_tws_file"; then
    awk -v blockfile="$_tws_block" '
      function emit(   line) { while ((getline line < blockfile) > 0) print line; close(blockfile) }
      {
        if (capture) { if ($0 ~ /\]/) capture = 0; next }
        if ($0 ~ /^[ ]*scoop[ ]*=/) {
          emit()
          if ($0 !~ /\]/) capture = 1
          next
        }
        print
      }
    ' "$_tws_file" > "$_tws_tmp"
  elif grep -Eq '^[ ]*\[' "$_tws_file"; then
    awk -v blockfile="$_tws_block" '
      function emit(   line) { while ((getline line < blockfile) > 0) print line; close(blockfile) }
      BEGIN { injected = 0 }
      {
        if (!injected && $0 ~ /^[ ]*\[/) { emit(); injected = 1 }
        print
      }
    ' "$_tws_file" > "$_tws_tmp"
  else
    cat "$_tws_block" > "$_tws_tmp"
    if [ -s "$_tws_file" ]; then
      printf '\n' >> "$_tws_tmp"
      cat "$_tws_file" >> "$_tws_tmp"
    fi
  fi

  _ksm_inplace_from "$_tws_tmp" "$_tws_file" || {
    rm -f "$_tws_tmp" "$_tws_block"
    unset _tws_file _tws_block _tws_tmp _tws_pkg
    return 1
  }
  rm -f "$_tws_tmp" "$_tws_block"
  unset _tws_file _tws_block _tws_tmp _tws_pkg
}

# VALUE must already be TOML-shaped (quoted string, bare number/bool, …).
_toml_set_trust_key() {
  _tsk_file="$1" _tsk_key="$2" _tsk_val="$3"
  [ -f "$_tsk_file" ] || { unset _tsk_file _tsk_key _tsk_val; return 1; }

  _tsk_tmp="${_tsk_file}.new.$$"

  if grep -Eq '^\[trust\]' "$_tsk_file"; then
    awk -v key="$_tsk_key" -v val="$_tsk_val" '
      BEGIN { in_trust = 0; done = 0 }
      /^\[/ {
        if (in_trust && !done) { print key " = " val; done = 1 }
        in_trust = ($0 == "[trust]")
        print
        next
      }
      {
        if (in_trust && !done && $0 ~ ("^[ ]*" key "[ ]*=")) {
          print key " = " val
          done = 1
          next
        }
        print
      }
      END {
        if (in_trust && !done) print key " = " val
      }
    ' "$_tsk_file" > "$_tsk_tmp"
  else
    cat "$_tsk_file" > "$_tsk_tmp"
    printf '\n[trust]\n%s = %s\n' "$_tsk_key" "$_tsk_val" >> "$_tsk_tmp"
  fi

  _ksm_inplace_from "$_tsk_tmp" "$_tsk_file" || {
    rm -f "$_tsk_tmp"
    unset _tsk_file _tsk_key _tsk_val _tsk_tmp
    return 1
  }
  rm -f "$_tsk_tmp"
  unset _tsk_file _tsk_key _tsk_val _tsk_tmp
}

_toml_get_trust_key() {
  _tgk_file="$1" _tgk_key="$2"
  [ -f "$_tgk_file" ] || return 1
  grep -E '^[ ]*'"$_tgk_key"'[ ]*=' "$_tgk_file" 2>/dev/null \
    | head -1 | sed 's/.*=[ ]*//; s/^"//; s/"$//; s/[[:space:]]*$//'
  unset _tgk_file _tgk_key
}
