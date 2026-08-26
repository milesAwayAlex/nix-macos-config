# Body of the `prefs-status` tool built by preferences.nix. The `check` calls
# are generated from the declared configuration and appended below; `summary`
# closes the run and sets the exit status.
#
# `defaults` is called by absolute path — it is Apple's, SIP-protected, and the
# only runtime dependency here beyond bash.

checked=0
drifted=0
label=''

# check <label> <key> scalar|blob <expected> <domain>...
# A key written to more than one domain is only ok when every domain agrees.
check() {
    local this_label=$1 key=$2 kind=$3 want=$4
    shift 4

    if [ "$this_label" != "$label" ]; then
        label=$this_label
        # The domains are worth showing: controlcenter's is a per-machine
        # ByHost path, and a paired domain shows which half is missing.
        printf '── %s  (%s)\n' "$label" "$*"
    fi
    checked=$((checked + 1))

    local ok=1 shown='' value verdict
    for domain in "$@"; do
        if ! value=$(/usr/bin/defaults read "$domain" "$key" 2>/dev/null); then
            value=''
        fi
        if [ "$kind" = blob ]; then
            [ -n "$value" ] || ok=0
        else
            [ "$value" = "$want" ] || ok=0
        fi
        shown=${shown:+$shown / }${value:-unset}
    done

    if [ "$kind" = blob ]; then
        if [ "$ok" = 1 ]; then shown='set'; else shown='unset'; fi
    fi

    if [ "$ok" = 1 ]; then
        verdict=ok
    else
        verdict=DRIFT
        drifted=$((drifted + 1))
    fi

    printf '   %-44s %-22.22s %s\n' "$key" "$shown" "$verdict"
}

summary() {
    printf '\n%s keys checked, %s drifted\n' "$checked" "$drifted"
    [ "$drifted" = 0 ]
}

