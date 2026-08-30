# Prompt — Implementação Completa de Observabilidade em VPS Ubuntu 24.04

Atue como um **Engenheiro DevOps/SRE especialista em observabilidade, Docker, Docker Compose, Grafana, Prometheus, Loki e infraestrutura Linux**.

Tenho uma **VPS rodando Ubuntu 24.04** e quero implementar uma solução completa de **monitoramento, métricas, logs e observabilidade**, utilizando Docker.

O objetivo é construir uma infraestrutura **100% declarativa, automatizada, versionável e reproduzível**, evitando ao máximo qualquer configuração manual através das interfaces web.

---

# 1. Objetivo da solução

Preciso criar uma stack de observabilidade para monitorar minha VPS e todos os containers Docker executados nela.

A stack deverá contemplar:

* **Grafana** — visualização e dashboards;
* **Prometheus** — coleta e armazenamento de métricas;
* **Loki** — armazenamento e consulta de logs;
* **Promtail ou alternativa atualmente recomendada** — coleta e envio de logs;
* **Node Exporter** — métricas do host/VPS;
* **cAdvisor** — métricas dos containers Docker;
* Outros exporters/componentes que sejam tecnicamente necessários.

Toda a infraestrutura deverá ser executada utilizando:

* Docker;
* Docker Compose;
* arquivos YAML/JSON/configuração;
* Grafana Provisioning;
* dashboards versionados;
* configuração como código.

A solução deve ser adequada para produção, mas sem introduzir complexidade desnecessária para uma única VPS.

---

# 2. Regra importante sobre versões e tecnologias

Antes de implementar a solução, **avalie o estado atual das tecnologias escolhidas**.

Não utilize configurações antigas simplesmente porque são comuns em tutoriais.

Verifique especialmente:

* Grafana;
* Prometheus;
* Loki;
* Promtail;
* cAdvisor;
* Node Exporter;
* Docker Compose;
* plugins do Grafana.

Caso alguma tecnologia esteja:

* deprecated;
* em manutenção limitada;
* substituída por outra;
* descontinuada;
* incompatível com versões atuais;

apresente a alternativa recomendada.

### Atenção especial ao Promtail

Avalie se o Promtail continua sendo a melhor opção para a versão atual do Loki/Grafana.

Se existir uma alternativa oficialmente recomendada para coleta de logs, como **Grafana Alloy**, explique a diferença entre:

```text
Promtail
```

e

```text
Grafana Alloy
```

e escolha a alternativa tecnicamente mais adequada.

Caso eu tenha solicitado explicitamente Promtail, você pode mantê-lo se houver uma justificativa de compatibilidade, mas deve deixar claro o impacto dessa decisão.

---

# 3. Arquitetura esperada

A arquitetura deverá seguir aproximadamente este modelo:

```text
                         INTERNET
                            │
                            │
                     ┌──────▼──────┐
                     │   Grafana   │
                     │   :3000     │
                     └──────┬──────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
       ┌──────▼──────┐             ┌──────▼──────┐
       │  Prometheus │             │     Loki     │
       │    :9090    │             │    :3100     │
       └──────┬──────┘             └──────▲──────┘
              │                           │
      ┌───────┼──────────────┐            │
      │       │              │            │
 ┌────▼───┐ ┌─▼──────────┐ ┌─▼────────┐  │
 │ Node   │ │  cAdvisor  │ │ Prometheus│ │
 │Exporter│ │            │ │  targets  │ │
 └────┬───┘ └────┬───────┘ └──────────┘  │
      │           │                        │
      └───────────┴────────────────────────┘
                  VPS
          Ubuntu 24.04 + Docker
                  │
          ┌───────┴────────┐
          │ Docker         │
          │ Containers     │
          └────────────────┘
                  │
          ┌───────▼────────┐
          │ Log Collector  │
          │ Promtail/Alloy │
          └───────┬────────┘
                  │
                  ▼
                Loki
```

A arquitetura pode ser modificada caso exista uma abordagem melhor.

Explique as decisões arquiteturais.

---

# 4. Estrutura de diretórios

Crie uma estrutura organizada, profissional e preparada para versionamento Git.

Utilize algo semelhante a:

```text
monitoring/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── README.md
│
├── prometheus/
│   ├── prometheus.yml
│   └── rules/
│       ├── system.yml
│       └── docker.yml
│
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── datasources.yml
│   │   ├── dashboards/
│   │   │   └── dashboards.yml
│   │   └── plugins/
│   │
│   ├── dashboards/
│   │   ├── infrastructure-overview.json
│   │   ├── host-metrics.json
│   │   ├── docker-containers.json
│   │   └── logs-overview.json
│   │
│   └── config/
│
├── loki/
│   └── loki-config.yml
│
├── promtail/
│   └── promtail-config.yml
│
├── alloy/
│   └── config.alloy
│
└── scripts/
    ├── install.sh
    ├── backup.sh
    └── healthcheck.sh
```

Não é obrigatório seguir exatamente essa estrutura.

Caso exista uma organização melhor, utilize-a e explique o motivo.

Não crie arquivos desnecessários apenas para aumentar a quantidade de arquivos.

---

# 5. Docker Compose

Crie um `docker-compose.yml` completo.

A stack deverá ser iniciada com:

```bash
docker compose up -d
```

E parada com:

```bash
docker compose down
```

Também deve funcionar:

```bash
docker compose ps
```

e:

```bash
docker compose logs -f
```

Configure corretamente:

* networks;
* volumes;
* restart policies;
* healthchecks quando apropriado;
* dependências;
* timezone;
* environment variables;
* limites de recursos quando fizer sentido;
* versões das imagens.

Evite utilizar `latest`.

Prefira versões estáveis e compatíveis entre si.

Explique as versões escolhidas.

---

# 6. Rede Docker

Crie uma rede Docker dedicada para a stack.

Por exemplo:

```text
monitoring
```

Os componentes internos devem se comunicar através dessa rede.

Evite publicar portas internas desnecessariamente.

Por exemplo, serviços como:

```text
Prometheus
Loki
cAdvisor
Node Exporter
Promtail/Alloy
```

não devem ficar diretamente acessíveis pela internet.

O Grafana será o principal ponto de acesso externo.

Explique quais portas serão expostas e por quê.

---

# 7. Persistência

Configure volumes persistentes para todos os componentes que armazenam dados.

No mínimo:

```text
Prometheus → dados de métricas
Grafana    → banco/configurações
Loki       → logs
```

Os dados devem sobreviver a:

```bash
docker compose restart
```

e:

```bash
docker compose down
docker compose up -d
```

Explique o que é persistido e onde fica armazenado no host.

Também explique como realizar backup desses dados.

---

# 8. Prometheus

Configure o Prometheus utilizando arquivo:

```text
prometheus/prometheus.yml
```

O Prometheus deverá coletar métricas de:

* próprio Prometheus;
* Node Exporter;
* cAdvisor;
* outros exporters relevantes.

A configuração deverá estar preparada para adicionar futuramente:

* outras VPS;
* aplicações;
* APIs;
* serviços;
* endpoints HTTP;
* exporters adicionais.

Estruture os targets de maneira organizada.

---

# 9. Node Exporter

Inclua o **Node Exporter** para monitorar o sistema operacional da VPS.

O Node Exporter deverá coletar métricas como:

### CPU

* utilização;
* idle;
* system;
* user;
* iowait;
* load.

### Memória

* RAM total;
* RAM utilizada;
* RAM disponível;
* cache;
* buffers;
* swap.

### Disco

* espaço utilizado;
* espaço disponível;
* percentual de utilização;
* I/O;
* read/write.

### Filesystem

Monitorar os principais filesystems da VPS.

### Rede

* tráfego recebido;
* tráfego enviado;
* erros;
* packets;
* interfaces.

### Sistema

* uptime;
* load average;
* processos;
* contexto;
* temperatura, quando disponível.

Crie dashboards apropriados para essas métricas.

---

# 10. cAdvisor

Inclua o **cAdvisor** na stack.

O objetivo é monitorar os containers Docker individualmente.

O cAdvisor deverá fornecer métricas como:

* CPU por container;
* percentual de CPU;
* memória por container;
* working set;
* cache;
* limite de memória;
* network receive;
* network transmit;
* filesystem;
* disk I/O;
* containers ativos;
* containers existentes;
* outras métricas relevantes.

O Prometheus deverá realizar scrape das métricas do cAdvisor.

O cAdvisor não deve ser exposto publicamente.

Explique todos os volumes necessários no container do cAdvisor, especialmente aqueles relacionados a:

* `/sys`;
* `/var/run`;
* `/var/lib/docker`;
* filesystem do host;

ou equivalentes necessários para a versão escolhida.

Não copie volumes de configurações antigas sem verificar se são necessários na versão atual.

---

# 11. Monitoramento dos containers

Crie um dashboard específico:

```text
Docker / Containers
```

Esse dashboard deverá permitir identificar rapidamente os containers que mais consomem recursos.

Inclua:

### Overview

* número total de containers;
* containers ativos;
* containers parados;
* CPU total;
* memória total;
* network I/O;
* disk I/O.

### CPU

* CPU por container;
* Top 10 containers por CPU;
* CPU ao longo do tempo.

### Memória

* memória por container;
* Top 10 containers por memória;
* percentual de utilização;
* memória utilizada versus limite.

### Network

* download por container;
* upload por container;
* throughput;
* Top containers por tráfego.

### Disk

* leitura;
* escrita;
* I/O;
* containers com maior utilização.

Utilize variáveis do Grafana para:

* container;
* imagem;
* hostname;
* serviço, quando aplicável.

---

# 12. Loki

Configure o **Loki** como backend de logs.

O Loki deve ser configurado para funcionar de forma adequada em uma única VPS.

Avalie:

* armazenamento;
* retenção;
* compactor;
* filesystem/object storage;
* limites;
* cache;
* schema;
* performance.

Não utilize uma configuração de produção distribuída desnecessariamente complexa para uma única VPS.

Prefira uma configuração simples e robusta.

Explique as decisões.

---

# 13. Coleta de logs

Preciso coletar logs de:

* sistema operacional;
* Docker;
* containers;
* serviços relevantes.

Avalie o uso de:

```text
Promtail
```

versus:

```text
Grafana Alloy
```

e utilize a alternativa mais adequada para as versões atuais.

A solução deve permitir identificar:

* hostname;
* container;
* serviço;
* imagem;
* nível de log;
* timestamp.

Os logs dos containers devem ser coletados sem alterar desnecessariamente o funcionamento das aplicações.

---

# 14. Dashboard de Logs

Crie um dashboard:

```text
Logs Overview
```

Utilizando Loki.

Ele deverá permitir:

* pesquisar logs;
* filtrar por container;
* filtrar por serviço;
* filtrar por hostname;
* filtrar por nível;
* visualizar volume de logs;
* visualizar logs ao longo do tempo;
* pesquisar mensagens;
* identificar erros.

Crie variáveis do Grafana quando apropriado.

---

# 15. Grafana

O Grafana deve ser configurado completamente via código.

Não quero depender de configuração manual através da interface web.

Automatize:

* datasources;
* dashboards;
* folders;
* plugins;
* configurações relevantes.

Utilize o sistema de **Provisioning do Grafana**.

---

# 16. Datasources

Configure automaticamente pelo menos:

```text
Prometheus
Loki
```

O Prometheus será utilizado para:

```text
Métricas
```

e Loki para:

```text
Logs
```

Os datasources devem estar disponíveis automaticamente após:

```bash
docker compose up -d
```

Não quero precisar acessar:

```text
Grafana → Connections → Data Sources
```

para configurar manualmente.

---

# 17. Dashboards via JSON

Todos os dashboards devem existir como arquivos:

```text
*.json
```

e ser versionados pelo Git.

O Grafana deverá importá-los automaticamente através de provisioning.

Não quero criar dashboards manualmente pela interface.

Os dashboards devem possuir:

* títulos;
* descrições;
* tags;
* variáveis;
* queries PromQL;
* queries LogQL;
* unidades corretas;
* thresholds;
* intervalos adequados;
* legendas;
* painéis organizados.

Evite IDs ou referências quebradas.

Não utilize dashboards exportados de terceiros sem revisar as queries e dependências.

---

# 18. Dashboard principal — Infrastructure Overview

Crie um dashboard principal chamado:

```text
Infrastructure Overview
```

Esse deve ser o dashboard inicial da stack.

Ele deverá apresentar uma visão geral da saúde da VPS.

Inclua cards para:

```text
CPU
RAM
Swap
Disk
Network
Load
Uptime
Containers
```

Também inclua:

* CPU ao longo do tempo;
* memória ao longo do tempo;
* disco;
* network;
* containers com maior consumo;
* status geral.

Deve ser possível identificar rapidamente:

> "Minha VPS está saudável ou existe algum problema?"

---

# 19. Dashboard Host Metrics

Crie um dashboard:

```text
Host Metrics
```

com informações detalhadas do Node Exporter.

Inclua:

* CPU;
* load average;
* RAM;
* swap;
* disk usage;
* disk I/O;
* filesystem;
* network;
* uptime;
* processos.

Use unidades corretas:

```text
bytes
bytes/sec
percent
seconds
cores
```

Evite apresentar bytes como números sem unidade.

---

# 20. Dashboard Docker

Crie:

```text
Docker / Containers
```

Utilizando cAdvisor.

O dashboard deve permitir selecionar:

```text
Container
Image
Hostname
```

e visualizar detalhadamente o consumo dos containers.

---

# 21. Dashboard Logs

Crie:

```text
Logs Overview
```

Utilizando Loki.

Inclua:

* volume de logs;
* erros;
* warnings;
* logs recentes;
* pesquisa textual;
* filtros.

Sempre que possível, permita navegar de métricas para logs.

Por exemplo:

```text
Container com CPU alta
        ↓
Selecionar container
        ↓
Visualizar logs daquele container
```

---

# 22. HTML Graphics

Preciso utilizar o plugin:

```text
html-graphics
```

no Grafana.

A instalação do plugin deve ser **100% automatizada**.

Não quero instalar o plugin manualmente pela interface.

Utilize o mecanismo apropriado do Grafana para instalar plugins no container.

Verifique a compatibilidade da versão do plugin com a versão do Grafana escolhida.

---

# 23. Uso do HTML Graphics

Utilize o HTML Graphics para melhorar visualmente os dashboards quando isso fizer sentido.

Crie componentes como:

* cards personalizados;
* status da VPS;
* indicadores de CPU;
* indicadores de memória;
* indicadores de disco;
* indicadores de containers;
* cabeçalho;
* health status;
* indicadores visuais.

Por exemplo:

```text
┌───────────────────────────────────────────────┐
│              VPS STATUS                       │
│                                               │
│  CPU       RAM       DISK       CONTAINERS    │
│  18%       42%       61%          12          │
│                                               │
│              ● HEALTHY                        │
└───────────────────────────────────────────────┘
```

O HTML/CSS/JavaScript deve ser armazenado dentro dos dashboards JSON para continuar sendo versionável.

Não dependa de arquivos externos desnecessários.

Evite utilizar HTML Graphics quando um painel nativo do Grafana resolver o problema de forma mais simples.

---

# 24. Alertas

Implemente uma estrutura preparada para alertas.

Crie regras para situações como:

### CPU

```text
CPU persistentemente acima de determinado limite
```

### Memória

```text
Memória disponível muito baixa
```

### Disco

```text
Filesystem acima de 80%
Filesystem acima de 90%
```

### Containers

```text
Container indisponível
Container reiniciando excessivamente
```

### Sistema

```text
Host down
```

### Logs

Quando tecnicamente viável:

```text
aumento anormal de erros
```

As regras devem evitar falsos positivos.

Não configure thresholds arbitrários sem explicar o motivo.

Estruture as alertas para que possam futuramente enviar notificações para:

* e-mail;
* Slack;
* Discord;
* Telegram;
* webhook.

Não é necessário configurar todos esses canais agora, mas deixe a estrutura preparada.

---

# 25. Recording Rules

Avalie a utilização de Prometheus Recording Rules para queries utilizadas frequentemente nos dashboards.

Se isso melhorar:

* performance;
* legibilidade;
* manutenção;

crie arquivos como:

```text
prometheus/rules/
```

com regras organizadas.

Não crie recording rules desnecessariamente.

---

# 26. Segurança

A solução deve seguir boas práticas de segurança.

Não exponha publicamente:

```text
Prometheus :9090
Loki       :3100
cAdvisor   :8080
Node Exporter :9100
Promtail/Alloy
```

Esses serviços devem utilizar a rede interna do Docker sempre que possível.

O Grafana será o principal serviço externo.

Se o Grafana for exposto diretamente na internet, recomende boas práticas como:

* senha administrativa forte;
* HTTPS;
* reverse proxy;
* firewall;
* fail2ban ou alternativa, quando aplicável;
* desativação de recursos desnecessários;
* atualização regular.

Não coloque credenciais diretamente no Git.

Utilize:

```text
.env
```

ou mecanismo mais seguro quando apropriado.

Crie:

```text
.env.example
```

sem credenciais reais.

---

# 27. Firewall

Considere que a VPS pode utilizar:

```text
UFW
```

Explique quais portas precisam estar abertas.

Por exemplo:

```text
22   → SSH
80   → HTTP, se necessário
443  → HTTPS, se necessário
3000 → Grafana, caso seja exposto diretamente
```

Não abra portas internas sem necessidade.

Se recomendar reverse proxy, explique a arquitetura.

---

# 28. Healthchecks

Configure healthchecks para os serviços onde fizer sentido.

O objetivo é conseguir identificar:

```text
container running
```

versus:

```text
service actually healthy
```

Não adicione healthchecks frágeis ou dependentes de ferramentas que não existem dentro das imagens.

---

# 29. Resource limits

Avalie o consumo da própria stack.

A solução não pode consumir uma quantidade desnecessária de recursos da VPS.

Considere:

* retenção do Prometheus;
* retenção do Loki;
* tamanho dos logs;
* frequência de scrape;
* cardinalidade;
* quantidade de dashboards;
* quantidade de containers.

Explique como ajustar a configuração caso a VPS tenha poucos recursos.

---

# 30. Retenção

Configure políticas de retenção adequadas.

Defina claramente:

```text
Prometheus → X dias
Loki       → X dias
```

Escolha valores razoáveis para uma VPS.

Explique como alterar posteriormente.

Não configure retenção ilimitada.

---

# 31. Performance

Tenha cuidado com:

* alta cardinalidade;
* labels dinâmicos no Loki;
* scrape intervals muito agressivos;
* dashboards com queries excessivamente pesadas;
* LogQL custosa;
* PromQL ineficiente.

Para Loki, evite transformar valores altamente dinâmicos em labels.

Explique quais labels serão utilizados e por quê.

---

# 32. Timezone

Permita configurar timezone através do `.env`.

Por exemplo:

```text
TZ=America/Sao_Paulo
```

Não assuma UTC sem explicar.

A configuração deve ser consistente entre:

* Docker;
* Grafana;
* Loki;
* Prometheus;
* containers auxiliares.

---

# 33. Versionamento Git

A estrutura deverá ser preparada para Git.

Crie um:

```text
.gitignore
```

ignorando pelo menos:

```text
.env
*.log
dados persistentes
secrets
backups
```

Não coloque dados persistentes do Grafana/Prometheus/Loki no Git.

Os dashboards JSON, YAML e arquivos de configuração devem ser versionados.

---

# 34. Backup

Crie documentação explicando como fazer backup de:

* Grafana;
* Prometheus;
* Loki;
* dashboards;
* configurações.

Se fizer sentido, crie:

```text
scripts/backup.sh
```

O script deve ser simples e seguro.

Explique também o que realmente precisa ser backupado.

---

# 35. Atualizações

Documente como atualizar a stack.

Por exemplo:

```bash
docker compose pull
docker compose up -d
```

Mas explique os riscos de atualização.

Antes de atualizar componentes críticos:

* verificar release notes;
* verificar breaking changes;
* fazer backup;
* validar compatibilidade.

---

# 36. Troubleshooting

O README deve possuir uma seção de troubleshooting.

Inclua problemas como:

### Grafana sem datasource

Verificar:

```bash
docker compose logs grafana
```

### Prometheus não coleta cAdvisor

Verificar:

```text
Prometheus → Status → Targets
```

e logs do container.

### Loki não recebe logs

Verificar:

* collector;
* configuração;
* permissões;
* labels;
* rede Docker.

### Dashboard sem dados

Verificar:

* datasource UID;
* PromQL;
* LogQL;
* targets;
* intervalo de tempo.

### Plugin HTML Graphics não instalado

Verificar:

```bash
docker compose logs grafana
```

e a lista de plugins instalados.

---

# 37. README

Crie um `README.md` completo contendo:

1. Visão geral;
2. Arquitetura;
3. Pré-requisitos;
4. Instalação do Docker;
5. Estrutura de diretórios;
6. Configuração do `.env`;
7. Inicialização;
8. Acesso ao Grafana;
9. Datasources;
10. Dashboards;
11. Plugins;
12. Prometheus;
13. Node Exporter;
14. cAdvisor;
15. Loki;
16. Promtail/Alloy;
17. Logs;
18. Alertas;
19. Backup;
20. Atualização;
21. Segurança;
22. Troubleshooting.

Inclua os comandos necessários.

---

# 38. Instalação inicial

Crie, se fizer sentido, um:

```text
scripts/install.sh
```

que possa:

1. verificar o Ubuntu;
2. verificar Docker;
3. verificar Docker Compose;
4. criar diretórios necessários;
5. validar `.env`;
6. validar configurações;
7. iniciar a stack;
8. verificar o status dos serviços.

O script deve ser idempotente.

Não execute comandos destrutivos sem confirmação.

---

# 39. Validação

Antes de considerar a implementação concluída, valide:

### Docker

```bash
docker compose config
```

### Containers

```bash
docker compose ps
```

### Logs

```bash
docker compose logs
```

### Prometheus

Verificar se os targets estão UP.

### Grafana

Verificar:

* datasource;
* dashboards;
* plugin.

### Loki

Verificar se está recebendo logs.

### cAdvisor

Verificar se está expondo métricas.

### Node Exporter

Verificar se está expondo métricas.

---

# 40. Critérios de aceitação

Considere a solução concluída somente se:

* [ ] Docker Compose funciona;
* [ ] todos os containers iniciam corretamente;
* [ ] volumes persistentes estão configurados;
* [ ] Prometheus está funcionando;
* [ ] Node Exporter está funcionando;
* [ ] cAdvisor está funcionando;
* [ ] Loki está funcionando;
* [ ] Promtail/Alloy está funcionando;
* [ ] Grafana está funcionando;
* [ ] Prometheus está provisionado automaticamente;
* [ ] Loki está provisionado automaticamente;
* [ ] dashboards são importados automaticamente;
* [ ] dashboards estão em JSON;
* [ ] HTML Graphics está instalado automaticamente;
* [ ] métricas do host aparecem;
* [ ] métricas dos containers aparecem;
* [ ] logs aparecem no Loki;
* [ ] filtros dos dashboards funcionam;
* [ ] alertas estão preparados/configurados;
* [ ] nenhum serviço interno está desnecessariamente exposto à internet;
* [ ] `.env` não contém credenciais reais no repositório;
* [ ] README explica toda a operação.

---

# 41. Formato da resposta

Quero que você entregue a solução completa.

Não quero apenas uma explicação conceitual.

Para cada arquivo criado, apresente:

```text
CAMINHO:
monitoring/docker-compose.yml
```

seguido pelo conteúdo completo:

```yaml
...
```

Faça isso para todos os arquivos necessários.

Ao final, apresente a árvore completa:

```text
monitoring/
├── ...
└── ...
```

Depois explique:

1. Como instalar;
2. Como iniciar;
3. Como acessar;
4. Como validar;
5. Como verificar os dashboards;
6. Como verificar métricas;
7. Como verificar logs;
8. Como atualizar;
9. Como fazer backup;
10. Como adicionar novos serviços/exporters.

---

# 42. Regras importantes para a implementação

Siga estas regras durante toda a implementação:

### Regra 1 — Infrastructure as Code

Não dependa de configuração manual.

Tudo que puder ser configurado via arquivo deve ser configurado via arquivo.

### Regra 2 — Idempotência

Executar novamente a instalação não deve quebrar a infraestrutura.

### Regra 3 — Segurança

Não exponha serviços internos desnecessariamente.

### Regra 4 — Versionamento

Não utilize:

```text
latest
```

sem uma justificativa clara.

### Regra 5 — Compatibilidade

Verifique a compatibilidade entre:

```text
Grafana
Prometheus
Loki
Promtail/Alloy
Node Exporter
cAdvisor
HTML Graphics
Docker
Ubuntu 24.04
```

### Regra 6 — Simplicidade

É uma única VPS.

Não crie uma arquitetura distribuída ou excessivamente complexa sem necessidade.

### Regra 7 — Dashboards

Os dashboards precisam ser:

```text
JSON
↓
Git
↓
Grafana Provisioning
↓
Importação automática
```

### Regra 8 — Plugins

Plugins devem ser instalados automaticamente.

### Regra 9 — Logs

Não utilize labels de alta cardinalidade desnecessariamente no Loki.

### Regra 10 — Produção

A solução deve ser suficientemente robusta para uso real, não apenas um exemplo/tutorial.

---

# 43. Resultado esperado

Ao finalizar, quero ter uma estrutura semelhante a:

```text
                    ┌───────────────────────────┐
                    │          Grafana          │
                    │                           │
                    │  Infrastructure Overview  │
                    │  Host Metrics             │
                    │  Docker / Containers      │
                    │  Logs Overview             │
                    └─────────────┬─────────────┘
                                  │
                   ┌──────────────┴──────────────┐
                   │                             │
             ┌─────▼─────┐                 ┌─────▼─────┐
             │ Prometheus│                 │    Loki    │
             └─────┬─────┘                 └─────▲─────┘
                   │                             │
          ┌────────┼────────┐                    │
          │                 │                    │
    ┌─────▼─────┐     ┌─────▼─────┐       ┌─────┴─────┐
    │   Node    │     │  cAdvisor │       │ Promtail/ │
    │  Exporter │     │            │       │   Alloy   │
    └─────┬─────┘     └─────┬─────┘       └───────────┘
          │                 │
          └────────┬────────┘
                   │
            ┌──────▼──────┐
            │ Ubuntu VPS  │
            │             │
            │   Docker    │
            │             │
            │ Containers  │
            └─────────────┘
```

A experiência final deve ser:

```text
git clone ...
        ↓
cd monitoring
        ↓
cp .env.example .env
        ↓
editar configurações
        ↓
docker compose up -d
        ↓
        ┌──────────────────────────┐
        │      Stack funcionando   │
        │                          │
        │ ✓ Prometheus             │
        │ ✓ Grafana                │
        │ ✓ Loki                   │
        │ ✓ Node Exporter          │
        │ ✓ cAdvisor               │
        │ ✓ Promtail/Alloy         │
        │ ✓ HTML Graphics          │
        │ ✓ Datasources             │
        │ ✓ Dashboards JSON         │
        │ ✓ Provisioning            │
        └──────────────────────────┘
```

O objetivo final é que eu possa subir essa estrutura em uma **VPS Ubuntu 24.04**, executar o Docker Compose e obter uma plataforma completa de observabilidade sem precisar configurar manualmente os dashboards, datasources ou plugins através da interface do Grafana.

**Priorize sempre segurança, compatibilidade, simplicidade, manutenção, automação, idempotência e boas práticas de produção.**
