#!/usr/bin/env bash
# security.txt has an expiry date, and RFC 9116 says a reader must ignore the file once it
# passes. So the failure mode is silent: nothing breaks, the page still serves, and a
# researcher who finds a bug is left with no address that counts. This turns that date into
# a build failure a month ahead, which is the only reminder that cannot be dismissed.
#
# It also checks that every place naming the mailbox agrees. The address is on a different
# domain than the product, so the copy tells researchers to confirm it against the site —
# that instruction is only worth anything while the copies match.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECURITY_TXT="${ROOT}/apps/web/public/.well-known/security.txt"

# Fail with a month of runway. A warning would get read once and scrolled past.
FAIL_DAYS=30
WARN_DAYS=90

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "${SECURITY_TXT}" ]] || fail "missing ${SECURITY_TXT#"${ROOT}/"}"

expires="$(sed -n 's/^Expires:[[:space:]]*\(.*\)/\1/p' "${SECURITY_TXT}" | tr -d '\r' | head -1)"
[[ -n "${expires}" ]] || fail "security.txt has no Expires field (RFC 9116 requires one)"

expires_epoch="$(date -u -d "${expires}" +%s 2>/dev/null)" \
  || fail "security.txt Expires is not a date this machine can read: ${expires}"

now_epoch="$(date -u +%s)"
days_left=$(( (expires_epoch - now_epoch) / 86400 ))

renew_hint="renew it in ${SECURITY_TXT#"${ROOT}/"} (and re-read the text around it: an address
  that no longer works is worse than none). Keep the new date under a year out."

if (( days_left < 0 )); then
  fail "security.txt expired ${days_left#-} days ago — researchers are told to ignore it. ${renew_hint}"
fi

if (( days_left < FAIL_DAYS )); then
  fail "security.txt expires in ${days_left} days — ${renew_hint}"
fi

# RFC 9116 asks for less than a year so the file stays evidence that someone is still
# reading the mailbox. A renewal that overshoots defeats the point of having a date.
if (( days_left > 366 )); then
  fail "security.txt expires in ${days_left} days, over the year RFC 9116 asks for — a date that far out stops meaning anyone is still there"
fi

# One mailbox, four copies. Take security.txt as the source and hold the rest against it.
contact="$(sed -n 's/^Contact:[[:space:]]*mailto:\(.*\)/\1/p' "${SECURITY_TXT}" | tr -d '\r' | head -1)"
[[ -n "${contact}" ]] || fail "security.txt has no 'Contact: mailto:' line"

for surface in \
  apps/web/src/lib/site.ts \
  apps/web/src/i18n/es.ts \
  apps/web/src/i18n/en.ts \
  docs/threat-model.md
do
  grep -qF "${contact}" "${ROOT}/${surface}" \
    || fail "${surface} does not name ${contact}, but security.txt does — a researcher who tries to confirm the address against the site will find two answers"
done

if (( days_left < WARN_DAYS )); then
  echo "security.txt: ${days_left} days left (${expires}) — worth renewing on the next pass"
else
  echo "security.txt OK: ${contact}, ${days_left} days left, all copies agree"
fi
