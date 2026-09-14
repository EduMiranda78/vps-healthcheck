<div align="center">

# VPS Healthcheck

### Auditoria, diagnóstico e inventário para servidores Linux

Ferramenta modular em Bash para coletar o estado operacional de uma VPS, classificar riscos e gerar relatórios reutilizáveis em terminal, TXT, JSON e HTML.

[![Linux](https://img.shields.io/badge/Linux-supported-111111?logo=linux&logoColor=white)](https://www.kernel.org/)
[![Bash](https://img.shields.io/badge/Bash-4.4%2B-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/version-0.1.1-f4b740)](https://github.com/EduMiranda78/vps-healthcheck)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%2B-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Debian](https://img.shields.io/badge/Debian-12%2B-A81D33?logo=debian&logoColor=white)](https://www.debian.org/)

**[Instalação](#instalação) · [Uso rápido](#uso-rápido) · [Módulos](#módulos-da-versão-atual) · [Relatórios](#formatos-de-saída) · [Arquitetura](#arquitetura)**

</div>

---

## Visão geral

Administrar uma VPS normalmente exige consultar comandos, arquivos de configuração e serviços diferentes. O **VPS Healthcheck** reúne esse processo em uma única ferramenta, com execução rápida ou completa, módulos independentes, limites configuráveis e múltiplos formatos de saída.

Ele foi projetado para responder, de forma estruturada, perguntas como:

- Qual é o estado atual do servidor?
- Há pressão de CPU, memória, disco ou swap?
- Existem serviços com falha?
- Quais portas estão abertas e quais processos estão escutando?
- Há atualizações ou reinicializações pendentes?
- Quais pontos exigem atenção imediata?
- Como registrar o estado da VPS antes e depois de uma manutenção?

> **Perfil do projeto:** coleta segura, diagnóstico objetivo e documentação reutilizável. A ferramenta não aplica correções automaticamente.

---

## Destaques

| Recurso | O que entrega |
|---|---|
| Auditoria rápida ou completa | Coleta adaptável ao contexto da manutenção |
| Execução modular | Permite rodar somente os módulos necessários |
| Classificação de saúde | Estados `OK`, `WARNING`, `CRITICAL`, `UNKNOWN` e `SKIPPED` |
| Thresholds configuráveis | Limites adaptáveis ao perfil de cada servidor |
| Múltiplas saídas | Terminal, TXT, JSON e HTML |
| Automação | Execução não interativa e códigos de saída específicos |
| Privacidade | Controles para reduzir exposição de dados sensíveis |
| Self-test | Validação interna da instalação e dependências |

---

## Principais recursos

- auditoria rápida ou completa;
- execução por módulo individual;
- arquitetura Bash modular;
- classificação de saúde por status;
- limites de alerta configuráveis;
- relatórios em terminal, TXT, JSON e HTML;
- logs por execução;
- diretório exclusivo para cada coleta;
- suporte a execução não interativa;
- opção de execução sem `sudo`;
- proteção contra exposição acidental de dados sensíveis;
- códigos de saída específicos para automação;
- instalador com backup da versão anterior;
- validação interna com `--self-test`;
- suíte própria de testes em Bash.

---

## Módulos da versão atual

### Núcleo operacional

| Módulo | Função principal |
|---|---|
| **Sistema** | distribuição, kernel, arquitetura, hostname, uptime, horário e virtualização |
| **CPU** | modelo, núcleos, carga, uso, frequência, processos e temperatura quando disponível |
| **Memória** | memória total, disponível, utilizada, cache, swap e processos consumidores |
| **Disco** | sistemas de arquivos, inodes, dispositivos, montagens, diretórios e arquivos relevantes |
| **Rede** | interfaces, endereços, gateway, DNS, rotas, portas e conexões |
| **Serviços** | unidades `systemd`, serviços em execução, falhas, timers e sockets |
| **Atualizações** | pacotes disponíveis, atualizações de segurança e reinicialização pendente |

### Expansão modular

A arquitetura também prevê módulos especializados para:

`Python` · `Docker` · `Nginx` · `SSL` · `Bancos de dados` · `Firewall` · `Segurança` · `Logs` · `Serviços de IA` · `Ollama`

Módulos opcionais podem ser ignorados sem interromper os módulos obrigatórios.

---

## Status de saúde

Os dados coletados são classificados em estados operacionais:

| Status | Significado |
|---|---|
| `OK` | funcionamento dentro dos limites definidos |
| `WARNING` | condição que merece atenção |
| `CRITICAL` | condição que exige ação prioritária |
| `UNKNOWN` | dado insuficiente para classificação |
| `SKIPPED` | módulo ignorado ou indisponível |

Os limites podem ser alterados em `config/thresholds.conf`.

Exemplos de critérios configuráveis:

- percentual de CPU;
- utilização de memória e swap;
- ocupação de disco e inodes;
- quantidade de falhas ou eventos;
- tempo de uptime;
- limites operacionais específicos por módulo.

---

## Formatos de saída

| Formato | Uso indicado |
|---|---|
| **Terminal** | inspeção imediata durante suporte ou manutenção |
| **TXT** | registro simples, anexos e documentação técnica |
| **JSON** | integrações, automações e processamento por outras ferramentas |
| **HTML** | relatório visual para consulta, apresentação ou arquivo |

Por padrão, a ferramenta utiliza terminal e TXT. JSON e HTML podem ser ativados por argumento ou configuração.

---

## Instalação

### Requisitos

- Linux;
- Bash 4.4 ou superior;
- acesso administrativo para instalação global;
- `apt-get` em instalações automáticas baseadas em Debian ou Ubuntu.

### Instalação global

```bash
git clone https://github.com/EduMiranda78/vps-healthcheck.git
cd vps-healthcheck
chmod +x install.sh healthcheck.sh
sudo ./install.sh
```

O instalador:

1. valida a estrutura do projeto;
2. instala dependências básicas;
3. cria backup de uma instalação anterior;
4. copia o projeto para `/opt/vps-healthcheck`;
5. cria o comando global `/usr/local/bin/vps-healthcheck`;
6. aplica permissões;
7. executa o self-test.

Depois da instalação:

```bash
vps-healthcheck --version
vps-healthcheck --self-test
```

### Execução sem instalação

```bash
chmod +x healthcheck.sh
./healthcheck.sh --quick
```

---

## Uso rápido

### Auditoria rápida

```bash
vps-healthcheck --quick
```

### Auditoria completa

```bash
vps-healthcheck --full --html
```

### Relatórios JSON e HTML

```bash
vps-healthcheck --full --json --html
```

### Módulos específicos

```bash
vps-healthcheck --modules system,cpu,memory,disk
```

### Saída personalizada

```bash
vps-healthcheck \
  --full \
  --json \
  --html \
  --output-dir /var/reports/vps-healthcheck
```

### Execução para automação

```bash
vps-healthcheck \
  --quick \
  --json \
  --no-terminal \
  --non-interactive
```

---

## Opções principais

```text
--quick                 Auditoria rápida
--full                  Auditoria completa
--module NOME           Executa um módulo
--modules A,B,C         Executa uma lista de módulos

--terminal              Saída no terminal
--no-terminal           Desativa a saída detalhada no terminal
--txt                   Relatório TXT
--json                  Relatório JSON
--html                  Relatório HTML

--config ARQUIVO        Configuração principal
--thresholds ARQUIVO    Limites de saúde
--output-dir DIRETÓRIO  Diretório de relatórios
--no-sudo               Não utiliza sudo
--non-interactive       Não solicita interação

--verbose               Saída detalhada
--quiet                 Somente mensagens essenciais
--list-modules          Lista os módulos
--self-test             Valida a instalação
--version               Exibe a versão
--help                  Exibe a ajuda
```

---

## Configuração

O comportamento padrão é controlado por:

```text
config/healthcheck.conf
config/thresholds.conf
```

### `healthcheck.conf`

Controla modo de execução, formatos de saída, diretórios de relatórios e logs, uso de `sudo`, módulos habilitados, timeouts, privacidade e comportamento diante de falhas.

### `thresholds.conf`

Centraliza os limites usados para classificar métricas e alertas como `OK`, `WARNING` ou `CRITICAL`.

Também é possível fornecer arquivos alternativos:

```bash
vps-healthcheck \
  --quick \
  --config /etc/vps-healthcheck/healthcheck.conf \
  --thresholds /etc/vps-healthcheck/thresholds.conf
```

---

## Privacidade e segurança

O projeto inclui controles para reduzir exposição indevida em relatórios:

- redação de segredos habilitada por padrão;
- ambiente de processos não incluído por padrão;
- valores sensíveis de configurações não incluídos por padrão;
- opções para ocultar IPs, hostname, usuários e domínios;
- permissões restritivas para relatórios e logs;
- execução limitada à coleta e diagnóstico, sem aplicar correções automaticamente.

> Antes de compartilhar um relatório externamente, revise o conteúdo e ajuste as opções de redação ao ambiente.

---

## Estrutura do projeto

```text
vps-healthcheck/
├── healthcheck.sh              # CLI e orquestração
├── install.sh                  # instalação global
├── VERSION                     # versão do projeto
├── config/
│   ├── healthcheck.conf        # comportamento geral
│   └── thresholds.conf         # limites de saúde
├── lib/
│   ├── constants.sh            # constantes e status
│   ├── config.sh               # carregamento de configuração
│   ├── dependencies.sh         # dependências
│   ├── collector.sh            # armazenamento das métricas
│   ├── logger.sh               # logs
│   ├── utils.sh                # funções auxiliares
│   ├── report_txt.sh           # relatório TXT
│   ├── report_json.sh          # relatório JSON
│   ├── report_html.sh          # relatório HTML
│   └── módulos de coleta
├── tests/
│   └── run_tests.sh            # suíte de testes
├── reports/                    # relatórios gerados
└── logs/                       # logs de execução
```

---

## Arquitetura

```text
Argumentos da CLI
        ↓
Configuração e thresholds
        ↓
Seleção e carregamento dos módulos
        ↓
Coleta de métricas e alertas
        ↓
Classificação do estado de saúde
        ↓
Terminal / TXT / JSON / HTML
```

Cada módulo implementa uma função principal independente e envia os resultados para um coletor central. Isso permite adicionar novos diagnósticos sem concentrar toda a lógica em um único arquivo.

---

## Testes e validação

### Self-test

```bash
vps-healthcheck --self-test
```

### Suíte de testes

```bash
chmod +x tests/run_tests.sh
./tests/run_tests.sh
```

Também estão disponíveis:

```bash
./tests/run_tests.sh --verbose
./tests/run_tests.sh --stop-on-failure
./tests/run_tests.sh --libraries-only
./tests/run_tests.sh --files-only
./tests/run_tests.sh --no-integration
```

---

## Casos de uso

- inventário inicial de uma VPS;
- diagnóstico antes de manutenção;
- comparação antes e depois de alterações;
- coleta de evidências durante incidentes;
- documentação de servidores;
- auditoria de recursos e serviços;
- geração de relatórios para suporte técnico;
- entrada estruturada para automações e ferramentas de observabilidade;
- base para rotinas agendadas com `cron` ou timers do `systemd`.

---

## Limitações atuais

- não substitui observabilidade contínua;
- registra uma fotografia do estado do servidor no momento da coleta;
- alguns módulos especializados ainda dependem da evolução da implementação pública;
- determinadas métricas exigem permissões administrativas;
- a disponibilidade das informações varia conforme distribuição, kernel, hardware e serviços instalados;
- o projeto não aplica correções automáticas.

---

## Roadmap

- concluir e validar módulos especializados;
- integrar opcionalmente Telegram, e-mail ou webhook;
- adicionar execução agendada com retenção de histórico;
- comparar relatórios entre execuções;
- disponibilizar pacote `.deb`;
- adicionar CI com ShellCheck e testes automatizados;
- publicar exemplos anonimizados de relatórios;
- criar modo resumido orientado a alertas;
- exportar métricas em formato compatível com Prometheus.

---

## Princípios do projeto

`Coleta segura` · `Transparência` · `Modularidade` · `Portabilidade` · `Configuração explícita` · `Relatórios reutilizáveis`

---

## Autor

Desenvolvido e mantido por **Eduardo Miranda**.

[![GitHub](https://img.shields.io/badge/GitHub-EduMiranda78-181717?logo=github)](https://github.com/EduMiranda78)
[![Site](https://img.shields.io/badge/Site-Miranda%20Stack-f4b740)](https://mirandastack.com/)
