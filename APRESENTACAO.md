# Apresentação do VPS Healthcheck

## 1. O projeto

O **VPS Healthcheck** é uma ferramenta de linha de comando desenvolvida em Bash para realizar auditoria, diagnóstico, inventário e monitoramento pontual de servidores VPS Linux.

Seu objetivo é transformar uma sequência fragmentada de comandos administrativos em uma coleta organizada, reproduzível e documentável.

---

## 2. O problema

A análise manual de uma VPS normalmente exige consultar diferentes fontes:

- sistema operacional e kernel;
- consumo de CPU e memória;
- espaço em disco e inodes;
- interfaces, rotas, DNS e portas;
- serviços em execução ou com falha;
- atualizações pendentes;
- logs e configurações específicas.

Esse processo consome tempo, depende da experiência do operador e dificulta a comparação entre o estado anterior e posterior a uma manutenção.

---

## 3. A solução

O VPS Healthcheck executa uma auditoria padronizada e entrega uma visão consolidada do servidor.

A ferramenta:

1. carrega configurações e thresholds;
2. seleciona os módulos solicitados;
3. coleta métricas e evidências;
4. classifica resultados por nível de saúde;
5. gera alertas e recomendações técnicas;
6. produz relatórios reutilizáveis.

---

## 4. Proposta de valor

### Para suporte técnico

Reduz o tempo necessário para entender o estado inicial do servidor.

### Para manutenção preventiva

Ajuda a localizar sinais de saturação, falhas de serviço e atualizações pendentes.

### Para documentação

Produz registros estruturados que podem ser anexados a tickets, procedimentos e inventários.

### Para automação

Oferece JSON, códigos de saída específicos e execução não interativa.

### Para segurança operacional

Realiza coleta e diagnóstico sem aplicar correções automáticas no ambiente.

---

## 5. Público-alvo

- administradores de sistemas Linux;
- profissionais de infraestrutura;
- equipes DevOps e SRE;
- desenvolvedores responsáveis por aplicações em VPS;
- consultores de tecnologia;
- prestadores de suporte;
- usuários que mantêm servidores próprios.

---

## 6. Recursos centrais

- auditoria rápida;
- auditoria completa;
- execução por módulo;
- configuração externa;
- thresholds personalizáveis;
- classificação `OK`, `WARNING`, `CRITICAL`, `UNKNOWN` e `SKIPPED`;
- relatórios em terminal, TXT, JSON e HTML;
- logs separados por execução;
- diretórios individuais para cada coleta;
- suporte a `sudo` opcional;
- modo não interativo;
- códigos de saída específicos;
- self-test;
- suíte própria de testes;
- instalador com backup automático.

---

## 7. Módulos operacionais

A versão pública atual possui módulos centrais para:

- sistema;
- CPU;
- memória;
- disco;
- rede;
- serviços;
- atualizações.

A arquitetura também registra módulos especializados para Python, Docker, Nginx, SSL, bancos de dados, firewall, segurança, logs, serviços de IA e Ollama.

Os módulos especializados são opcionais e podem ser incorporados progressivamente sem alterar o núcleo da aplicação.

---

## 8. Arquitetura técnica

```text
CLI
 │
 ├── configuração principal
 ├── thresholds
 ├── seleção de módulos
 │
 ▼
Orquestrador
 │
 ├── carregamento seguro de bibliotecas
 ├── validação de dependências
 ├── controle de falhas
 └── execução dos módulos
 │
 ▼
Coletor central
 │
 ├── métricas
 ├── módulos
 ├── alertas
 ├── metadados
 └── status geral
 │
 ▼
Terminal | TXT | JSON | HTML
```

Cada módulo possui uma função principal independente e grava seus resultados em um coletor compartilhado.

---

## 9. Modos de execução

### Rápido

Voltado para uma verificação operacional imediata.

```bash
vps-healthcheck --quick
```

### Completo

Executa todos os módulos disponíveis e habilitados.

```bash
vps-healthcheck --full --html
```

### Direcionado

Executa somente os módulos necessários para uma investigação.

```bash
vps-healthcheck --modules system,cpu,memory,disk
```

### Automatizado

Adequado para scripts, cron, timers e integração com outras ferramentas.

```bash
vps-healthcheck \
  --quick \
  --json \
  --no-terminal \
  --non-interactive
```

---

## 10. Relatórios

### Terminal

Leitura imediata durante a execução.

### TXT

Registro simples e portátil.

### JSON

Integração com scripts, painéis e processamento automatizado.

### HTML

Relatório visual para consulta, documentação e apresentação.

---

## 11. Configuração e personalização

O projeto separa comportamento e critérios de saúde:

```text
config/healthcheck.conf
config/thresholds.conf
```

Isso permite adaptar:

- módulos habilitados;
- formatos de saída;
- diretórios;
- timeouts;
- uso de `sudo`;
- níveis de detalhamento;
- privacidade;
- limites de alerta;
- continuidade após falhas.

---

## 12. Privacidade

A configuração oferece controles para reduzir exposição indevida em relatórios:

- redação de segredos;
- ocultação opcional de IPs;
- ocultação de hostname;
- ocultação de usuários;
- ocultação de domínios;
- exclusão do ambiente dos processos;
- exclusão de valores sensíveis de configuração.

A ferramenta gera evidências técnicas, portanto os relatórios devem ser revisados antes do compartilhamento externo.

---

## 13. Instalação e operação

O instalador copia o projeto para:

```text
/opt/vps-healthcheck
```

E cria o comando global:

```text
/usr/local/bin/vps-healthcheck
```

Em atualizações, o instalador cria backup da versão anterior e executa o self-test antes de concluir.

---

## 14. Qualidade e validação

O projeto inclui:

- validação de argumentos;
- verificação da versão do Bash;
- detecção de sistema incompatível;
- carregamento seguro de arquivos;
- controle de módulos obrigatórios e opcionais;
- limpeza de temporários;
- tratamento de sinais;
- códigos de erro específicos;
- self-test da instalação;
- testes de bibliotecas, estrutura e integração.

---

## 15. Diferenciais

- não depende de uma aplicação web;
- funciona diretamente no terminal;
- arquitetura modular;
- relatórios estruturados;
- configuração explícita;
- adequado para servidores pequenos;
- sem agente residente obrigatório;
- coleta sob demanda;
- base preparada para automação;
- foco simultâneo em operação e documentação.

---

## 16. Limitações

O VPS Healthcheck não substitui soluções de observabilidade contínua como Prometheus, Zabbix ou Grafana.

Ele produz uma fotografia técnica do servidor no momento da execução. Seu papel principal é diagnóstico, auditoria e inventário sob demanda.

Alguns módulos especializados ainda dependem de evolução e validação na versão pública.

---

## 17. Evolução planejada

- conclusão dos módulos especializados;
- integração com notificações;
- histórico e comparação entre execuções;
- exportação para Prometheus;
- pacote Debian;
- CI com ShellCheck;
- exemplos de relatórios anonimizados;
- execução agendada;
- painel resumido de alertas.

---

## 18. Pitch de 30 segundos

O VPS Healthcheck é uma ferramenta modular em Bash que centraliza a auditoria de servidores VPS Linux. Em uma única execução, ela coleta métricas de sistema, recursos, rede, serviços e atualizações, classifica o estado de saúde e gera relatórios em terminal, TXT, JSON e HTML. A proposta é reduzir o tempo de diagnóstico e criar registros padronizados para suporte, manutenção, documentação e automação.

---

## 19. Mensagem principal

> Uma visão estruturada da saúde da sua VPS em uma única execução.
