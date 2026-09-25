#!/bin/sh
set -eu
umask 077
env_file=${1:-.env}
backup_file=${2:-trmnl-$(date +%Y%m%d-%H%M%S).dump}
if [ -e "$backup_file" ]; then
  echo "Plik kopii już istnieje; wybierz inną nazwę." >&2
  exit 1
fi
# Set COMPOSE_PROJECT_NAME / DOCKER_CONTEXT for a non-default deployment.
temporary_file=$(mktemp "${backup_file}.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT HUP INT TERM
docker compose --env-file "$env_file" exec -T db pg_dump -U trmnl -d trmnl -Fc > "$temporary_file"
test -s "$temporary_file"
ln "$temporary_file" "$backup_file"
echo "Zapisano kopię bazy. Zachowaj także plik .env w bezpiecznym miejscu."
