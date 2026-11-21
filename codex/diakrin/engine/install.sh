#!/bin/sh
# Diakrin CLI installer for macOS and Linux. https://diakrin.com/cli
#
#   curl -fsSL https://diakrin.com/cli/install.sh | sh
#   curl -fsSL https://diakrin.com/cli/install.sh | sh -s -- --version 0.2.0
#
# Downloads a release from https://github.com/Diakrin/diakrin-cli/releases, checks its
# SHA-256 against the release's SHA256SUMS before extracting anything, installs it into
# ~/.diakrin/versions/<version> and puts a `diakrin` launcher in ~/.local/bin.
# If cosign is installed, the Sigstore signature of SHA256SUMS is verified as well.
# No sudo, no telemetry and no credentials: the engine never signs in (the Diakrin plugin connects to Diakrin).
#
# Options:
#   --version X.Y.Z     install this version instead of the latest
#   --from-dir DIR      install from a downloaded release directory (no network)
#   --no-modify-path    do not add the launcher directory to your shell profile
#   --force             replace a `diakrin` launcher that this installer did not create
# Options the Diakrin plugin uses (plug-and-play local engine, docs/specs/plug-and-play-local-engine.md §3):
#   --pin-file FILE     version and per-platform SHA-256 from the plugin's engine.env (plain KEY=value lines;
#                       never sourced); installs into ~/.diakrin/bin, never edits a shell profile
#   --if-needed         exit at once when the installed engine is the pinned major and at least the pinned
#                       version, and start its daily `upgrade --auto` check
#   --background        do the work in a detached child and return immediately
#   --wait              wait (up to 120 s) for an install already running, then report
#   --context HOST      print one line of agent context for claude-code, codex or cursor; never exit non-zero
#   --claude-env-file F append the engine's PATH line to Claude Code's session env file once
# Environment:
#   DIAKRIN_HOME (default ~/.diakrin), DIAKRIN_BIN_DIR (default ~/.local/bin),
#   DIAKRIN_INSTALL_BASE (https release base, for company mirrors),
#   DIAKRIN_REQUIRE_SIGNATURE=1 (fail unless cosign verifies the signature)

set -eu

RELEASE_BASE="${DIAKRIN_INSTALL_BASE:-https://github.com/Diakrin/diakrin-cli/releases}"
SIGNER_IDENTITY_PREFIX='https://github.com/Diakrin/diakrin-platform/.github/workflows/cli-release.yml@refs/tags/cli-v'
SIGNER_ISSUER='https://token.actions.githubusercontent.com'
LAUNCHER_MARKER='# Managed by the Diakrin installer'
PROFILE_MARKER='# Added by the Diakrin installer'

version=''
from_dir=''
modify_path=1
force=0
tmp=''
pin_file=''
if_needed=0
background=0
wait_install=0
context=''
claude_env_file=''
lock=''
self="$0"

READY_LINE='Diakrin local engine is ready (~/.diakrin/bin/diakrin).'
INSTALLING_LINE='Diakrin local engine is being set up in the background; run its installer with --wait before the first local step.'
UNSUPPORTED_LINE='Diakrin local engine is not available on this computer yet; use the cloud Preview path.'
FAILED_LINE='Diakrin local engine could not be set up (no network or blocked download); use the cloud Preview path.'

# With --context, stdout carries exactly one line of agent context; everything else goes to stderr.
say() { if [ -n "$context" ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
emit_context() {
  [ -n "$context" ] || return 0
  if [ "$context" = cursor ]; then printf '{"additional_context":"%s"}\n' "$1"; else printf '%s\n' "$1"; fi
}
# A plugin hook must never fail the agent's session: with --context, failures print the context line and exit 0.
fail() { printf 'diakrin install: %s\n' "$*" >&2; if [ -n "$context" ]; then emit_context "$FAILED_LINE"; exit 0; fi; exit 1; }
unsupported() { printf 'diakrin install: %s\n' "$*" >&2; if [ -n "$context" ]; then emit_context "$UNSUPPORTED_LINE"; exit 0; fi; exit 2; }
cleanup() {
  if [ -n "$tmp" ]; then rm -rf "$tmp"; fi
  if [ -n "$lock" ]; then rm -rf "$lock"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || unsupported 'missing value for --version'; version="$2"; shift 2 ;;
    --from-dir) [ $# -ge 2 ] || unsupported 'missing value for --from-dir'; from_dir="$2"; shift 2 ;;
    --no-modify-path) modify_path=0; shift ;;
    --force) force=1; shift ;;
    --pin-file) [ $# -ge 2 ] || unsupported 'missing value for --pin-file'; pin_file="$2"; shift 2 ;;
    --if-needed) if_needed=1; shift ;;
    --background) background=1; shift ;;
    --wait) wait_install=1; shift ;;
    --context)
      [ $# -ge 2 ] || unsupported 'missing value for --context'
      case "$2" in claude-code|codex|cursor) context="$2" ;; *) unsupported "unknown --context '$2'" ;; esac
      shift 2 ;;
    --claude-env-file) [ $# -ge 2 ] || unsupported 'missing value for --claude-env-file'; claude_env_file="$2"; shift 2 ;;
    -h|--help) say 'Usage: install.sh [--version X.Y.Z] [--from-dir DIR] [--no-modify-path] [--force] [--pin-file FILE [--if-needed] [--background] [--wait] [--context claude-code|codex|cursor] [--claude-env-file FILE]]'; exit 0 ;;
    *) unsupported "unknown option: $1" ;;
  esac
done

is_version() { printf '%s' "$1" | grep -Eq '^[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}$'; }

# Platform. Windows is not supported yet; musl (Alpine) cannot run the bundled Node.
# The engine's PATH for Claude Code's later commands (nice to have: the skill always uses the absolute path).
if [ -n "$claude_env_file" ] && ! grep -qF '/.diakrin/bin:' "$claude_env_file" 2>/dev/null; then
  printf 'export PATH="$HOME/.diakrin/bin:$PATH"\n' >> "$claude_env_file" 2>/dev/null || true
fi

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) unsupported "unsupported operating system '$(uname -s)'. Supported: macOS and Linux (x64, arm64)." ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x64 ;;
  *) unsupported "unsupported processor '$(uname -m)'. Supported: x64 and arm64." ;;
esac
# A Terminal running under Rosetta reports x86_64 on Apple silicon; install the native build.
if [ "$os" = darwin ] && [ "$arch" = x64 ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then arch=arm64; fi
if [ "$os" = linux ] && ls /lib/ld-musl-* >/dev/null 2>&1; then
  unsupported 'musl-based Linux (for example Alpine) is not supported. Use a glibc-based distribution.'
fi
target="$os-$arch"
home="${DIAKRIN_HOME:-$HOME/.diakrin}"

version_ge() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,x,".");split(b,y,".");for(i=1;i<=3;i++){if(x[i]+0>y[i]+0)exit 0;if(x[i]+0<y[i]+0)exit 1}exit 0}'; }
pin_major=''; pin_version=''; pin_sha=''; pin_origin=''
if [ -n "$pin_file" ]; then
  [ -f "$pin_file" ] || fail "pin file not found: $pin_file"
  # Plain KEY=value lines with a strict character set; the file is never sourced or evaluated.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    printf '%s\n' "$line" | grep -Eq '^(ENGINE_MAJOR|ENGINE_VERSION|ENGINE_SHA256_(darwin|linux)_(arm64|x64)|DIAKRIN_API_ORIGIN)=[A-Za-z0-9._:/-]+$' ||
      fail 'the pin file has a line that is not a plain KEY=value setting.'
    key="${line%%=*}"; value="${line#*=}"
    case "$key" in
      ENGINE_MAJOR) pin_major="$value" ;;
      ENGINE_VERSION) pin_version="$value" ;;
      DIAKRIN_API_ORIGIN) pin_origin="$value" ;;
      "ENGINE_SHA256_${os}_${arch}") pin_sha="$value" ;;
    esac
  done < "$pin_file"
  is_version "$pin_version" || fail 'the pin file has no valid ENGINE_VERSION.'
  [ "$pin_major" = "${pin_version%%.*}" ] || fail 'ENGINE_MAJOR does not match ENGINE_VERSION in the pin file.'
  printf '%s' "$pin_sha" | grep -Eq '^[a-f0-9]{64}$' || unsupported "the pinned engine has no build for $target."
  printf '%s' "$pin_origin" | grep -Eq '^(https://[a-z0-9.-]+(:[0-9]{1,5})?|http://(127\.0\.0\.1|localhost)(:[0-9]{1,5})?)$' ||
    fail 'the pin file has no valid DIAKRIN_API_ORIGIN.'
  version="$pin_version"
  modify_path=0
  bin_dir="${DIAKRIN_BIN_DIR:-$home/bin}"
  mkdir -p "$home" "$HOME/.diakrin"
  # The engine sends transfer tokens only to origins listed here (written by the plugin's installer, never by a tool result). Always
  # under $HOME/.diakrin, whatever DIAKRIN_HOME says: a project setting must never choose which Diakrin receives tokens.
  grep -qxF "$pin_origin" "$HOME/.diakrin/origins" 2>/dev/null || printf '%s\n' "$pin_origin" >> "$HOME/.diakrin/origins"
else
  bin_dir="${DIAKRIN_BIN_DIR:-$HOME/.local/bin}"
fi
launcher="$bin_dir/diakrin"

# The installed engine is the pinned major and at least the pinned version (read from its launcher: no process start).
engine_current() {
  [ -n "$pin_version" ] || return 1
  text="$(cat "$launcher" 2>/dev/null)" || return 1
  case "$text" in *"$LAUNCHER_MARKER"*) ;; *) return 1 ;; esac
  dest_dir="$(printf '%s\n' "$text" | sed -n 's/^exec "\(.*\)\/bin\/diakrin" "\$@"$/\1/p')"
  [ -x "$dest_dir/bin/diakrin" ] || return 1
  current="$(basename "$dest_dir")"
  is_version "$current" || return 1
  [ "${current%%.*}" = "$pin_major" ] || return 1
  version_ge "$current" "$pin_version"
}
# An older engine of the pinned major still works: the agent uses it while the pinned version installs in the background,
# so a plugin update never makes the agent wait on (and prompt for) the installer.
engine_usable() {
  [ -n "$pin_version" ] || return 1
  text="$(cat "$launcher" 2>/dev/null)" || return 1
  case "$text" in *"$LAUNCHER_MARKER"*) ;; *) return 1 ;; esac
  dest_dir="$(printf '%s\n' "$text" | sed -n 's/^exec "\(.*\)\/bin\/diakrin" "\$@"$/\1/p')"
  [ -x "$dest_dir/bin/diakrin" ] || return 1
  current="$(basename "$dest_dir")"
  is_version "$current" || return 1
  [ "${current%%.*}" = "$pin_major" ]
}
wait_for_lock() {
  waited=0
  while [ -d "$home/.install.lock" ] && [ "$waited" -lt 1200 ]; do sleep 0.1; waited=$((waited + 1)); done
}
if [ "$wait_install" = 1 ]; then
  wait_for_lock
  if engine_current; then emit_context "$READY_LINE"; exit 0; fi
fi
if [ "$if_needed" = 1 ] && engine_current; then
  # Up to date for this plugin; the engine itself decides whether its daily signed-channel check is due.
  nohup "$launcher" upgrade --auto >/dev/null 2>&1 </dev/null &
  emit_context "$READY_LINE"
  exit 0
fi
if [ "$background" = 1 ] && [ -f "$self" ]; then
  mkdir -p "$home"
  set --
  [ -n "$pin_file" ] && set -- "$@" --pin-file "$pin_file"
  [ -n "$from_dir" ] && set -- "$@" --from-dir "$from_dir"
  [ -n "$version" ] && [ -z "$pin_file" ] && set -- "$@" --version "$version"
  [ "$modify_path" = 0 ] && set -- "$@" --no-modify-path
  [ "$force" = 1 ] && set -- "$@" --force
  nohup sh "$self" "$@" >"$home/install.log" 2>&1 </dev/null &
  if engine_usable; then emit_context "$READY_LINE"; else emit_context "$INSTALLING_LINE"; fi
  exit 0
fi

if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$1" | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null 2>&1; then sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
else fail 'sha256sum or shasum is required.'; fi
command -v tar >/dev/null 2>&1 || fail 'tar is required.'

tmp="$(mktemp -d "${TMPDIR:-/tmp}/diakrin-install.XXXXXX")"

# One install at a time per engine home (two AI tools starting at once); a lock older than 10 minutes is stale.
mkdir -p "$home"
if ! mkdir "$home/.install.lock" 2>/dev/null; then
  if [ -n "$(find "$home/.install.lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rm -rf "$home/.install.lock"; mkdir "$home/.install.lock" 2>/dev/null || fail 'another install is running.'
  else
    wait_for_lock
    if engine_current; then emit_context "$READY_LINE"; exit 0; fi
    mkdir "$home/.install.lock" 2>/dev/null || fail 'another install is still running.'
  fi
fi
lock="$home/.install.lock"

if [ -n "$from_dir" ]; then
  [ -d "$from_dir" ] || fail "release directory not found: $from_dir"
  fetch() { cp "$from_dir/$1" "$2" 2>/dev/null || fail "release file missing: $1"; }
  fetch_optional() { cp "$from_dir/$1" "$2" 2>/dev/null; }
  if [ -z "$version" ]; then fetch VERSION "$tmp/VERSION"; version="$(tr -d ' \r\n' < "$tmp/VERSION")"; fi
else
  case "$RELEASE_BASE" in https://*) ;; *) fail 'DIAKRIN_INSTALL_BASE must be an https:// URL.' ;; esac
  command -v curl >/dev/null 2>&1 || fail 'curl is required.'
  download() { curl --proto '=https' --tlsv1.2 -fsSL --retry 2 --connect-timeout 15 -o "$2" "$1"; }
  if [ -z "$version" ]; then
    download "$RELEASE_BASE/latest/download/VERSION" "$tmp/VERSION" ||
      fail "could not reach $RELEASE_BASE. Check your internet connection or proxy, then run the install line again."
    version="$(tr -d ' \r\n' < "$tmp/VERSION")"
  fi
  fetch() { download "$RELEASE_BASE/download/v$version/$1" "$2" || fail "could not download $1 for version $version."; }
  fetch_optional() { download "$RELEASE_BASE/download/v$version/$1" "$2" 2>/dev/null; }
fi
is_version "$version" || fail "invalid version '$version'."

archive="diakrin-$version-$target.tar.gz"
say "Installing Diakrin CLI $version ($target)..."
if [ -n "$pin_file" ]; then
  # The plugin's pinned SHA-256 is the trust anchor (the plugin itself is approved by IT).
  expected="$pin_sha"
else
fetch SHA256SUMS "$tmp/SHA256SUMS"

# Signature: verified when cosign is available, required when DIAKRIN_REQUIRE_SIGNATURE=1.
if command -v cosign >/dev/null 2>&1; then
  fetch_optional SHA256SUMS.sigstore.json "$tmp/SHA256SUMS.sigstore.json" || fail 'release signature (SHA256SUMS.sigstore.json) is missing.'
  cosign verify-blob "$tmp/SHA256SUMS" --bundle "$tmp/SHA256SUMS.sigstore.json" \
    --certificate-identity "$SIGNER_IDENTITY_PREFIX$version" --certificate-oidc-issuer "$SIGNER_ISSUER" >/dev/null 2>&1 ||
    fail 'signature verification failed. The release was not installed.'
  say 'Signature verified (Sigstore).'
elif [ "${DIAKRIN_REQUIRE_SIGNATURE:-0}" = 1 ]; then
  fail 'DIAKRIN_REQUIRE_SIGNATURE=1 but cosign is not installed. Install cosign (https://docs.sigstore.dev) and retry.'
fi

expected="$(awk -v f="$archive" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")"
printf '%s' "$expected" | grep -Eq '^[a-f0-9]{64}$' || fail "no checksum for $archive in SHA256SUMS. This platform may not be published for $version."
fi
fetch "$archive" "$tmp/$archive"
actual="$(sha256 "$tmp/$archive")"
[ "$actual" = "$expected" ] || fail "checksum mismatch for $archive (expected $expected, got $actual). The download was not installed."

if [ -e "$launcher" ] && [ "$force" != 1 ] && ! grep -q "$LAUNCHER_MARKER" "$launcher" 2>/dev/null; then
  fail "$launcher already exists and was not created by this installer. Remove it or rerun with --force."
fi

mkdir -p "$home/versions" "$bin_dir"
dest="$home/versions/$version"
if [ ! -x "$dest/bin/diakrin" ]; then
  staging="$home/versions/.staging-$version-$$"
  rm -rf "$staging"; mkdir -p "$staging"
  tar -xzf "$tmp/$archive" -C "$staging" --strip-components 1 || { rm -rf "$staging"; fail 'could not extract the archive.'; }
  # `diakrin --version` prints the bare version (releases before this change printed JSON when not on a terminal).
  # (The JSON may also carry latestVersion/updateAvailable once the CLI has looked up the latest release.)
  reported="$("$staging/bin/diakrin" --version 2>/dev/null | tr -d ' \r\n' || true)"
  case "$reported" in
    "$version"|"{\"version\":\"$version\","*) ;;
    *) rm -rf "$staging"; fail "the extracted CLI did not start (reported '$reported')." ;;
  esac
  rm -rf "$dest"; mv "$staging" "$dest"
fi

# Switch the launcher atomically; older versions stay in $home/versions.
printf '#!/bin/sh\n%s\nexec "%s/bin/diakrin" "$@"\n' "$LAUNCHER_MARKER" "$dest" > "$launcher.new.$$"
chmod 755 "$launcher.new.$$"
mv -f "$launcher.new.$$" "$launcher"

case ":${PATH:-}:" in
  *":$bin_dir:"*) on_path=1 ;;
  *) on_path=0 ;;
esac
# Another `diakrin` earlier in PATH (for example an older npm global install) would keep running instead of this one.
shadow="$(command -v diakrin 2>/dev/null || true)"
if [ "$shadow" = "$launcher" ]; then shadow=''; fi
profile=''
if { [ "$on_path" = 0 ] || [ -n "$shadow" ]; } && [ "$modify_path" = 1 ]; then
  case "$(basename "${SHELL:-sh}")" in
    zsh) profile="$HOME/.zshrc" ;;
    bash) if [ "$os" = darwin ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.bashrc"; fi ;;
    *) profile="$HOME/.profile" ;;
  esac
  if ! grep -q "$PROFILE_MARKER" "$profile" 2>/dev/null; then
    printf '\nexport PATH="%s:$PATH" %s\n' "$bin_dir" "$PROFILE_MARKER" >> "$profile"
    say "Added $bin_dir to PATH in $profile."
  fi
fi

say "Installed Diakrin CLI $version to $dest"
if [ -n "$pin_file" ] || [ -n "$context" ]; then
  # A plugin install: the engine lives in ~/.diakrin/bin and is always called by its absolute path; no next steps to print.
  emit_context "$READY_LINE"
  exit 0
fi
if [ "$on_path" = 0 ]; then say "Open a new terminal (or run: export PATH=\"$bin_dir:\$PATH\") so the diakrin command is found."; fi
if [ -n "$shadow" ]; then
  say ''
  say "Warning: 'diakrin' still runs $shadow, not the version just installed ($launcher)."
  case "$(readlink "$shadow" 2>/dev/null || true)$shadow" in
    *node_modules*) say '  It looks like an older npm install. Remove it with: npm uninstall -g @diakrin/builder-cli' ;;
    *) say "  Remove it, or run the new one directly: $launcher" ;;
  esac
  if [ -n "$profile" ]; then say "  New terminals run the new version first ($profile puts $bin_dir at the front). In this terminal run: export PATH=\"$bin_dir:\$PATH\"; hash -r"; fi
fi
say ''
say 'Next:'
say '  Using Diakrin to build apps? Install the Diakrin plugin in your AI tool (Claude Code, Cursor or Codex);'
say '  it connects to Diakrin and uses this engine. Your IT team may have installed it already.'
say '  Using an AI coding agent without the plugin? Teach it Diakrin (installs agent skills; no network):'
say '    diakrin init'
say '  Install Diakrin in your own AWS account (needs the AWS CLI signed in with admin rights):'
say '    diakrin self-hosted infra up --env diakrin.env'
say '    diakrin self-hosted deploy --env diakrin.env'
