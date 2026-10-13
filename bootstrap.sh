#!/usr/bin/env bash
# Bootstrap a talmar install on the NixOS ISO. Lives in a *public* repo/gist
# because talmar itself is private: it pulls the ssh key off the YubiKey,
# clones talmar with it and hands over to talmar's install.sh.
#
#   curl -L <url>/bootstrap.sh | bash
#   curl -L <url>/bootstrap.sh | bash -s -- <host> [disk]   (args go to install.sh)
#
# Contains no secrets; the key stays on the YubiKey (PIN + touch per use).
set -euo pipefail

repo=${TALMAR_REPO:-git@github.com:wobbat/talmar.git}
dest=${TALMAR_DEST:-$HOME/.talmar}
key=$HOME/.ssh/id_ed25519_sk

say() { printf '\e[1m==> %s\e[0m\n' "$*"; }
die() { printf '\e[31merror:\e[0m %s\n' "$*" >&2; exit 1; }

git() {
  if command -v git >/dev/null; then command git "$@"
  else nix-shell -p git --run "git $(printf '%q ' "$@")"; fi
}

# Everything runs inside main: bash has read the whole script before
# stdin is switched to the terminal.
main() {
  # Under `curl | bash` stdin is the script; prompts must use the terminal.
  exec </dev/tty

  mkdir -p ~/.ssh && chmod 700 ~/.ssh

  # --- ssh key off the YubiKey ------------------------------------------------
  if [[ -f $key ]]; then
    say "using existing $key"
  else
    say "reading resident ssh key from the YubiKey (PIN)"
    tmp=$(mktemp -d)
    (cd "$tmp" && ssh-keygen -K) || die "ssh-keygen -K failed (YubiKey plugged in / connected to the VM?)"
    shopt -s nullglob
    found=("$tmp"/id_ed25519_sk_rk*)
    found=("${found[@]/%.pub/}")
    mapfile -t found < <(printf '%s\n' "${found[@]}" | sort -u)
    ((${#found[@]} > 0)) || die "no ed25519-sk resident key on the YubiKey"
    ((${#found[@]} == 1)) || die "several resident keys found in $tmp; move the right one to $key by hand"
    install -m 600 "${found[0]}" "$key"
    install -m 644 "${found[0]}.pub" "$key.pub"
    rm -rf "$tmp"
  fi

  # GitHub's published host key, so the clone doesn't stop to ask.
  grep -qs '^github.com ssh-ed25519' ~/.ssh/known_hosts ||
    echo 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' >>~/.ssh/known_hosts

  # --- clone ------------------------------------------------------------------
  if [[ -d $dest/.git ]]; then
    say "$dest already cloned; pulling (PIN + touch)"
    git -C "$dest" pull --ff-only
  else
    say "cloning $repo (PIN + touch)"
    git clone "$repo" "$dest"
  fi

  # --- install ----------------------------------------------------------------
  say "starting install.sh"
  exec "$dest/install.sh" "$@"
}

main "$@"
