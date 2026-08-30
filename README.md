# VPS Healthcheck

Ferramenta modular de **auditoria, diagnóstico, inventário e monitoramento pontual** para servidores VPS Linux.

O projeto centraliza informações operacionais importantes em uma única execução, classifica resultados por nível de saúde e gera relatórios reutilizáveis para suporte, documentação, manutenção preventiva e análise de incidentes.

> Versão atual: **0.1.1**  
> Plataforma: **Linux**  
> Linguagem: **Bash 4.4+**  
> Foco inicial: **Debian 12** e **Ubuntu 22.04+**

---

## Visão geral

Administrar uma VPS normalmente exige consultar vários comandos, arquivos de configuração e serviços diferentes. O VPS Healthcheck organiza esse processo em uma ferramenta única, com execução rápida ou completa, módulos independentes, limites configuráveis e múltiplos formatos de saída.

A ferramenta foi projetada para responder, de forma estruturada, perguntas como:

- Qual é o estado atual do servidor?
- Há pressão de CPU, memória, disco ou swap?
- Existem serviços com falha?
- Quais portas estão abertas e quais processos estão escutando?
- Há atualizações ou reinicializações pendentes?
- Quais pontos exigem atenção imediata?
- Como registrar o estado da VPS antes e depois de uma manutenção?

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

Os módulos centrais presentes na versão pública atual cobrem:

| Módulo | Função principal |
|---|---|
| Sistema | distribuição, kernel, arquitetura, hostname, uptime, horário e virtualização |
| CPU | modelo, núcleos, carga, uso, frequência, processos e temperatura quando disponível |
| Memória | memória total, disponível, utilizada, cache, swap e processos consumidores |
| Disco | sistemas de arquivos, inodes, dispositivos, montagens, diretórios e arquivos relevantes |
| Rede | interfaces, endereços, gateway, DNS, rotas, portas e conexões |
| Serviços | unidades `systemd`, serviços em execução, falhas, timers e sockets |
| Atualizações | pacotes disponíveis, atualizações de segurança e reinicialização pendente |

### Expansão modular

A CLI, a configuração e o registro interno já preveem módulos especializados para:

- aplicações Python;
- Docker;
- Nginx;
- certificados SSL;
- bancos de dados;
- firewall;
- segurança;
- logs;
- serviços de IA;
- Ollama.

Esses módulos são tratados como opcionais pela arquitetura. Quando um módulo opcional não está disponível, a execução pode registrá-lo como ignorado sem interromper os módulos obrigatórios.

---

## Status de saúde

Os dados coletados são organizados por módulos, métricas e alertas. O motor interno trabalha com estados como:

- `OK`
- `WARNING`
- `CRITICAL`
- `UNKNOWN`
- `SKIPPED`

Os limites podem ser alterados em `config/thresholds.conf`, permitindo adaptar a ferramenta ao perfil de cada servidor.

Exemplos de critérios configuráveis:

- percentual de CPU;
- utilização de memória e swap;
- ocupação de disco e inodes;
- quantidade de falhas ou eventos;
- tempo de uptime;
- limites operacionais específicos por módulo.

---

## Formatos de saída

A mesma execução pode gerar um ou mais formatos:

| Formato | Uso indicado |
|---|---|
| Terminal | inspeção imediata durante suporte ou manutenção |
| TXT | registro simples, anexos e documentação técnica |
| JSON | integrações, automações e processamento por outras ferramentas |
| HTML | relatório visual para consulta, apresentação ou arquivo |

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

Após a instalação:

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

Executa os módulos essenciais de sistema, CPU, memória, disco, rede, serviços e atualizações.

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
vps-healthcheck --system --cpu --memory
```

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

O comportamento padrão é controlado por dois arquivos:

```text
config/healthcheck.conf
config/thresholds.conf
```

### `healthcheck.conf`

Controla:

- modo de execução padrão;
- formatos de saída;
- diretórios de relatórios e logs;
- uso de `sudo`;
- módulos habilitados;
- timeouts;
- privacidade e redação de dados;
- profundidade e limites de varredura;
- comportamento após falhas opcionais ou obrigatórias.

### `thresholds.conf`

Centraliza limites usados para classificar métricas e alertas como `OK`, `WARNING` ou `CRITICAL`.

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
- execução limitada a coleta e diagnóstico, sem aplicar correções automaticamente.

Antes de compartilhar um relatório externamente, revise o conteúdo e ajuste as opções de redação ao ambiente.

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

O fluxo principal é dividido em etapas:

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

### Self-test da instalação

```bash
vps-healthcheck --self-test
```

Valida arquivos essenciais, bibliotecas, configuração, permissões e funções internas.

### Suíte de testes

```bash
chmod +x tests/run_tests.sh
./tests/run_tests.sh
```

Opções disponíveis:

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
- diagnóstico antes de uma manutenção;
- comparação antes e depois de alterações;
- coleta de evidências durante incidentes;
- documentação de servidores;
- auditoria de recursos e serviços;
- geração de relatórios para suporte técnico;
- entrada estruturada para automações e ferramentas de observabilidade;
- base para rotinas agendadas com `cron` ou timers do `systemd`.

---

## Limitações atuais

- não substitui uma plataforma de observabilidade contínua;
- executa uma fotografia do estado do servidor no momento da coleta;
- alguns módulos especializados ainda dependem da evolução da implementação pública;
- determinadas métricas exigem permissões administrativas;
- a disponibilidade de informações varia conforme distribuição, kernel, hardware e serviços instalados;
- o projeto não aplica correções automáticas.

---

## Roadmap sugerido

- concluir e validar todos os módulos especializados;
- adicionar integração opcional com Telegram, e-mail ou webhook;
- criar execução agendada com retenção de histórico;
- gerar comparação entre relatórios;
- disponibilizar pacote `.deb`;
- adicionar CI com ShellCheck e testes automatizados;
- publicar exemplos reais de relatórios anonimizados;
- criar modo resumido orientado a alertas;
- exportar métricas em formato compatível com Prometheus.

---

## Princípios do projeto

- coleta segura;
- transparência dos resultados;
- modularidade;
- portabilidade;
- configuração explícita;
- relatórios reutilizáveis;
- nenhuma alteração automática no servidor durante a auditoria.

---

## Autor

Desenvolvido e mantido por **Eduardo Miranda**.

Repositório: `EduMiranda78/vps-healthcheck`  
Site: [Miranda Stack](https://mirandastack.com/)
