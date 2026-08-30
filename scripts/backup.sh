#!/usr/bin/env bash
# ==============================================================================
# scripts/backup.sh — backup consistente e não destrutivo da stack.
#
# O que é backupado (ver README > Backup para detalhes):
#   - Prometheus: snapshot da TSDB (via admin API), não o diretório "quente"
#     inteiro — evita copiar um WAL em escrita.
#   - Loki: diretório /loki inteiro (chunks + índice + regras).
#   - Grafana: diretório /var/lib/grafana inteiro (grafana.db + plugins).
#   - Config como código: prometheus/, loki/, alloy/, grafana/provisioning,
#     grafana/dashboards, docker-compose.yml e .env.
#
# Este script NÃO para nenhum container. Usa `docker compose cp`, que não
# depende de nenhuma ferramenta (tar/wget) existir dentro das imagens —
# funciona mesmo com Alloy/Node Exporter/cAdvisor (imagens mínimas).
#
# O .env vai dentro do backup porque sem ele a stack não é reproduzível —
# por isso o arquivo gerado é sensível (contém a senha do Grafana e
# possíveis webhooks de alerta) e deve ser guardado com o mesmo cuidado que
# o .env original (nunca commitar, restringir permissões, considerar
# criptografar antes de mover para armazenamento externo).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BACKUP_DIR="$ROOT_DIR/backups"
KEEP="${BACKUP_KEEP:-7}"
TS="$(date +%Y%m%d-%H%M%S)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

log()  { printf '\033[1;34m[backup]\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m[backup][erro]\033[0m %s\n' "$1" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"

log "Disparando snapshot da TSDB do Prometheus..."
SNAPSHOT_JSON="$(docker compose exec -T prometheus wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot || true)"
SNAPSHOT_NAME="$(printf '%s' "$SNAPSHOT_JSON" | grep -oE '"name":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"

if [ -z "${SNAPSHOT_NAME:-}" ]; then
  fail "Não foi possível criar o snapshot do Prometheus. A stack está no ar? --web.enable-admin-api está habilitado? Resposta: $SNAPSHOT_JSON"
fi
log "Snapshot criado: $SNAPSHOT_NAME"

mkdir -p "$STAGE/prometheus-snapshot" "$STAGE/loki-data" "$STAGE/grafana-data" "$STAGE/config"

docker compose cp "prometheus:/prometheus/snapshots/$SNAPSHOT_NAME" "$STAGE/prometheus-snapshot/$SNAPSHOT_NAME"
docker compose cp "loki:/loki" "$STAGE/loki-data"
docker compose cp "grafana:/var/lib/grafana" "$STAGE/grafana-data"

log "Copiando configuração como código..."
cp -r prometheus loki alloy grafana docker-compose.yml "$STAGE/config/"
[ -f .env ] && cp .env "$STAGE/config/.env"

ARCHIVE="$BACKUP_DIR/observability-backup-$TS.tar.gz"
log "Compactando em $ARCHIVE ..."
tar czf "$ARCHIVE" -C "$STAGE" .
chmod 600 "$ARCHIVE"

log "Removendo snapshot temporário de dentro do container Prometheus..."
docker compose exec -T prometheus rm -rf "/prometheus/snapshots/$SNAPSHOT_NAME" || true

log "Backup concluído: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

log "Aplicando retenção de backups locais (mantendo os $KEEP mais recentes)..."
# shellcheck disable=SC2012
ls -1t "$BACKUP_DIR"/observability-backup-*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" | xargs -r rm --

log "Feito. Copie $ARCHIVE para fora da VPS periodicamente (S3, outro host, etc.) — um backup que só existe na própria VPS não protege contra a perda da VPS."
