#!/usr/bin/env bash
# ==============================================================================
# scripts/install.sh — instalação/inicialização idempotente da stack.
#
# Rodar de novo depois que a stack já está no ar NÃO quebra nada: o script
# só cria o que ainda não existe e nunca sobrescreve .env ou dados.
#
# O que este script faz:
#   1. Verifica SO, Docker e Docker Compose (não instala nada sozinho —
#      apenas orienta, já que instalar Docker é uma ação de sistema que deve
#      ser uma decisão explícita do operador).
#   2. Cria .env a partir de .env.example, se .env ainda não existir.
#   3. Valida se GRAFANA_ADMIN_PASSWORD foi trocado do valor padrão.
#   4. Valida o docker-compose.yml (`docker compose config`).
#   5. Sobe a stack (`docker compose up -d`).
#   6. Aguarda os serviços ficarem saudáveis e imprime um resumo de status.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m[install][atenção]\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m[install][erro]\033[0m %s\n' "$1" >&2; exit 1; }

log "Verificando pré-requisitos..."

if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "${ID:-}" = "ubuntu" ] && [ "${VERSION_ID:-}" = "24.04" ]; then
    log "Ubuntu 24.04 detectado."
  else
    warn "SO detectado: ${PRETTY_NAME:-desconhecido} (stack foi validada em Ubuntu 24.04 — deve funcionar em outras distros com Docker, mas sem garantia)."
  fi
else
  warn "Não foi possível identificar o SO (/etc/os-release ausente)."
fi

command -v docker >/dev/null 2>&1 || fail "Docker não encontrado. Instale antes de continuar: https://docs.docker.com/engine/install/ubuntu/"

if docker compose version >/dev/null 2>&1; then
  log "Docker Compose plugin encontrado: $(docker compose version --short 2>/dev/null || true)"
else
  fail "Plugin 'docker compose' não encontrado (o pacote docker-compose-plugin é necessário, não o binário legado docker-compose)."
fi

if ! docker info >/dev/null 2>&1; then
  fail "Não foi possível falar com o daemon do Docker. Seu usuário está no grupo 'docker'? (sudo usermod -aG docker \$USER && newgrp docker)"
fi

log "Verificando arquivo .env..."
if [ ! -f .env ]; then
  cp .env.example .env
  log ".env criado a partir de .env.example — edite os valores (senha do Grafana, timezone, retenção) antes de ir para produção."
else
  log ".env já existe — mantendo como está (nunca sobrescrito por este script)."
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

if [ "${GRAFANA_ADMIN_PASSWORD:-}" = "change-me-strong-password" ]; then
  warn "GRAFANA_ADMIN_PASSWORD ainda está com o valor padrão do .env.example. Troque antes de expor a stack."
fi

log "Validando docker-compose.yml..."
docker compose config >/dev/null || fail "docker compose config falhou — corrija o docker-compose.yml/.env antes de continuar."

mkdir -p backups

log "Subindo a stack (docker compose up -d)..."
docker compose up -d

log "Aguardando serviços ficarem saudáveis (até 2 minutos)..."
DEADLINE=$((SECONDS + 120))
while [ $SECONDS -lt $DEADLINE ]; do
  UNHEALTHY=$(docker compose ps --format '{{.Service}} {{.Health}}' 2>/dev/null | awk '$2=="starting"' | wc -l | tr -d ' ')
  [ "${UNHEALTHY:-0}" = "0" ] && break
  sleep 5
done

echo
log "Status final:"
docker compose ps

echo
log "Instalação concluída. Acesse o Grafana em: ${GRAFANA_ROOT_URL:-http://localhost:${GRAFANA_PORT:-3000}}"
log "Para checar a saúde detalhada da stack: scripts/healthcheck.sh"
