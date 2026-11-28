#!/usr/bin/env bash
set -Eeuo pipefail

# Rebuild only the dedicated Authelia Compose project.
# Deliberately does NOT run `docker system prune` or touch other Docker projects.

readonly IMAGE='docker.io/authelia/authelia:4.39.28'
readonly PROJECT_NAME='authelia-forward-auth-for-immich'
readonly PROJECT_DIR="${HOME}/System_Scripts/${PROJECT_NAME}"
readonly DOMAIN='hpelitebook8460p.billfish-emperor.ts.net'
readonly USERNAME='hpserver'
readonly DISPLAY_NAME='HP Server'
readonly AUTH_PORT='9091'

say()  { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -ne 0 ]] || die 'Run this script as your normal server user (hpserver), not with sudo.'
[[ -t 0 && -t 1 ]] || die 'Run this script from an interactive terminal; password creation requires a TTY.'
[[ -n "${HOME:-}" && "$PROJECT_DIR" == "$HOME/System_Scripts/$PROJECT_NAME" ]] || die 'Unexpected project path; refusing to continue.'
[[ ! -L "$HOME/System_Scripts" ]] || die "System_Scripts is a symbolic link: $HOME/System_Scripts. Resolve it manually first."
[[ ! -L "$PROJECT_DIR" ]] || die "Project directory is a symbolic link: $PROJECT_DIR. Resolve it manually first."

for cmd in docker openssl curl script sed grep awk tee seq; do
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done

docker compose version >/dev/null 2>&1 || die 'Docker Compose plugin is required.'
docker info >/dev/null 2>&1 || die 'Cannot access Docker. Ensure the Docker daemon is running and this user can use it.'

cat <<EOF

AUTHELIA FULL REBUILD

This will completely reset the dedicated Authelia installation at:
  $PROJECT_DIR

It will:
  • Stop/remove this Authelia Compose project and its containers/orphan containers.
  • Remove Compose-managed volumes and project-labelled leftover volumes.
  • Remove the Authelia image tag, then pull the pinned image again.
  • DELETE the entire Authelia project directory, including config, SQLite data,
    secrets, backups, TOTP registrations, sessions and notification history.
  • Recreate the directory structure, fresh secrets, YAML configuration and user
    database with a newly generated Argon2 password hash.
  • Start Authelia and check its local health endpoint.

It will NOT:
  • Run global Docker cleanup/prune.
  • Delete Immich, its PostgreSQL database, Redis, ML data or images.
  • Delete or modify other Docker projects, Caddy configuration, Tailscale Funnel,
    Cloudflare Tunnel or Immich configuration.

After rebuilding, previously enrolled TOTP devices must be enrolled again.
The Caddy listener on 127.0.0.1:9081 and Funnel portal on port 10000 are expected
 to remain configured as they are now.
EOF

read -r -p 'Proceed with this destructive Authelia-only rebuild? Type YES: ' CONFIRM
[[ "$CONFIRM" == 'YES' ]] || die 'Cancelled. No changes were made.'

say 'Stopping and removing the existing Authelia Compose project, including its volumes.'
if [[ -f "$PROJECT_DIR/compose.yaml" ]]; then
  docker compose -p "$PROJECT_NAME" -f "$PROJECT_DIR/compose.yaml" down --volumes --remove-orphans
fi

# If a container named authelia remains, only remove it when Compose labels prove
# that it belongs to this exact project. Never remove a similarly named unrelated container.
if docker container inspect authelia >/dev/null 2>&1; then
  EXISTING_PROJECT="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' authelia 2>/dev/null || true)"
  if [[ "$EXISTING_PROJECT" == "$PROJECT_NAME" ]]; then
    docker rm -f authelia
  else
    die "A container named 'authelia' remains but is not labelled as project '$PROJECT_NAME'. Inspect it manually; refusing to remove it."
  fi
fi

say 'Removing any leftover volumes labelled for this Authelia project.'
mapfile -t PROJECT_VOLUMES < <(docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT_NAME")
if ((${#PROJECT_VOLUMES[@]})); then
  docker volume rm "${PROJECT_VOLUMES[@]}"
fi

say 'Removing the Authelia image tag (other Docker images and projects are untouched).'
docker image rm "$IMAGE" >/dev/null 2>&1 || true

say 'Deleting the complete Authelia project directory.'
if [[ -d "$PROJECT_DIR" ]]; then
  rm -rf -- "$PROJECT_DIR"
fi
mkdir -p "$PROJECT_DIR/config" "$PROJECT_DIR/data" "$PROJECT_DIR/secrets" "$PROJECT_DIR/backups"
chmod 750 "$PROJECT_DIR" "$PROJECT_DIR/config" "$PROJECT_DIR/data" "$PROJECT_DIR/backups"
chmod 700 "$PROJECT_DIR/secrets"

say 'Pulling the pinned Authelia image.'
docker pull "$IMAGE"

say 'Generating new, independent Authelia secrets.'
umask 077
openssl rand -hex 64 > "$PROJECT_DIR/secrets/reset_password_jwt_secret"
openssl rand -hex 64 > "$PROJECT_DIR/secrets/session_secret"
openssl rand -hex 64 > "$PROJECT_DIR/secrets/storage_encryption_key"
chmod 600 "$PROJECT_DIR/secrets/"*

cat > "$PROJECT_DIR/.env" <<EOF
PUID=$(id -u)
PGID=$(id -g)
EOF
chmod 600 "$PROJECT_DIR/.env"

cat > "$PROJECT_DIR/compose.yaml" <<'EOF'
services:
  authelia:
    image: docker.io/authelia/authelia:4.39.28
    container_name: authelia
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    init: true
    security_opt:
      - no-new-privileges:true
    ports:
      - "127.0.0.1:9091:9091"
    environment:
      AUTHELIA_SESSION_SECRET_FILE: /secrets/session_secret
      AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE: /secrets/storage_encryption_key
      AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE: /secrets/reset_password_jwt_secret
    volumes:
      - ./config:/config
      - ./data:/data
      - ./secrets:/secrets:ro
EOF

cat > "$PROJECT_DIR/config/configuration.yml" <<EOF
---
theme: dark

server:
  address: 'tcp://:9091/'
  endpoints:
    authz:
      forward-auth:
        implementation: 'ForwardAuth'

log:
  level: info

totp:
  issuer: 'HP EliteBook Home Server'
  algorithm: 'SHA1'
  digits: 6
  period: 30

authentication_backend:
  password_reset:
    disable: true
  file:
    path: '/config/users_database.yml'
    watch: true
    password:
      algorithm: 'argon2'
      argon2:
        variant: 'argon2id'
        iterations: 3
        memory: 65536
        parallelism: 4
        key_length: 32
        salt_length: 16

access_control:
  default_policy: 'deny'
  rules:
    - domain: '$DOMAIN'
      policy: 'two_factor'

session:
  name: 'authelia_session'
  same_site: 'lax'
  inactivity: '15m'
  expiration: '2h'
  remember_me: -1
  cookies:
    - domain: '$DOMAIN'
      authelia_url: 'https://$DOMAIN:10000'
      default_redirection_url: 'https://$DOMAIN:8443'

identity_validation:
  reset_password:
    jwt_lifespan: '5 minutes'

storage:
  local:
    path: '/data/db.sqlite3'

notifier:
  filesystem:
    filename: '/data/notifications.txt'
EOF
chmod 640 "$PROJECT_DIR/config/configuration.yml"

cat > "$PROJECT_DIR/.gitignore" <<'EOF'
secrets/
data/
backups/
config/users_database.yml
.env
EOF
cp "$PROJECT_DIR/.gitignore" "$PROJECT_DIR/.cursorignore"
chmod 640 "$PROJECT_DIR/.gitignore" "$PROJECT_DIR/.cursorignore"

say 'Generating the user password hash with Authelia interactive password prompts.'
printf '%s\n' 'The Authelia CLI will ask for the password twice. Input is not echoed.'
printf '%s\n' 'The plaintext password is not written to disk or placed in the shell command line.'

# util-linux `script` supplies a pseudo-terminal so Authelia can securely prompt
# and confirm the password. tee displays the CLI prompts while command substitution
# captures only the CLI transcript for extracting its Digest line.
HASH_TRANSCRIPT="$(script -q -c "docker run --rm -it '$IMAGE' authelia crypto hash generate argon2" /dev/null 2>/dev/null | tee /dev/tty)" || die 'Authelia password hashing command failed.'
PASSWORD_HASH="$(printf '%s\n' "$HASH_TRANSCRIPT" | tr -d '\r' | sed -nE 's/.*Digest: (\$argon2id[^[:space:]]*).*/\1/p' | tail -n 1)"
unset HASH_TRANSCRIPT
[[ "$PASSWORD_HASH" == \$argon2id\$* ]] || die 'Could not extract an Argon2id digest from Authelia output. No user database was written.'

say 'Writing the user database with the Argon2id hash (not the plaintext password).'
{
  printf '%s\n' '---' 'users:' "  $USERNAME:" "    displayname: '$DISPLAY_NAME'" "    password: '$PASSWORD_HASH'" '    groups: []'
} > "$PROJECT_DIR/config/users_database.yml"
chmod 600 "$PROJECT_DIR/config/users_database.yml"
unset PASSWORD_HASH

say 'Validating the Docker Compose file and Authelia configuration.'
docker compose -p "$PROJECT_NAME" -f "$PROJECT_DIR/compose.yaml" config -q
docker compose -p "$PROJECT_NAME" -f "$PROJECT_DIR/compose.yaml" run --rm --no-deps authelia authelia config validate --config /config/configuration.yml

say 'Starting Authelia.'
docker compose -p "$PROJECT_NAME" -f "$PROJECT_DIR/compose.yaml" up -d

say 'Waiting for Authelia health endpoint.'
HEALTH_OK=0
for _ in $(seq 1 30); do
  if curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:${AUTH_PORT}/api/health" >/dev/null 2>&1; then
    HEALTH_OK=1
    break
  fi
  sleep 1
done

if [[ "$HEALTH_OK" -ne 1 ]]; then
  docker compose -p "$PROJECT_NAME" -f "$PROJECT_DIR/compose.yaml" logs --tail 80 authelia || true
  die 'Authelia did not become healthy. Inspect the logs above before attempting further changes.'
fi

cat <<EOF

SUCCESS: Authelia was rebuilt from scratch.

Project:       $PROJECT_DIR
Compose name:  $PROJECT_NAME
Image:         $IMAGE
Health:        http://127.0.0.1:$AUTH_PORT/api/health
Portal:        https://$DOMAIN:10000/
Protected app: https://$DOMAIN:8443/
Username:      $USERNAME

Next steps:
  1. Open the Authelia portal and log in with the new password.
  2. Enrol your TOTP authenticator again; old TOTP registrations were deleted.
  3. Test the protected Immich Funnel URL in a private browser window.
  4. Check logs with: docker compose -p $PROJECT_NAME -f '$PROJECT_DIR/compose.yaml' logs --tail 80 authelia

Caddy and Tailscale Funnel were not modified. This script did not run global Docker prune.
EOF
