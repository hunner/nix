#!/usr/bin/env bash
#
# Give the `agents` user access to hunner's gpg-agent (and so the YubiKey),
# through gpg-agent's own restricted extra socket. Run this AS HUNNER:
#
#   bash ~/Documents/git/nix/hosts/liminal/modules/agents-gpg-bridge/setup-agents-gpg.sh
#
# and afterwards, once gpg-agent has been restarted:
#
#   bash .../setup-agents-gpg.sh --verify
#
# It is idempotent: run it as many times as you like.
#
# It never touches private key material. The only thing that crosses to the
# agents user is the PUBLIC key and a text file naming a socket path.
#
# Order matters, and the script enforces it. gpg-agent refuses to start at all
# if the extra-socket directory is missing, so `extra-socket` must not go live
# in ~/.gnupg/gpg-agent.conf until systemd-tmpfiles has created
# /run/agents-gpg -- which happens during `nixos-rebuild switch`, no reboot
# needed, provided modules/agents-gpg-bridge is imported.

set -euo pipefail

SOCKET_DIR=/run/agents-gpg
SOCKET_PATH="$SOCKET_DIR/S.gpg-agent.extra"
AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"

# hunner's certification key, and the signing subkey git uses.
PRIMARY_FPR=6B147327595D299854FED9D51CED67750173FC1C
SIGNING_KEY=0xEF99694AA599DDAD
GIT_NAME="Hunter Haugen"
GIT_EMAIL="hunter@haugen.email"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m   %s\n' "$*"; }
warn() { printf '    \033[33mwarn\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -un)" = "hunner" ] || die "run this as hunner, not $(id -un)"

# ---------------------------------------------------------------- verify mode
if [ "${1:-}" = "--verify" ]; then
  say "Verifying the bridge end to end"

  [ -S "$SOCKET_PATH" ] || die "$SOCKET_PATH is not a socket. Has gpg-agent been restarted since the conf change? (gpgconf --kill gpg-agent; gpg-connect-agent /bye)"
  ok "socket exists: $(ls -ld "$SOCKET_PATH")"

  perms=$(stat -c '%a %U %G' "$SOCKET_PATH")
  case "$perms" in
    660\ hunner\ ai) ok "socket perms: $perms" ;;
    *) die "socket perms are '$perms', expected '660 hunner ai'. Check: systemctl --user status agents-gpg-socket.path agents-gpg-socket.service" ;;
  esac

  say "Can agents reach the agent?"
  sudo -u agents gpg-connect-agent 'GETINFO version' /bye 2>&1 | sed 's/^/    /'
  # "connection to the agent is in restricted mode" on stderr is the CORRECT
  # result: it proves the extra socket is in use rather than the full one.

  say "Can agents produce a real signature? (touch the key when it chimes)"
  echo "agents-bridge-verify" | sudo -u agents gpg --sign --local-user "$SIGNING_KEY" \
    --output /tmp/agents-bridge-verify.gpg --yes
  ok "signature written"

  say "Does that signature verify against hunner's keyring?"
  gpg --verify /tmp/agents-bridge-verify.gpg 2>&1 | sed 's/^/    /'
  rm -f /tmp/agents-bridge-verify.gpg

  say "All checks passed."
  exit 0
fi

# --------------------------------------------------------------- prepare mode
say "1/4  Checking $SOCKET_DIR exists (created by systemd-tmpfiles)"
[ -d "$SOCKET_DIR" ] || die "$SOCKET_DIR does not exist.
       Import modules/agents-gpg-bridge in hosts/liminal/configuration.nix and
       run 'sudo nixos-rebuild switch' FIRST. Enabling extra-socket before the
       directory exists stops gpg-agent from starting at all."
ok "$(ls -ld "$SOCKET_DIR")"

say "2/4  Enabling extra-socket in $AGENT_CONF"
[ -f "$AGENT_CONF" ] || die "$AGENT_CONF not found"
want="extra-socket $SOCKET_PATH"
if grep -qxF "$want" "$AGENT_CONF"; then
  ok "already enabled"
elif grep -qxF "#$want" "$AGENT_CONF"; then
  cp -a "$AGENT_CONF" "$AGENT_CONF.bak.$(date +%Y%m%d-%H%M%S)"
  # Only the exact commented line, so the old macOS extra-socket comment and
  # every other commented setting are left untouched.
  sed -i "s|^#${want}$|${want}|" "$AGENT_CONF"
  ok "uncommented (backup kept alongside)"
else
  cp -a "$AGENT_CONF" "$AGENT_CONF.bak.$(date +%Y%m%d-%H%M%S)"
  printf '%s\n' "$want" >> "$AGENT_CONF"
  ok "appended (backup kept alongside)"
fi

say "3/4  Exporting the PUBLIC key for the agents user"
pub=$(mktemp /tmp/hunner-pub.XXXXXX.asc)
trap 'rm -f "$pub"' EXIT
gpg --export --armor --export-options export-minimal "$PRIMARY_FPR" > "$pub"
chmod 0644 "$pub"
ok "$(wc -c < "$pub") bytes of public key at $pub"

say "4/4  Configuring ~agents/.gnupg and ~agents/.gitconfig"
sudo -u agents env \
  PUBKEY="$pub" \
  SOCKET_PATH="$SOCKET_PATH" \
  PRIMARY_FPR="$PRIMARY_FPR" \
  SIGNING_KEY="$SIGNING_KEY" \
  GIT_NAME="$GIT_NAME" \
  GIT_EMAIL="$GIT_EMAIL" \
  bash -s <<'AGENTS_SIDE'
set -euo pipefail
say()  { printf '    \033[1m-- %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m   %s\n' "$*"; }

# sudo keeps the caller's cwd, which agents may not be able to read -- and git
# stats the cwd before doing anything, even for --global config.
cd "$HOME"

GNUPGHOME_DIR="$HOME/.gnupg"
mkdir -p "$GNUPGHOME_DIR"
chmod 0700 "$GNUPGHOME_DIR"

# gpg is fussy about where it expects to find S.gpg-agent. With no
# /run/user/988 (agents is a system user with no lingering session) it uses
# the homedir, but assert rather than assume -- a stray XDG_RUNTIME_DIR in the
# environment can move it.
want_sock=$(gpgconf --list-dirs agent-socket)
if [ "$want_sock" != "$GNUPGHOME_DIR/S.gpg-agent" ]; then
  printf '!! gpg expects its agent socket at %s, not in the homedir.\n' "$want_sock" >&2
  printf '   Unset XDG_RUNTIME_DIR for the agents user and re-run.\n' >&2
  exit 1
fi

say "redirect file -> $SOCKET_PATH"
# A regular file where gpg looks for the agent socket. libassuan reads the
# %Assuan% header and connects to the named socket instead. This is gpg's own
# redirection mechanism, not a bridge or a proxy.
if [ -S "$GNUPGHOME_DIR/S.gpg-agent" ]; then
  printf '!! %s is a real socket -- an agent is running as agents.\n' "$GNUPGHOME_DIR/S.gpg-agent" >&2
  printf '   Stop it (gpgconf --kill gpg-agent) and re-run.\n' >&2
  exit 1
fi
printf '%%Assuan%%\nsocket=%s\n' "$SOCKET_PATH" > "$GNUPGHOME_DIR/S.gpg-agent"
ok "$(tr '\n' ' ' < "$GNUPGHOME_DIR/S.gpg-agent")"

say "gpg.conf"
# no-autostart is the important one: without it, any failure to reach hunner's
# agent silently spawns a keyless agent here and signing fails in a confusing
# way (and the new agent would clobber the redirect file above).
cat > "$GNUPGHOME_DIR/gpg.conf" <<EOF
no-autostart
default-key $SIGNING_KEY
keyid-format 0xlong
with-fingerprint
no-greeting
EOF
ok "written"

say "importing the public key"
gpg --quiet --import "$PUBKEY"
printf '%s:6:\n' "$PRIMARY_FPR" | gpg --quiet --import-ownertrust
ok "$(gpg --list-keys --with-colons "$PRIMARY_FPR" | grep -c '^uid') uids, trust=$(gpg --list-keys --with-colons "$PRIMARY_FPR" | awk -F: '/^pub/{print $2}')"

say "git identity"
# Written key by key so the existing credential helpers and safe.directory
# entries in ~agents/.gitconfig survive.
git config --global user.name       "$GIT_NAME"
git config --global user.email      "$GIT_EMAIL"
git config --global user.signingkey "$SIGNING_KEY"
git config --global commit.gpgsign  true
git config --global gpg.program     gpg
ok "$(git config --global user.name) <$(git config --global user.email)> key $(git config --global user.signingkey)"
AGENTS_SIDE

say "Prepared. Two steps left, and they are yours to run:"
cat <<EOF

  1. Restart gpg-agent so it binds the relocated extra socket. This drops the
     cached PIN and any ssh-agent identities in the current session:

         gpgconf --kill gpg-agent && gpg-connect-agent /bye

  2. Verify end to end (this will ask for a touch):

         bash ${BASH_SOURCE[0]} --verify

EOF
