# `keychain_secret ITEM`, for the darwin tools that keep a generated secret in
# the login keychain (D43, D45): prints the item's value, or makes one when
# security says it is not there (44); any other failure, a locked keychain, is
# no reason for a new one. Values reach `security` on stdin only.
''
  keychain_secret() {
    local rc=0 value
    value=$(/usr/bin/security find-generic-password -s "$1" -a "$USER" -w 2>/dev/null) || rc=$?
    if [ "$rc" -eq 44 ]; then
      value=$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n')
      printf 'add-generic-password -s %s -a %s -w "%s"\n' "$1" "$USER" "$value" |
        /usr/bin/security -i >/dev/null
    elif [ "$rc" -ne 0 ]; then
      echo "the login keychain did not answer for $1 ($rc)" >&2
      return 1
    fi
    printf '%s' "$value"
  }
''
