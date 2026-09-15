#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
emacsclient_bin=${EMACSCLIENT:-emacsclient}
"$emacsclient_bin" --eval "(progn (load \"$root/scripts/etaf-ui-surfaces-gui.el\" nil t t) (etaf-ui-gui-interactions-start))" >/dev/null
end=$(( $(date +%s) + ${GUI_TIMEOUT:-90} ))
while [ "$(date +%s)" -lt "$end" ]; do
  result=$("$emacsclient_bin" --eval 'etaf-ui-gui-interactions' 2>/dev/null || true)
  case "$result" in
    *"(complete passed)"*) "$emacsclient_bin" --eval '(format "GUI interactions: %d passed" (1- (length etaf-ui-gui-interactions)))'; exit 0 ;;
    *failed*) printf '%s\n' "$result" >&2; exit 1 ;;
  esac
  sleep 1
done
printf '%s\n' "ETAF UI GUI check timed out" >&2
exit 2
