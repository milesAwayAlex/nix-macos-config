# Merge a remote base branch into the current branch; gupp also pushes.
gup() { _git_update_base gup "$@"; }
gupp() { _git_update_base gupp "$@"; }

_git_update_base() {
  local command=$1 remote=origin branch='' advertised kind ref name
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        printf 'usage: %s [-r remote] [branch]\n' "$command"
        printf 'Merge the remote default branch (or the named branch) into the current branch.\n'
        [ "$command" != gupp ] || printf 'Push normally after a successful merge.\n'
        return 0
        ;;
      -r|--remote)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          printf '%s: %s requires a remote name\n' "$command" "$1" >&2
          return 2
        fi
        remote=$2
        shift 2
        ;;
      --) shift; break ;;
      -*) printf '%s: unknown option: %s\n' "$command" "$1" >&2; return 2 ;;
      *) break ;;
    esac
  done
  if [ "$#" -gt 1 ]; then
    printf 'usage: %s [-r remote] [branch]\n' "$command" >&2
    return 2
  fi
  if [ "$#" -eq 1 ]; then
    branch=$1
    if ! git check-ref-format "refs/heads/$branch"; then
      printf '%s: invalid branch: %s\n' "$command" "$branch" >&2
      return 2
    fi
  fi

  # This operation updates a branch, never a detached checkout.
  git symbolic-ref --quiet HEAD >/dev/null || {
    printf '%s: run from a checked-out branch\n' "$command" >&2
    return 1
  }
  git remote get-url -- "$remote" >/dev/null || return

  if [ -z "$branch" ]; then
    # Ask the remote: origin/HEAD can be missing or stale after a rename.
    advertised=$(git ls-remote --symref -- "$remote" HEAD) || return
    while read -r kind ref name; do
      if [ "$kind" = ref: ] && [ "$name" = HEAD ] && [[ "$ref" == refs/heads/* ]]; then
        branch=${ref#refs/heads/}
        break
      fi
    done <<< "$advertised"
    if [ -z "$branch" ]; then
      printf '%s: %s did not advertise a default branch; specify one explicitly\n' "$command" "$remote" >&2
      return 1
    fi
  fi

  printf '%s: merging %s/%s into the current branch\n' "$command" "$remote" "$branch"
  # Fetch the exact branch and merge what was fetched, even with a narrow or
  # custom remote fetch mapping. A deleted branch fails instead of merging a
  # stale remote-tracking ref. Git owns merge policy and local-change checks.
  git fetch -- "$remote" "refs/heads/$branch" || return
  git merge -- FETCH_HEAD || return
  if [ "$command" = gupp ]; then
    git push
  fi
}
