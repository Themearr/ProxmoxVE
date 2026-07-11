#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Themearr
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Themearr/themearr

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# =============================================================================
# DEPENDENCIES
# =============================================================================

msg_info "Installing Dependencies"
# Theme audio is fetched over HTTP from the youtube-mp36 RapidAPI, so ffmpeg/yt-dlp
# are no longer needed. openssl is used to generate the API auth token below.
$STD apt-get install -y \
  curl \
  openssl
msg_ok "Installed Dependencies"

# =============================================================================
# .NET 9 RUNTIME
# =============================================================================

msg_info "Installing .NET 9 Runtime"
$STD bash -c "curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 9.0 --runtime aspnetcore --install-dir /usr/share/dotnet"
ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
msg_ok "Installed .NET 9 Runtime"

# =============================================================================
# DOWNLOAD & DEPLOY APPLICATION
# =============================================================================

get_lxc_ip

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_SUFFIX="linux-x64" ;;
  aarch64) ARCH_SUFFIX="linux-arm64" ;;
  *)       msg_error "Unsupported architecture: $ARCH"; exit 1 ;;
esac
fetch_and_deploy_gh_release "themearr" "Themearr/themearr" "prebuild" "latest" "/opt/themearr" "themearr-${ARCH_SUFFIX}.tar.gz"

msg_info "Setting up Application"
mkdir -p /opt/themearr/data
# The API fail-closes if THEMEARR_AUTH_TOKEN is unset, so generate a 256-bit token
# (preserving an existing one on re-run) and hand it to the service via EnvironmentFile.
AUTH_ENV="/opt/themearr/data/auth.env"
if [[ ! -s "$AUTH_ENV" ]]; then
  THEMEARR_TOKEN="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  (umask 077; printf 'THEMEARR_AUTH_TOKEN=%s\n' "$THEMEARR_TOKEN" >"$AUTH_ENV")
  chmod 600 "$AUTH_ENV"
else
  THEMEARR_TOKEN="$(grep -oP '^THEMEARR_AUTH_TOKEN=\K.*' "$AUTH_ENV")"
fi
msg_ok "Set up Application"

# =============================================================================
# CREATE SYSTEMD SERVICE
# =============================================================================

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/themearr.service
[Unit]
Description=Themearr Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/themearr
EnvironmentFile=/opt/themearr/data/auth.env
Environment="HOME=/opt/themearr/data"
Environment="XDG_CACHE_HOME=/opt/themearr/data/.cache"
Environment="DB_PATH=/opt/themearr/data/themearr.db"
Environment="THEMEARR_VERSION_FILE=/opt/themearr/VERSION"
Environment="ASPNETCORE_URLS=http://0.0.0.0:8080"
ExecStart=/usr/local/bin/dotnet /opt/themearr/Themearr.API.dll
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now themearr
msg_ok "Created Service"

# Save the access token where the operator can retrieve it, and print it once.
{
  echo "Themearr Access Token: ${THEMEARR_TOKEN}"
} >~/themearr.creds
chmod 600 ~/themearr.creds
msg_ok "Access token saved to /root/themearr.creds"
echo -e "\n  Themearr access token (enter this in the web UI on first load):\n    ${THEMEARR_TOKEN}\n  Also saved at /root/themearr.creds\n"

# =============================================================================
# IN-APP UPDATER HELPER
# =============================================================================
# The in-app "Update" button runs this fixed path. It prefers the checksum-verified
# deploy.sh shipped inside the release, and only falls back to fetching it (pinned to
# the installed tag, never mutable main). The service runs as root, so no sudo needed.

msg_info "Installing updater helper"
cat <<'UPDATER_EOF' >/usr/local/bin/themearr-update
#!/usr/bin/env bash
set -euo pipefail
REPO="Themearr/themearr"
LOCAL="/opt/themearr/deploy.sh"
if [[ -f "$LOCAL" ]]; then
  exec bash "$LOCAL"
fi
REF="$(cat /opt/themearr/VERSION 2>/dev/null || echo main)"
[[ "$REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || REF="main"
curl -fsSL "https://raw.githubusercontent.com/${REPO}/${REF}/deploy.sh" | bash
UPDATER_EOF
chmod 755 /usr/local/bin/themearr-update
chown root:root /usr/local/bin/themearr-update
msg_ok "Installed updater helper"

# =============================================================================
# CLEANUP & FINALIZATION
# =============================================================================

motd_ssh
customize
cleanup_lxc
