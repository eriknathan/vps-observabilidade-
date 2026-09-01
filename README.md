# vps-observabilidade

Stack de observabilidade 100% declarativa para uma VPS Ubuntu 24.04: **Grafana + Prometheus + Loki + Grafana Alloy + cAdvisor + Node Exporter**, tudo via Docker Compose, com datasources, dashboards, plugins e alertas provisionados por código — nenhuma configuração manual pela UI do Grafana.

## Índice

1. [Visão geral](#1-visão-geral)
2. [Arquitetura](#2-arquitetura)
3. [Pré-requisitos](#3-pré-requisitos)
4. [Instalação do Docker](#4-instalação-do-docker)
5. [Estrutura de diretórios](#5-estrutura-de-diretórios)
6. [Configuração do .env](#6-configuração-do-env)
7. [Inicialização](#7-inicialização)
8. [Acesso ao Grafana](#8-acesso-ao-grafana)
9. [Datasources](#9-datasources)
10. [Dashboards](#10-dashboards)
11. [Plugins](#11-plugins)
12. [Prometheus](#12-prometheus)
13. [Node Exporter](#13-node-exporter)
14. [cAdvisor](#14-cadvisor)
15. [Loki](#15-loki)
16. [Alloy (Promtail vs. Alloy)](#16-alloy-promtail-vs-alloy)
17. [Logs](#17-logs)
18. [Alertas](#18-alertas)
19. [Backup](#19-backup)
20. [Atualização](#20-atualização)
21. [Segurança](#21-segurança)
22. [Troubleshooting](#22-troubleshooting)
23. [Deploy automático via GitHub Actions](#23-deploy-automático-via-github-actions)

---

## 1. Visão geral

Esta stack monitora o host (VPS) e todos os containers Docker rodando nele:

- **Grafana** — único ponto de acesso externo; visualização de métricas e logs.
- **Prometheus** — coleta e armazena métricas (host + containers + a própria stack).
- **Loki** — armazena e indexa logs.
- **Grafana Alloy** — coleta logs dos containers e do sistema operacional e envia ao Loki.
- **Node Exporter** — expõe métricas do sistema operacional da VPS.
- **cAdvisor** — expõe métricas de CPU/memória/rede/disco por container Docker.

Tudo é definido em arquivo (YAML/JSON) e versionado no Git. Subir a stack do zero é `cp .env.example .env && docker compose up -d`.

## 2. Arquitetura

```
                              INTERNET
                                 │
                          (só esta porta é exposta)
                                 │
                          ┌──────▼──────┐
                          │   Grafana   │  :3000 (host) → 3000 (container)
                          └──────┬──────┘
                                 │  rede docker "monitoring" (interna)
                 ┌───────────────┼───────────────┐
                 │               │               │
          ┌──────▼─────┐  ┌──────▼─────┐        │
          │ Prometheus │  │    Loki    │◄───────┐│
          │   :9090    │  │   :3100    │        ││
          └──────┬─────┘  └────────────┘        ││
                 │ scrape                        ││ push
     ┌───────────┼───────────┐                   ││
     │           │           │                   ││
┌────▼─────┐ ┌───▼─────┐ ┌───▼────┐         ┌────▼┴────┐
│  Node    │ │ cAdvisor│ │ Grafana│         │  Alloy   │
│ Exporter │ │  :8080  │ │ :3000  │         │ (logs)   │
│  :9100   │ │         │ │/metrics│         └────┬─────┘
└────┬─────┘ └────┬────┘ └────────┘              │
     │            │                    docker.sock + journald
     └──────┬─────┴───────────────────────────────┘
            │
      Ubuntu 24.04 + Docker (host + containers)
```

Decisões de arquitetura (por quê):

- **Só o Grafana é publicado no host.** Prometheus, Loki, cAdvisor, Node Exporter e Alloy só existem dentro da rede Docker `monitoring` — não há motivo para expô-los à internet, e isso elimina uma superfície de ataque inteira sem nenhum custo funcional (Regra 3 — Segurança).
- **Alerting embutido no Grafana, sem Alertmanager separado.** Um único mecanismo de alerta que enxerga tanto Prometheus (PromQL) quanto Loki (LogQL) é mais simples de operar numa única VPS do que rodar mais um componente (Regra 6 — Simplicidade).
- **Alloy no lugar de Promtail** — ver [seção 16](#16-alloy-promtail-vs-alloy).
- **Volumes nomeados do Docker**, não bind mounts para dados — evita problemas de permissão/UID entre host e containers e mantém o backup simples via `docker compose cp`.

## 3. Pré-requisitos

- VPS com **Ubuntu 24.04** (outras distros com Docker recente devem funcionar, mas não foram o alvo da validação).
- Acesso root/sudo.
- Docker Engine ≥ 25 e o plugin `docker compose` (v2 — **não** o binário legado `docker-compose`).
- Portas: `22` (SSH) sempre; `3000` só se o Grafana for exposto diretamente (ver [Segurança](#21-segurança)).
- Recomendado: ao menos 2 vCPUs / 4 GB RAM livres para a stack de observabilidade além das suas aplicações (ver [seção 21 do CONTEXT.md / limites de recursos](#12-prometheus) para como reduzir o consumo em VPS menores).

## 4. Instalação do Docker

Se o Docker ainda não estiver instalado na VPS:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
newgrp docker
docker compose version   # confirma que o plugin v2 está presente
```

`scripts/install.sh` verifica isso automaticamente e para com uma mensagem clara se faltar algo — ele **não** instala o Docker sozinho (é uma decisão de sistema que cabe a você tomar explicitamente).

## 5. Estrutura de diretórios

```
.
├── docker-compose.yml
├── .env.example
├── .gitignore
├── README.md
├── prometheus/
│   ├── prometheus.yml
│   ├── targets/
│   │   └── additional-targets.json.example
│   └── rules/
│       ├── system-recording-rules.yml
│       └── docker-recording-rules.yml
├── loki/
│   └── loki-config.yml
├── alloy/
│   └── config.alloy
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/datasources.yml
│   │   ├── dashboards/dashboards.yml
│   │   ├── alerting/
│   │   │   ├── rules.yml
│   │   │   ├── contact-points.yml
│   │   │   └── notification-policies.yml
│   │   └── plugins/          # vazio de propósito, ver seção 11
│   └── dashboards/
│       ├── infrastructure-overview-html.json
│       ├── host-metrics-html.json
│       ├── docker-containers-html.json
│       └── logs-overview-html.json
└── scripts/
    ├── install.sh
    ├── backup.sh
    └── healthcheck.sh
```

Sem `promtail/` (ver seção 16) e sem `grafana/config/` — o Grafana é configurado inteiramente via variáveis de ambiente no `docker-compose.yml`. `grafana/provisioning/plugins/` existe mas fica **vazio**: o Grafana sempre escaneia esse caminho no boot e loga erro se ele não existir, então o diretório está aqui só para isso não acontecer — o plugin de painel usado nesta stack é instalado via `GF_INSTALL_PLUGINS` (provisioning de plugin em YAML é para *app plugins*, não para painéis, então não temos nada real para colocar aí).

## 6. Configuração do .env

```bash
cp .env.example .env
```

Edite pelo menos:

| Variável | O que é |
|---|---|
| `TZ` | Timezone de todos os containers (ex.: `America/Sao_Paulo`) |
| `VPS_HOSTNAME` | Identificador desta VPS — vira label `host` em métricas e logs |
| `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` | Credenciais do admin, criadas no primeiro boot |
| `GRAFANA_PORT` | Porta publicada no host |
| `PROMETHEUS_RETENTION_DAYS` / `LOKI_RETENTION_DAYS` | Retenção de métricas/logs |
| `ALERT_*` | Credenciais dos canais de alerta (opcional, ver [seção 18](#18-alertas)) |

`.env` nunca é commitado (está no `.gitignore`). `.env.example` não tem segredos reais.

## 7. Inicialização

```bash
docker compose config      # valida o compose file
docker compose up -d       # sobe tudo em background
docker compose ps          # confere status
docker compose logs -f     # acompanha os logs de todos os serviços
docker compose down        # para tudo (dados persistem nos volumes nomeados)
```

Ou, de forma guiada: `./scripts/install.sh` (idempotente — pode rodar de novo a qualquer momento).

## 8. Acesso ao Grafana

`http://<ip-da-vps>:${GRAFANA_PORT:-3000}` (ou `http://localhost:3000` localmente), login com `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` do `.env`.

## 9. Datasources

Provisionados automaticamente em `grafana/provisioning/datasources/datasources.yml`:

- **Prometheus** (`uid: prometheus`) — `http://prometheus:9090`, datasource padrão.
- **Loki** (`uid: loki`) — `http://loki:3100`.

Nada a configurar em Connections > Data Sources — eles já existem no primeiro boot. `allowUiUpdates` não se aplica a datasources tipo file-provisioned da mesma forma que dashboards, mas edições manuais na UI também seriam perdidas no próximo redeploy do container, pelo mesmo princípio de Infrastructure as Code.

## 10. Dashboards

Importados automaticamente na pasta **Observability** a partir de `grafana/dashboards/*.json` (provider em `grafana/provisioning/dashboards/dashboards.yml`, com `allowUiUpdates: false` — mudanças na UI não persistem, o JSON no Git é a fonte da verdade).

Quatro dashboards standalone, cada um com um visual NOC escuro (fundo quase preto, acentos neon por métrica) construído inteiramente com o plugin HTML Graphics — sem depender de painéis nativos do Grafana para os números principais:

- **Infrastructure Overview** — landing page da stack: header com badge de saúde geral (SAUDÁVEL/ATENÇÃO/CRÍTICO calculado a partir de CPU/memória/disco/alvos), 8 mini-cards (CPU/RAM/Swap/Disk/Network/Load/Uptime/Containers), séries temporais de CPU/memória/disco/rede e um painel de status dos alvos do Prometheus (`up`). Responde "minha VPS está saudável?" de cara.
- **Host Metrics** — detalhamento completo do Node Exporter: cards de CPU/Memória/Armazenamento/Rede com sparkline e delta, carga do sistema (CPU por modo empilhado + load average), composição de memória (donut + swap), filesystems, latência de disco, tráfego por interface e um painel de **Problemas ativos** que busca em tempo real o estado das regras de alerta do Grafana (`/api/prometheus/grafana/api/v1/rules`) — não uma reimplementação paralela dos thresholds.
- **Docker / Containers** — cAdvisor, com variáveis `hostname`/`image`/`container`: overview (containers ativos, imagens, CPU/memória/rede/disco totais), séries por container de CPU/memória/rede/disco, Top 10 de cada recurso e memória usada vs. limite.
- **Logs Overview** — Loki, variáveis `hostname`/`container`/`compose_service`/`level`/`search`: contadores de linhas/erros/warnings do intervalo, volume de logs por nível, visualizador de logs com busca textual e um painel dedicado a erros recentes.

Para editar qualquer um: altere o `.json` correspondente em `grafana/dashboards/`, depois `docker compose restart grafana` (ou aguarde o `updateIntervalSeconds: 30` do provider recarregar sozinho) — não edite pela UI, a mudança seria descartada.

### Variáveis de template no Loki: use a query estruturada, não a string legada

Se for criar ou editar uma variável do tipo Query com datasource Loki, **não** use a sintaxe de string `label_values(seletor, label)` — o editor de variáveis do Grafana atual não reconhece esse formato de 2 argumentos de forma confiável (ele aceita silenciosamente e cai num estado inválido, sem erro visível) e a variável acaba resolvendo para um único valor incorreto, fazendo `$variavel` (com "All" selecionado) não casar com nenhuma série real. Use o objeto estruturado:

```json
"query": {
  "label": "container",
  "stream": "{job=~\"docker|systemd-journal\", host=~\"$hostname\"}",
  "type": 1,
  "refId": "container"
}
```

(`type: 1` = Label values, `type: 0` = Label names; omita `stream` para listar valores sem filtro.) Além disso, o `stream` **precisa** conter pelo menos um matcher que não seja compatível com string vazia — o LogQL rejeita um seletor onde *todos* os matchers casam com `""` (é exatamente o que `host=~"$hostname"` vira quando "All" expande para `.*`). Por isso o seletor acima sempre inclui `job=~"docker|systemd-journal"` junto com `host`, mesmo que o painel de destino já filtre por host sozinho.

## 11. Plugins

O plugin **HTML Graphics** (`gapit-htmlgraphics-panel`, catálogo oficial do Grafana, compatível com Grafana ≥ 8.2, versão atual instalada 2.2.3) é instalado automaticamente no boot via `GF_INSTALL_PLUGINS=gapit-htmlgraphics-panel` no `docker-compose.yml` — sem passo manual.

`GF_PANELS_DISABLE_SANITIZE_HTML=true` também está setado, necessário para o plugin renderizar HTML/CSS/JS customizado. Isso desabilita a sanitização de HTML nos painéis — um trade-off de segurança aceitável aqui porque o único HTML renderizado é o que **nós mesmos** escrevemos e versionamos nos dashboards JSON (não há input de usuário externo passando por esse caminho).

Os quatro dashboards usam o plugin extensivamente (não só em cabeçalhos decorativos): cards de estatística, gráficos de série temporal com tooltip, donuts, tabelas e o visualizador de logs são todos painéis HTML Graphics, com uma pequena biblioteca de funções JavaScript (formatação de bytes/duração, parsing dos dataframes do Grafana, renderização de linha/área/empilhado, sparklines) duplicada em cada painel — necessário porque cada instância do plugin roda isolada em sua própria Shadow DOM, sem escopo compartilhado entre painéis.

Confirmar que o plugin instalou: `docker compose logs grafana | grep -i plugin`.

## 12. Prometheus

Config em `prometheus/prometheus.yml`. Scrape a cada 15s de: `prometheus` (self), `node-exporter`, `cadvisor`, `grafana` e `loki` (meta-monitoramento de ambos — o job `loki` também é o único jeito de saber se o Loki está de pé, ver [seção 15](#15-loki)), mais um job `file-sd-targets` que lê `prometheus/targets/*.json` — para adicionar uma nova VPS, aplicação ou exporter no futuro, basta criar um arquivo JSON nesse diretório seguindo `additional-targets.json.example`; o Prometheus recarrega sozinho (`refresh_interval: 1m`), sem restart.

**Retenção**: `PROMETHEUS_RETENTION_DAYS` (padrão 15 dias) + `PROMETHEUS_RETENTION_SIZE` (padrão 5 GB) como teto de segurança — o que vier primeiro vence. Para VPS com pouco disco, reduza ambos no `.env`.

**Recording rules** (`prometheus/rules/`) pré-computam as agregações reaproveitadas pelos dashboards (CPU/memória/disco em % por host, CPU/memória/rede/disco por container) — evita recalcular a mesma expressão pesada toda vez que um painel renderiza.

**Ajustar para VPS pequena**: aumente `scrape_interval`/`evaluation_interval` no `global` (ex.: 30s), reduza a retenção, e evite adicionar exporters de alta cardinalidade sem necessidade.

## 13. Node Exporter

Container `node-exporter`, sem porta publicada, métricas de CPU (idle/user/system/iowait), memória (total/usada/disponível/cache/buffers/swap), disco (uso, I/O, read/write), filesystem, rede (tráfego/erros/pacotes/interfaces) e sistema (uptime, load, processos). Monta `/proc`, `/sys` e `/` (somente leitura) do host — sem precisar de `network_mode: host`, já que ele lê estado via esses mounts, não via namespace de rede. `--collector.filesystem.*-exclude` filtra mounts de overlay/containers para não poluir as séries com dezenas de filesystems irrelevantes.

## 14. cAdvisor

Container `cadvisor`, sem porta publicada. Volumes e por quê:

| Mount | Motivo |
|---|---|
| `/:/rootfs:ro` | Métricas de filesystem do host |
| `/var/run:/var/run:ro` | Socket e estado em runtime do Docker |
| `/sys:/sys:ro` | cgroups (CPU/memória/I/O por container) — Ubuntu 24.04 usa cgroup v2 |
| `/var/lib/docker:/var/lib/docker:ro` | Metadados/camadas de imagem para métricas de storage |
| `/dev/disk:/dev/disk:ro` | Mapeamento de dispositivos de disco |
| device `/dev/kmsg` | Leitura de mensagens do kernel usadas por alguns coletores |

Roda com `privileged: true` — necessário na prática para o cAdvisor enxergar métricas completas de cgroup v2/dispositivos nesta versão; é um trade-off de privilégio aceito **apenas dentro da rede interna** (o container não é exposto). Se ao validar na sua VPS específica o cAdvisor funcionar sem `privileged: true` (alguns kernels/configurações permitem), remova a flag — teste com `docker compose logs cadvisor` e confira se as métricas de memória/cgroup aparecem na linha Docker / Containers do dashboard Observability.

**Sobre a imagem**: usamos `ghcr.io/google/cadvisor`, não `gcr.io/cadvisor/cadvisor` — a partir da v0.53.0 o projeto migrou de registry (o antigo `gcr.io/cadvisor/cadvisor` só tem tags até v0.55.1 e não recebe mais publicações). Além disso, **evite as versões v0.54.1 até v0.56.x**: há uma regressão conhecida e ainda aberta ([google/cadvisor#3772](https://github.com/google/cadvisor/issues/3772), [#3793](https://github.com/google/cadvisor/issues/3793)) em que o cliente Docker embutido no cAdvisor falha ao negociar a versão da API contra um Docker Engine mais novo — o "Docker factory" não registra, e as métricas ficam só com o label `id` (caminho cru do cgroup), sem `name`/`image`. O sintoma é exatamente a linha *Docker / Containers* inteira em "No data" mesmo com `up{job="cadvisor"}` OK. Corrigido em v0.57.0 ([#3863](https://github.com/google/cadvisor/pull/3863)); esta stack usa v0.60.5.

Se depois de atualizar a stack o dashboard Docker ainda mostrar "No data", confirme a causa diretamente:
```bash
docker compose exec prometheus wget -qO- 'http://cadvisor:8080/metrics' | grep '^container_last_seen{' | head -3
```
Se aparecer só `{id="..."}` sem `name=`, a imagem em uso está na faixa afetada pela regressão.

Prometheus faz scrape de `cadvisor:8080/metrics`.

## 15. Loki

Config em `loki/loki-config.yml`: single-binary, `auth_enabled: false` (single tenant — só é alcançável na rede interna), storage em **filesystem** (sem S3/GCS), índice **TSDB v13** (o recomendado atualmente para esse tipo de deployment, substitui o boltdb-shipper legado). Compactor com retenção habilitada (`LOKI_RETENTION_DAYS`, padrão 14 dias). `limits_config` limita taxa de ingestão e streams por tenant para proteger a VPS de um container que passe a gerar volume anormal de log.

Detecção automática de nível de log (`detected_level`) vem habilitada por padrão no Loki 3.1+ (`discover_log_levels`) — não precisa configurar nada; é isso que alimenta o filtro "Nível" da linha Logs sem precisar transformar nível em label (ver seção 17).

**Sobre o healthcheck do Loki**: a imagem oficial (`grafana/loki`) é construída sobre `gcr.io/distroless/static:nonroot` — não tem shell, `wget`, `curl` nem nada além do binário do Loki, então **não existe como rodar um healthcheck HTTP de dentro do container** (por isso não há `healthcheck:` no serviço `loki` do `docker-compose.yml`, ao contrário do que uma primeira versão deste projeto assumiu incorretamente). A saúde do Loki é verificada de duas formas externas: o job `loki` no Prometheus (`up{job="loki"}`) e `scripts/healthcheck.sh`, que sonda `http://loki:3100` a partir do container do Prometheus (que tem `wget`), via a rede Docker interna. Por esse mesmo motivo, `grafana` e `alloy` dependem de `loki` com `condition: service_started` (não `service_healthy`) no compose — ambos toleram bem o Loki ainda estar de boot (Grafana demora mais para inicializar do que o Loki leva pra responder; o `loki.write` do Alloy já tem retry/backoff embutido).

## 16. Alloy (Promtail vs. Alloy)

**Promtail está deprecated e em EOL** (a Grafana Labs encerrou o suporte LTS em 28/02/2026; não recebe mais atualizações). O substituto oficial é o **Grafana Alloy**, o coletor unificado (baseado em OpenTelemetry Collector) para o qual todo o desenvolvimento novo migrou. Por isso esta stack usa **só Alloy — não há Promtail** aqui, mesmo o `CONTEXT.md` original sugerindo uma pasta `promtail/`: construir sobre um coletor morto contrariaria a própria regra do spec de não usar tecnologia deprecated.

Diferença prática:

| | Promtail | Alloy |
|---|---|---|
| Status | EOL (fev/2026) | Ativo, recomendado |
| Escopo | Só logs | Logs, métricas e traces num único agente |
| Configuração | YAML | Linguagem própria (River/Alloy), componentes composáveis |

`alloy/config.alloy` faz duas coisas:

1. **Logs de containers** via `discovery.docker` + `loki.source.docker`, lendo direto do socket do Docker — nenhuma aplicação precisa mudar log-driver ou reiniciar.
2. **Logs do sistema** via `loki.source.journal` (systemd-journal), que também cobre os logs do próprio `dockerd`.

A UI de debug do Alloy (porta 12345) roda em loopback **dentro** do container — não é publicada no host.

## 17. Logs

Labels usados nos logs: `job` (`docker` ou `systemd-journal`), `host`, `container`, `compose_service`, `image`. Nível de log **não** é label — é extraído automaticamente pelo Loki como `detected_level` (structured metadata), filtrável no dashboard sem aumentar cardinalidade de séries.

Por que esses labels e não outros: todos têm cardinalidade baixa e limitada pelo número de containers/imagens distintos, não pelo volume de linhas — o oposto (ex.: usar um ID de requisição ou timestamp como label) explodiria o número de streams do Loki e derrubaria a performance numa VPS pequena.

## 18. Alertas

Regras em `grafana/provisioning/alerting/rules.yml` (Grafana Unified Alerting, sem Alertmanager separado — ver seção 2):

| Alerta | Condição | Justificativa |
|---|---|---|
| Host down | `up{job="node-exporter"} < 1` por 2m | ~8 scrapes perdidos (intervalo 15s) — filtra reinícios rápidos |
| CPU alta | > 85% por 10m | Sustentado, não pico pontual |
| Memória baixa | uso > 90% por 10m | Margem antes do OOM-killer agir |
| Disco warning | > 80% por 15m | Linha de warning padrão da indústria |
| Disco crítico | > 90% por 5m | Reação rápida antes de esgotar |
| Container reiniciando | > 2 reinícios em 15m | Indica crash loop, não reinício manual isolado |
| Erros em log | > 20 linhas `error` em 5m | Ponto de partida conservador — ajuste ao volume normal das suas apps |

Contact points em `contact-points.yml`: um único contact point `equipe-ops` com receivers de e-mail, Slack, Discord, Telegram e webhook genérico, todos definidos mas usando placeholders seguros até você preencher `.env` (evita que a stack falhe ao subir por causa de URL vazia). Para habilitar:

1. Preencha as variáveis `ALERT_*` no `.env` com os valores reais.
2. Para e-mail, mude também `ALERT_SMTP_ENABLED=true`.
3. `docker compose up -d` (recria só o Grafana, os outros containers não são afetados).

**Importante se você for adicionar um novo canal/variável aqui**: `contact-points.yml` interpola `$ALERT_*` usando o ambiente do *processo do Grafana dentro do container*, não o `.env` do host diretamente. Isso só funciona porque cada `ALERT_*` também está listado no bloco `environment:` do serviço `grafana` no `docker-compose.yml` (com um default placeholder próprio, redundante com o do `.env.example` — dupla camada de segurança). Se uma variável nova existir só em `contact-points.yml` mas não estiver em `environment:` do Grafana, ela vira string vazia — e para o receiver de e-mail (`addresses`) isso não é "alerta desabilitado", é um **erro fatal de provisionamento que impede o Grafana de subir** (`could not find addresses in settings`). Ao adicionar uma variável de alerta nova, sempre atualize os dois arquivos juntos.

`notification-policies.yml` roteia tudo para `equipe-ops`, com um caminho mais rápido (menor `group_wait`/`repeat_interval`) para alertas `severity: critical`.

## 19. Backup

O que é persistido e onde:

| Serviço | Volume nomeado | Conteúdo |
|---|---|---|
| Grafana | `grafana_data` | `grafana.db` (dashboards salvos internamente, usuários, sessões), plugins instalados |
| Prometheus | `prometheus_data` | Blocos da TSDB (métricas) |
| Loki | `loki_data` | Chunks, índice TSDB, regras |

Esses volumes sobrevivem a `docker compose restart` e a `docker compose down && docker compose up -d` (só são apagados por `docker compose down -v`, que este projeto nunca chama automaticamente).

`scripts/backup.sh`:

```bash
./scripts/backup.sh
```

Gera `backups/observability-backup-<timestamp>.tar.gz` contendo: snapshot consistente da TSDB do Prometheus (via admin API, não um copy "a quente" do WAL), o diretório completo do Loki, o diretório completo do Grafana, e toda a configuração como código (`prometheus/`, `loki/`, `alloy/`, `grafana/provisioning`, `grafana/dashboards`, `docker-compose.yml`, `.env`). Não para nenhum container. Mantém os `BACKUP_KEEP` (padrão 7) backups mais recentes localmente — **copie os arquivos para fora da VPS** (outro host, S3, etc.) periodicamente; um backup que só existe na própria VPS não protege contra a perda dela. O arquivo gerado contém o `.env` (segredos) — trate-o com o mesmo cuidado.

## 20. Atualização

```bash
docker compose pull
docker compose up -d
```

Riscos antes de atualizar um componente crítico (Prometheus, Loki, Grafana):

1. Leia o changelog/release notes da versão de destino, especialmente breaking changes de schema (Loki) ou de storage (Prometheus TSDB).
2. Rode `./scripts/backup.sh` antes.
3. Atualize um serviço por vez quando possível (edite a tag da imagem no `docker-compose.yml`, não use `latest`) e valide com `scripts/healthcheck.sh` antes de seguir para o próximo.
4. Loki em particular: mudanças de `schema_config` não são retroativas — novos schemas só valem a partir de uma nova entrada com `from:` futura, nunca edite uma entrada de schema já em uso.

Se o [deploy automático via GitHub Actions](#23-deploy-automático-via-github-actions) estiver configurado, um `git push` na `main` já faz `pull` + `up -d` + healthcheck sozinho — os passos acima continuam valendo antes de fazer esse push (backup, ler release notes etc.), só o "aplicar" vira automático.

## 21. Segurança

- Prometheus, Loki, cAdvisor, Node Exporter e Alloy **não têm porta publicada** — só acessíveis dentro da rede Docker `monitoring`.
- Grafana é o único serviço exposto. Se for exposto diretamente à internet:
  - Troque `GRAFANA_ADMIN_PASSWORD` por uma senha forte (não deixe o placeholder do `.env.example`).
  - Coloque atrás de um **reverse proxy com HTTPS** (Caddy ou Nginx + Let's Encrypt) — não incluído neste repositório de propósito (fora do escopo desta stack, mas altamente recomendado); nesse cenário, o Grafana passa a escutar só em `127.0.0.1:${GRAFANA_PORT}` (ajuste o `ports:` do serviço `grafana` no `docker-compose.yml`) e o proxy termina o TLS.
  - Considere `fail2ban` monitorando os logs de autenticação do Grafana (já centralizados no Loki via Alloy!) para bloquear tentativas de força bruta.
  - Desative `GF_USERS_ALLOW_SIGN_UP` (já vem `false` por padrão aqui).
  - Mantenha as imagens atualizadas (ver seção 20).
- `--web.enable-admin-api` do Prometheus (necessário para `backup.sh`) é seguro aqui porque a porta 9090 nunca sai da rede interna — não replique essa flag se um dia publicar a porta do Prometheus.
- Nenhuma credencial vai para o Git: `.env` está no `.gitignore`, `.env.example` só tem placeholders.

**Firewall (UFW)**:

```bash
sudo ufw allow 22/tcp        # SSH — sempre necessário
sudo ufw allow 3000/tcp      # Grafana — só se for acessar direto por IP:porta
# Se usar reverse proxy com HTTPS em vez do acesso direto:
# sudo ufw allow 80/tcp
# sudo ufw allow 443/tcp
# sudo ufw delete allow 3000/tcp   # feche a porta direta do Grafana
sudo ufw enable
```

Não abra 9090 (Prometheus), 3100 (Loki), 8080 (cAdvisor), 9100 (Node Exporter) ou 12345 (Alloy) — eles não precisam e não devem ser alcançáveis de fora da VPS.

## 22. Troubleshooting

**Grafana sem datasource**
```bash
docker compose logs grafana | grep -i datasource
```
Confira se `grafana/provisioning/datasources/datasources.yml` foi montado (`docker compose exec grafana ls /etc/grafana/provisioning/datasources`).

**Prometheus não coleta cAdvisor**
Abra `http://<vps>:9090/targets` via túnel SSH (`ssh -L 9090:localhost:9090 usuario@vps`, já que a porta não é pública) ou `docker compose exec prometheus wget -qO- http://localhost:9090/api/v1/targets`. Depois `docker compose logs cadvisor` — geralmente é permissão de volume ou `privileged` (ver seção 14).

**Loki não recebe logs**
```bash
docker compose logs alloy
```
Confirme que `/var/run/docker.sock` está montado no Alloy e que `loki.write` aponta para `http://loki:3100`. Rode `scripts/healthcheck.sh` — ele testa uma query real no Loki.

**Dashboard sem dados**
Confira se o `uid` do datasource no JSON do painel bate com `prometheus`/`loki` (é assim que estão definidos em `datasources.yml`), se a query PromQL/LogQL está correta (teste em Explore) e se o intervalo de tempo do dashboard cobre um período com dados.

**Plugin HTML Graphics não instalado**
```bash
docker compose logs grafana | grep -i "plugin"
docker compose exec grafana grafana-cli plugins ls
```
Se não aparecer, confirme `GF_INSTALL_PLUGINS=gapit-htmlgraphics-panel` no `docker-compose.yml` e que o container tem acesso à internet para baixar o plugin no primeiro boot.

---

## 23. Deploy automático via GitHub Actions

`.github/workflows/deploy.yml` sincroniza este repositório com a VPS e sobe a stack automaticamente a cada `git push` na branch `main` (ou manualmente via **Actions → Deploy to VPS → Run workflow**).

O que o workflow faz, em ordem: valida a presença do `docker-compose.yml` → valida a sintaxe do compose (usando `.env.example` só para satisfazer as variáveis obrigatórias — esse arquivo temporário nunca sai do runner) → valida o JSON de todos os dashboards → configura SSH com `known_hosts` fixo (sem `StrictHostKeyChecking=no` — conexão só é aceita se a VPS já for uma máquina conhecida) → testa a conexão → `rsync` do repositório para a VPS (excluindo `.env`, logs, backups e diretórios de dados) → escreve o `.env` de produção na VPS a partir de um secret (`umask 077`, nunca passa pelo Git/rsync) → `docker compose config && docker compose pull && docker compose up -d --remove-orphans` → roda **`scripts/healthcheck.sh` na própria VPS** como verificação final → remove a chave SSH do runner ao final (`if: always()`, mesmo se algo falhar antes).

A última etapa reaproveita o `scripts/healthcheck.sh` deste repositório em vez de só rodar `docker compose ps` — assim, se algum serviço subir mas não ficar saudável (datasource quebrado, Loki não respondendo, target down no Prometheus), o job do GitHub Actions **falha de verdade**, em vez de aparecer verde com a stack degradada.

### Secrets necessários (Settings → Secrets and variables → Actions)

| Secret | Conteúdo |
|---|---|
| `VPS_HOST` | IP ou hostname da VPS |
| `VPS_PORT` | Porta do SSH (normalmente `22`) |
| `VPS_USER` | Usuário SSH de deploy (recomendado: um usuário dedicado, não root, no grupo `docker`) |
| `VPS_DEPLOY_PATH` | Caminho absoluto na VPS onde o repositório vai viver (ex.: `/opt/vps-observabilidade`) |
| `VPS_SSH_PRIVATE_KEY` | Chave privada SSH (par dedicado ao deploy, não sua chave pessoal) |
| `VPS_KNOWN_HOSTS` | Saída de `ssh-keyscan -p <porta> <host>` rodado a partir de uma máquina confiável |
| `PRODUCTION_ENV` | Conteúdo completo do `.env` de produção (mesmas chaves do `.env.example`, com valores reais) |

Gerando a chave dedicada e o `known_hosts`:

```bash
ssh-keygen -t ed25519 -f deploy_key -C "github-actions-deploy" -N ""
# cole o conteúdo de deploy_key.pub em ~/.ssh/authorized_keys do usuário de deploy na VPS
# cole o conteúdo de deploy_key (privada) no secret VPS_SSH_PRIVATE_KEY

ssh-keyscan -p 22 seu-ip-ou-host >> known_hosts_output
# cole o conteúdo de known_hosts_output no secret VPS_KNOWN_HOSTS
```

### Sobre o `--delete` do rsync

O `rsync` roda com `--delete`, ou seja, arquivos removidos do Git também somem da VPS no próximo deploy — isso é o que garante que a VPS reflita exatamente o repositório, mas é por isso que `.env`, `backups/`, `*.log` e os diretórios de dados estão explicitamente em `--exclude`. Como esta stack usa **volumes nomeados do Docker** (não bind mounts em `data/`, ver [seção 19](#19-backup)), o `--delete` não tem como atingir dados reais de Prometheus/Loki/Grafana — eles vivem fora da árvore sincronizada. Se você migrar para bind mounts no futuro, adicione o novo diretório à lista de `--exclude` antes de habilitar o workflow.

### Sobre o `.env` de produção

O `.env` nunca passa pelo Git nem pelo `rsync` (está em `--exclude`). Ele é escrito diretamente na VPS via SSH a partir do secret `PRODUCTION_ENV`, com `umask 077` (arquivo criado já com permissão `600`, ilegível para outros usuários). Isso mantém a regra de "nenhuma credencial no Git" mesmo com deploy automatizado.

---

## Adicionando novos serviços/exporters

1. Crie/edite um arquivo em `prometheus/targets/*.json` (modelo em `additional-targets.json.example`) — o Prometheus recarrega sozinho, sem restart.
2. Para uma métrica nova aparecer num dashboard, edite o JSON correspondente em `grafana/dashboards/` e reinicie o Grafana (ou aguarde o reload automático do provider).
3. Para um novo container/host de logs, nada a fazer manualmente: o Alloy já descobre qualquer container Docker novo automaticamente via `discovery.docker`.
