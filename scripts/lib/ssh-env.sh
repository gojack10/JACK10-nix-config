# Sourceable helpers for local, gitignored SSH defaults.
# Real hostnames/users/ports belong in ~/.ssh/config or local/ssh.env, never git.

jack10_ssh_env_file() {
  printf '%s\n' "${JACK10_SSH_ENV:-$HOME/.config/JACK10-nix-config/local/ssh.env}"
}

jack10_load_ssh_env() {
  local env_file
  env_file="$(jack10_ssh_env_file)"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi
}

jack10_git_ssh_url() {
  local target="$1"
  local port="${2:-}"
  local path="$3"

  if [[ "$path" = /* ]]; then
    if [[ -n "$port" ]]; then
      printf 'ssh://%s:%s%s\n' "$target" "$port" "$path"
    else
      printf 'ssh://%s%s\n' "$target" "$path"
    fi
  else
    if [[ -n "$port" ]]; then
      printf 'ssh://%s:%s/%s\n' "$target" "$port" "$path"
    else
      printf '%s:%s\n' "$target" "$path"
    fi
  fi
}

jack10_ssh_display() {
  local target="$1"
  local port="${2:-}"
  if [[ -n "$port" ]]; then
    printf 'ssh -p %s %s\n' "$port" "$target"
  else
    printf 'ssh %s\n' "$target"
  fi
}
