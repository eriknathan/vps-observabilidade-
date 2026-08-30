#!/usr/bin/env bash
# ==============================================================================
# scripts/healthcheck.sh — status rápido de toda a stack.
#
# Combina duas fontes:
#   1. `docker compose ps` — estado dos containers (running/healthy).
#   2. Endpoints HTTP internos, checados via `docker compose exec` (os
#      serviços não publicam porta no host — ver README > Segurança), para
#      os serviços cujas imagens têm wget (grafana, prometheus, loki).
#   3. A própria métrica `up` do Prometheus, para node-exporter, cadvisor e
#      alloy — cujas imagens são mínimas (sem wget/shell utilitário), então
#      não dá pra checar HTTP "de dentro" delas (ver docker-compose.yml).
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

PASS=0
FAIL=0

ok()   { printf '  [ \033[1;32mOK\033[0m ] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [\033[1;31mFAIL\033[0m] %s\n' "$1"; FAIL=$((FAIL+1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

hdr "docker compose ps"
docker compose ps

hdr "Healthchecks HTTP internos"
check_http() {
  local service="$1" url="$2"
  if docker compose exec -T "$service" wget -q --spider "$url" 2>/dev/null; then
    ok "$service ($url)"
  else
    bad "$service ($url)"
  fi
}
check_http grafana    "http://localhost:3000/api/health"
check_http prometheus "http://localhost:9090/-/healthy"
check_http loki       "http://localhost:3100/ready"

hdr "Targets do Prometheus (up == 1)"
UP_JSON="$(docker compose exec -T prometheus wget -qO- 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null || true)"
if [ -z "$UP_JSON" ]; then
  bad "Não foi possível consultar o Prometheus"
else
  for job in prometheus node-exporter cadvisor grafana; do
    if printf '%s' "$UP_JSON" | grep -q "\"job\":\"$job\"[^}]*\"value\":\[[0-9.]*,\"1\"\]"; then
      ok "job=$job"
    else
      bad "job=$job (ver 'docker compose logs $job' e Prometheus > Status > Targets)"
    fi
  done
fi

hdr "Ingestão de logs no Loki (últimos 5 minutos)"
LOKI_LINES="$(docker compose exec -T loki wget -qO- 'http://localhost:3100/loki/api/v1/query?query={job=~".%2B"}&limit=1' 2>/dev/null || true)"
if printf '%s' "$LOKI_LINES" | grep -q '"status":"success"'; then
  ok "Loki respondeu a uma query de log"
else
  bad "Loki não respondeu como esperado — verifique se o Alloy está enviando logs (docker compose logs alloy)"
fi

hdr "Resumo"
echo "  Sucesso: $PASS  |  Falhas: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
