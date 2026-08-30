#!/usr/bin/env bash
# ==============================================================================
# scripts/healthcheck.sh — status rápido de toda a stack.
#
# Combina três fontes:
#   1. `docker compose ps` — estado dos containers (running/healthy).
#   2. Endpoints HTTP internos, checados via `docker compose exec` — só para
#      os serviços cujas imagens realmente têm uma ferramenta HTTP (grafana
#      via curl, prometheus via wget — confirmado em cada Dockerfile oficial,
#      ver docker-compose.yml).
#   3. A própria métrica `up` do Prometheus, para loki, node-exporter,
#      cadvisor e alloy — cujas imagens são mínimas ou distroless (sem
#      shell/wget/curl), então não dá pra checar HTTP "de dentro" delas.
#      Loki é a exceção parcial: como ele fala HTTP e está na mesma rede
#      Docker, sondamos http://loki:3100 a partir do container do
#      Prometheus (que tem wget) — sem precisar exec'ar no próprio Loki.
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
if docker compose exec -T grafana curl -f -s -o /dev/null "http://localhost:3000/api/health" 2>/dev/null; then
  ok "grafana (http://localhost:3000/api/health)"
else
  bad "grafana (http://localhost:3000/api/health)"
fi
if docker compose exec -T prometheus wget -q --spider "http://localhost:9090/-/healthy" 2>/dev/null; then
  ok "prometheus (http://localhost:9090/-/healthy)"
else
  bad "prometheus (http://localhost:9090/-/healthy)"
fi
# Loki não tem shell/wget/curl na imagem (distroless) — sondado a partir do
# container do Prometheus, via rede Docker interna.
if docker compose exec -T prometheus wget -q --spider "http://loki:3100/ready" 2>/dev/null; then
  ok "loki (http://loki:3100/ready, sondado via prometheus)"
else
  bad "loki (http://loki:3100/ready, sondado via prometheus)"
fi

hdr "Targets do Prometheus (up == 1)"
# Uma query por job (em vez de baixar `up` inteiro e tentar casar por regex)
# evita parsing de JSON aninhado no bash: o campo "job" fica dentro de
# "metric" e fecha com "}" ANTES do "value" irmão aparecer, então um regex
# tipo "job":"x"[^}]*"value" nunca bate — foi exatamente esse bug que fazia
# até job=prometheus (que é auto-scrape e não deveria falhar nunca) aparecer
# como FAIL. Filtrando por job na própria query, a resposta só tem a série
# daquele job, então basta procurar por `"value":[...,"1"]` em qualquer lugar.
for job in prometheus node-exporter cadvisor grafana loki; do
  RESULT="$(docker compose exec -T prometheus wget -qO- "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22${job}%22%7D" 2>/dev/null || true)"
  if printf '%s' "$RESULT" | grep -q '"value":\[[0-9.]*,"1"\]'; then
    ok "job=$job"
  else
    bad "job=$job (ver 'docker compose logs $job' e Prometheus > Status > Targets)"
  fi
done

hdr "Ingestão de logs no Loki (últimos 5 minutos)"
# Mesma lógica: sem shell no container do Loki, a query roda a partir do
# Prometheus (mesma rede `monitoring`, resolve "loki" via DNS interno).
#
# Usa /query_range (não /query) com start/end explícitos — /query é para
# queries instantâneas e não é o jeito certo de perguntar "teve log nos
# últimos N minutos". Também não basta checar '"status":"success"': o Loki
# responde sucesso mesmo com resultado vazio (zero logs), então checamos se
# o array "result" tem pelo menos um stream populado.
NOW_TS="$(date +%s)"
FROM_TS="$((NOW_TS - 300))"
LOKI_QUERY_URL="http://loki:3100/loki/api/v1/query_range?query=%7Bjob%3D~%22.%2B%22%7D&start=${FROM_TS}&end=${NOW_TS}&limit=1"
LOKI_RESPONSE="$(docker compose exec -T prometheus wget -qO- "$LOKI_QUERY_URL" 2>/dev/null || true)"
if printf '%s' "$LOKI_RESPONSE" | grep -q '"result":\[{'; then
  ok "Loki tem pelo menos 1 linha de log nos últimos 5 minutos"
elif printf '%s' "$LOKI_RESPONSE" | grep -q '"status":"success"'; then
  bad "Loki respondeu, mas sem nenhuma linha de log nos últimos 5 minutos — verifique 'docker compose logs alloy'"
else
  bad "Loki não respondeu como esperado a $LOKI_QUERY_URL"
fi

hdr "Resumo"
echo "  Sucesso: $PASS  |  Falhas: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
