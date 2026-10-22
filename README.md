# Parque 3.4 — Sistema de Inventário e Gestão Computacional

Sistema de coleta de inventário de TI e automação remota para um parque de
computadores **Windows e Linux**, sem necessidade de servidor dedicado ou banco
de dados. A comunicação entre os computadores (agentes) e o operador acontece
via **arquivos em uma pasta compartilhada**.

> **Autor:** 1SG-PL BRUNO · **Organização:** DepMSMRJ (Marinha)
> **Contato:** bruno.ramos@marinha.mil.br

---

## Índice

- [Visão geral](#visão-geral)
- [Arquitetura](#arquitetura)
- [Estrutura de arquivos](#estrutura-de-arquivos)
- [Configuração (`parque.conf`)](#configuração-parqueconf)
- [Scripts](#scripts)
- [Fluxos de uso](#fluxos-de-uso)
- [Dashboard web](#dashboard-web)
  - [Score de saúde](#score-de-saúde)
- [Implantação](#implantação)
- [Solução de problemas](#solução-de-problemas)

---

## Visão geral

O sistema resolve dois problemas:

1. **Inventário automatizado** — coletar, de cada máquina, dezenas de
   informações de hardware, sistema operacional, rede e segurança, e consolidar
   tudo em um painel único.
2. **Automação remota** — disparar, do posto do operador, ações nas máquinas
   (executar coleta, instalar/desinstalar software) através de "comandos"
   deixados em arquivo.

Tudo isso **sem servidor web, sem agente sempre-conectado, sem banco de dados**.
Basta um compartilhamento de arquivos acessível por todas as máquinas.

---

## Arquitetura

Modelo de **"caixa de correio por arquivos"**: não há comunicação direta entre
operador e máquinas. A pasta compartilhada é o meio de troca.

```
        ┌─────────────────────────────────────────────────────┐
        │           PASTA COMPARTILHADA (parque)              │
        │                                                     │
        │  inventario_web.html   ◄── dashboard consolidado    │
        │  parque.conf           ◄── configuração única       │
        │  inventario/           ◄── JSON/HTML por máquina    │
        │  comandos/<PC>.json    ◄── fila de comandos por PC  │
        │  executados/           ◄── histórico de comandos    │
        │  retorno/<PC>.log      ◄── log de cada PC           │
        │  softwares/            ◄── instaladores             │
        └─────────────────────────────────────────────────────┘
             ▲  operador solta comando            ▲  agente grava inventário
             │  (JSON em comandos/)               │  (JSON/HTML individual)
             │                                     │
   ┌─────────┴──────────┐              ┌──────────┴──────────────────────┐
   │  POSTO DO OPERADOR │              │  AGENTE (1 por máquina)         │
   │  (edita arquivos)  │              │  agente.ps1 (Windows)           │
   └────────────────────┘              │  loop a cada 60s lê comandos/   │
                                       │  → executa coleta/instalação    │
                                       └─────────────────────────────────┘
```

**Por que funciona sem servidor?** Cada agente roda um loop local (a cada 60s,
configurável) que apenas verifica se existe um arquivo de comando com o seu
próprio nome de host. Se existir, executa; se não, dorme. Não há portas abertas,
não há serviço de rede, não há agendador central.

---

## Estrutura de arquivos

```
parque/
├── parque.conf.example       # Modelo versionável de configuração
├── parque.conf               # Configuração local (não versionar)
├── windows.ps1               # Coletor de inventário para Windows
├── linux.sh                  # Coletor de inventário para Linux
├── agente.ps1                # Agente de automação (Windows)
├── agente.sh                 # Agente de automação (Linux, só inventário)
├── agente.bat                # Lançador do agente (Windows)
├── 1 - coletar.bat           # Lançador manual da coleta (Windows)
├── install_deps_ubuntu.sh    # Instala dependências do linux.sh (Ubuntu/Debian)
├── consolidar_inventario.ps1 # Consolida inventario/*.json no dashboard
├── consolidar_inventario.sh  # Consolidador equivalente para Linux
├── inventario_schema.json    # Lista canonica de campos do inventario
├── topologia_fisica.example.json # Modelo de mapeamento Divisão/Setor (versionar)
├── topologia_fisica.json   # Mapeamento real por host (não versionar)
├── teste.ps1 / teste.bat     # Scripts de benchmark (não production)
├── inventario_web.template.html # Dashboard publicável sem dados reais
├── inventario_web.html       # Dashboard operacional local com dados inline
├── inventario/               # Inventários individuais por máquina (não versionar)
│   ├── <HOSTNAME>.json
│   └── <HOSTNAME>.html
├── comandos/                 # Fila local: operador cria <HOSTNAME>.json aqui
├── executados/               # Histórico local: comandos já processados
├── retorno/                  # Logs locais de execução por máquina
└── softwares/                # Instaladores locais para deploy remoto
```

### O que entra no Git

O repositório deve guardar o produto, não os dados coletados. Versione scripts,
documentação, modelos e templates:

- `README.md`, `.gitignore`, `parque.conf.example`
- `windows.ps1`, `linux.sh`, `agente.ps1`, `agente.bat`, `agente.sh`
- `1 - coletar.bat`, `install_deps_ubuntu.sh`
- `consolidar_inventario.ps1`, `consolidar_inventario.sh`
- `inventario_schema.json`
- `inventario_web.template.html`
- `topologia_fisica.example.json`

Ficam fora do Git por padrão: `parque.conf`, `topologia_fisica.json`, `inventario_web.html`,
`inventario/`, `executados/`, `retorno/`, `comandos/`, `softwares/`, logs,
zips, screenshots e sobras de refatoração. Esses arquivos podem conter dados
reais de máquinas, usuários, rede, inventário e execução.

---

## Configuração (`parque.conf`)

Copie `parque.conf.example` para `parque.conf` e ajuste somente o que precisar.
O `parque.conf` real é local e não deve ser versionado. O arquivo usa o formato
`CHAVE=VALOR` (linhas com `#` são ignoradas) e é lido por `windows.ps1`,
`linux.sh` e `agente.ps1`.

### Princípio: zero-config por padrão

Se você **não mexer em nada**, o sistema funciona: os scripts calculam a pasta
base automaticamente a partir do local onde estão instalados. Você só precisa
editar o `parque.conf` para personalizar.

### Chaves disponíveis

| Chave | Default | Descrição |
|---|---|---|
| `PROJECT_DIR` | *(pasta dos scripts)* | Pasta raiz do projeto. Deixe vazio para usar a pasta onde os scripts estão. |
| `HTML_FILE` | `inventario_web.html` | Arquivo HTML central (dashboard + dados). |
| `HTML_TEMPLATE_FILE` | `inventario_web.template.html` | Template usado para criar o HTML operacional se ele não existir. |
| `INVENTORY_DIR` | `inventario` | Pasta dos inventários individuais por máquina. |
| `SCHEMA_FILE` | `inventario_schema.json` | Schema com a lista canônica de campos. |
| `COMANDOS_DIR` | `comandos` | Fila de comandos (`<HOSTNAME>.json`). |
| `EXECUTADOS_DIR` | `executados` | Histórico de comandos processados. |
| `RETORNO_DIR` | `retorno` | Logs por máquina (`<HOSTNAME>.log`). |
| `COLETOR_WINDOWS` | `windows.ps1` | Script coletor Windows (usado pelo agente). |
| `COLETOR_LINUX` | `linux.sh` | Script coletor Linux. |
| `CONSOLIDADOR_WINDOWS` | `consolidar_inventario.ps1` | Script que consolida `inventario/*.json` no dashboard. |
| `CONSOLIDADOR_LINUX` | `consolidar_inventario.sh` | Consolidador equivalente para Linux. |
| `INTERVALO_AGENTE_SEG` | `60` | Segundos entre verificações do agente. |
| `PERMITIR_CAMINHOS` | *(vazio = tudo)* | Allowlist de pastas (`;`) para `instalar/copiar/executar/desinstalar`. Vazio permite tudo + avisa no log. |
| `TEMPO_MAX_COMANDO_SEG` | `600` | Timeout por comando (`instalar/desinstalar/executar`); `executar` aceita `timeout_seg` próprio. |
| `TENTATIVAS_GRAVACAO` | `5` | Reservado para rotinas que precisem repetir gravações. |
| `ESPERA_GRAVACAO_SEG` | `3` | Reservado para intervalo entre tentativas. |
| `MARCADOR_DADOS_INI` | `//<DATA_START>` | Marcador de início do bloco JSON no HTML. |
| `MARCADOR_DADOS_FIM` | `//<DATA_END>` | Marcador de fim do bloco JSON no HTML. |

### Regras de valor

- **Em branco** → usa o default calculado.
- **Relativo** (ex.: `inventario`) → interpretado relativo a `PROJECT_DIR`.
- **Absoluto** (ex.: `C:\parque` ou `/opt/parque`) → usado literalmente.

### Exemplos

**Cenário 1 — usar a própria pasta do projeto (mais comum):**
```ini
PROJECT_DIR=
```

**Cenário 2 — apontar para um compartilhamento de rede:**
```ini
# Windows
PROJECT_DIR=\\servidor\parque$

# Linux (montado em /mnt/parque)
PROJECT_DIR=/mnt/parque
```

**Cenário 3 — o agente deve verificar mais rápido (a cada 15s):**
```ini
INTERVALO_AGENTE_SEG=15
```

**Cenário 4 — restringir o que o agente pode tocar (recomendado):**
```ini
# Só aceita arquivos dentro dessas pastas; timeout de 10 min por comando
PERMITIR_CAMINHOS=C:\softwares;\\servidor\parque\softwares
TEMPO_MAX_COMANDO_SEG=600
```

---

## Scripts

### `windows.ps1` — Coletor (Windows)

Coleta 68 campos de uma máquina Windows via WMI/CIM (`Get-CimInstance`), registro,
COM do Windows Update e APIs de hardware (lista canônica em
`inventario_schema.json`). Gera **duas saídas por máquina**:

1. Salva `inventario/<HOSTNAME>.json` (inventário individual em JSON).
2. Gera `inventario/<HOSTNAME>.html` (relatório HTML bonito por máquina).

O coletor **não escreve mais diretamente** no `inventario_web.html`. A
consolidação do dashboard é feita por `consolidar_inventario.ps1`, lendo todos
os JSONs individuais de `inventario/`.

Os JSONs gerados incluem metadados de padronização:

- `SchemaVersao`
- `Plataforma`
- `Coletor`
- `Coletor_Versao`

**Campos coletados:** identidade (hostname, usuário, domínio), SO (versão, build,
data de instalação, uptime, **status de licença/ativação**, chave parcial), CPU
(modelo, núcleos, threads, clock), placa-mãe, BIOS, RAM (total, pentes, tipo,
velocidade, fabricante), armazenamento (discos físicos, volumes, SMART), GPU,
monitores (modelo e número de série), resolução, bateria, impressoras, rede
(IP, MAC, gateway, DNS, DHCP), antivírus, firewall, WSUS, admins locais, portas
TCP/UDP abertas, updates pendentes, top-5 processos por CPU e RAM, etc.

### `linux.sh` — Coletor (Linux)

Equivalente do `windows.ps1` para Linux. Usa `dmidecode`, `lscpu`, `lsblk`,
`xrandr`, `upower`, `ss`, `smartctl`, `jq`, entre outros. **Requer root** e
gera as mesmas duas saídas individuais. Ele também não escreve diretamente no
HTML central.

> **Dependências:** rode `sudo ./install_deps_ubuntu.sh` (Ubuntu/Debian) antes
> da primeira execução para instalar `jq`, `dmidecode`, `smartmontools`, etc.

### `agente.ps1` — Agente (Windows)

Loop infinito (a cada `INTERVALO_AGENTE_SEG` segundos) que monitora a existência
de `comandos/<HOSTNAME>.json`. Quando aparece, lê o JSON e executa a ação
solicitada, depois move o arquivo para `executados/` e registra tudo em
`retorno/<HOSTNAME>.log`.

**Ações suportadas:**

| Ação | Comportamento |
|---|---|
| `inventario` | Executa o coletor (`powershell` 5.1 ou `pwsh` 7+, o que existir) e checa o código de saída. Falha do coletor é registrada no log em vez de "concluído" falso. |
| `instalar` | Instala software silenciosamente: `.msi` via `msiexec /i ... /qn`, `.exe` direto. Respeita allowlist e timeout; registra código de saída. |
| `desinstalar` | Remove software: aceita ProductCode `{GUID}`, caminho `.msi`/`.exe` ou DisplayName exato do registro (usa `QuietUninstallString`, senão converte `/I` em `/X`). Respeita allowlist e timeout. |
| `executar` | Roda `.ps1`/`.bat`/`.cmd`/`.exe` com `parametros` (e `timeout_seg` opcional). Saída vai para `retorno/<HOST>-executar.out.log`. Respeita allowlist e timeout. |
| `copiar` | Copia arquivo ou pasta (`origem` → `destino`, com `-Recurse`). Origem e destino precisam estar na allowlist. |

Comandos processados são arquivados em `executados/<HOST>-<timestamp>.json`
(o timestamp preserva o histórico em vez de sobrescrever). JSON inválido não
trava a fila: após 3 leituras com erro de parse, o arquivo é arquivado como
`<HOST>.invalido-<timestamp>.json` com 1 linha de erro no log — corrija e
publique novamente em `comandos/`.

Após cada comando (inclusive erros de parse e ações desconhecidas), o agente
grava o status estruturado em `retorno/<HOSTNAME>.json`
(`Computador, Acao, Inicio, Fim, Sucesso, CodigoSaida, Mensagem,
ComandoOrigem, ArquivoArquivado, AgenteVersao`) — o `.log` segue como
histórico legível.

**Segurança:** `PERMITIR_CAMINHOS` (no `parque.conf`) limita quais caminhos
`instalar/copiar/executar/desinstalar` aceitam. Vazio = permite tudo (com
aviso no log). `TEMPO_MAX_COMANDO_SEG` (padrão 600s) interrompe processos
travados; `executar` aceita `timeout_seg` próprio por comando.

### `agente.sh` — Agente (Linux)

Equivalente básico para Linux: loop com o mesmo protocolo de arquivos
(`comandos/`, `executados/` com timestamp, `retorno/` + status JSON, guarda
anti poison-file). Suporta **`inventario`** (roda `COLETOR_LINUX`, exige root
para coleta completa); demais ações são logadas como não suportadas e
arquivadas. Rode com `sudo ./agente.sh`.

### `agente.bat`

Lançador do `agente.ps1`. Executa o agente em primeiro plano. (Há uma linha
comentada para modo oculto `-WindowStyle Hidden`, se preferir rodar escondido.)

### `1 - coletar.bat`

Lançador **manual** da coleta — mostra um banner e executa `windows.ps1`.
Útil para coletar uma única máquina sob demanda (sem precisar do agente).

### `install_deps_ubuntu.sh`

Instala as dependências de sistema do `linux.sh` em Ubuntu/Debian
(`apt-get install jq dmidecode smartmontools ...`).

### `consolidar_inventario.ps1` / `consolidar_inventario.sh`

Lê todos os arquivos `inventario/*.json`, ignora entradas inválidas, remove
duplicidades por `Computador`, ordena os registros e atualiza o bloco
`inventoryData` do `inventario_web.html`.

Antes de gerar o dashboard, o consolidador normaliza cada registro conforme
`inventario_schema.json`: todos os computadores passam a ter a mesma lista de
campos, na mesma ordem. Campos ausentes em inventários antigos são preenchidos
com `null`.

O consolidador cria um backup do HTML antes de regravar e também gera
`inventario/inventario_web.json` como espelho agregado dos dados consolidados.
Esse arquivo agregado é operacional e fica fora do Git.

### `teste.ps1` / `teste.bat` — Benchmark

Scripts de **teste de desempenho** (não fazem parte do fluxo de produção).
Comparam a velocidade da coleta via `Get-WmiObject` (legado) vs.
`Get-CimInstance` (moderno). O resultado sai em `velocidade.txt`.

---

## Fluxos de uso

### 1. Coletar uma única máquina (manual)

Na própria máquina, execute:
```bat
.\1 - coletar.bat
```
Ou, no Linux:
```bash
sudo ./linux.sh
```
O inventário da máquina é gravado em `inventario/<HOSTNAME>.json` e
`inventario/<HOSTNAME>.html`. Rode o consolidador para atualizar o dashboard
central.

### 2. Coletar remotamente via agente

Garanta que o `agente.ps1` está rodando na máquina-alvo (via `agente.bat` ou
como tarefa agendada). No posto do operador, crie o arquivo de comando:

**`comandos/<HOSTNAME>.json`:**
```json
{"acao":"inventario"}
```

Em até `INTERVALO_AGENTE_SEG` segundos, o agente da máquina-alvo verá o comando,
executará `windows.ps1` e arquivará o comando em `executados/`. Acompanhe o
resultado em `retorno/<HOSTNAME>.log`.

### 3. Instalar / desinstalar / executar / copiar remotamente

Coloque o instalador em `softwares/` (acessível pela máquina-alvo) e crie:

**`comandos/<HOSTNAME>.json` (MSI, silencioso):**
```json
{
  "acao": "instalar",
  "arquivo": "C:\caminho\para\softwares\LibreOffice.msi",
  "parametros": "/qn"
}
```

**`.exe` (instalador com modo silencioso próprio):**
```json
{
  "acao": "instalar",
  "arquivo": "C:\caminho\para\softwares\K-Lite.exe",
  "parametros": "/VERYSILENT"
}
```

> **Importante:** o `arquivo` deve ser um caminho **válido na máquina-alvo**
> (não no posto do operador). Para MSI, o agente aciona `msiexec /i ... /qn`
> automaticamente e gera um log detalhado em `%TEMP%`.

**`comandos/<HOSTNAME>.json` (desinstalar por ProductCode):**
```json
{
  "acao": "desinstalar",
  "arquivo": "{12345678-1234-1234-1234-123456789012}"
}
```
Também aceita caminho `.msi`/`.exe` ou o DisplayName exato do
Painel de Controle (ex.: `"arquivo": "K-Lite Codec Pack"`).

**`comandos/<HOSTNAME>.json` (executar script, timeout próprio):**
```json
{
  "acao": "executar",
  "arquivo": "C:\\caminho\\para\\softwares\\rotina.ps1",
  "parametros": "-Modo Rapido",
  "timeout_seg": 120
}
```

**`comandos/<HOSTNAME>.json` (copiar arquivo/pasta):**
```json
{
  "acao": "copiar",
  "origem": "\\\\servidor\\parque\\softwares\\manual.pdf",
  "destino": "C:\\Manuais\\manual.pdf"
}
```

Origem e destino de `copiar` (e `arquivo` de `instalar/executar/desinstalar`
quando for caminho) precisam estar em `PERMITIR_CAMINHOS`. O resultado de
todo comando sai em `retorno/<HOSTNAME>.log` e no status estruturado
`retorno/<HOSTNAME>.json` (`Sucesso`, `CodigoSaida`, `Mensagem`).

### 4. Visualizar o inventário consolidado

Depois de rodar coletas em uma ou mais máquinas, consolide os arquivos
individuais:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\consolidar_inventario.ps1
```

No Linux:

```bash
./consolidar_inventario.sh
```

Abra `inventario_web.html` em qualquer navegador. Não é necessário servidor —
o arquivo é autossuficiente (HTML + CSS + JS + dados JSON inline).

---

## Dashboard web

Use `inventario_web.template.html` como base publicável do dashboard. Em uma
instalação real, o consolidador copia esse template para `inventario_web.html`
se o HTML operacional ainda não existir.

O `inventario_web.html` operacional não deve ir para o Git, porque contém dados
consolidados reais do parque.

O `inventario_web.html` é um arquivo único e autossuficiente que contém:

- **Os dados consolidados** — array JavaScript `inventoryData` embutido entre
  os marcadores `//<DATA_START>` e `//<DATA_END>`, gerado a partir de
  `inventario/*.json`.
- **A interface** — 4 abas (Dashboard, Alertas, Inventário, Topologia), cards gerenciais
  (Total/OK/Atenção/Críticas/Disco baixo/Sem WSUS/Windows 10/Coleta antiga),
  barras de distribuição (SO, RAM, disco, segurança), Top prioridades com
  score de saúde, tabela com paginação, ordenação por coluna, filtros por
  coluna, busca global, tema claro/escuro, detalhe por máquina (duplo-clique na
  tabela, clique nos alertas e nos nós da topologia), exportação CSV e modal de
  seleção de colunas. Cards com count-up, barras animadas, tooltip rico e CSS de
  impressão. Funciona offline (sem CDN).

Por isso, **basta abrir o arquivo no navegador** para ver o parque consolidado.
Os scripts de coleta atualizam apenas os JSONs individuais. O consolidador é o
único responsável por atualizar o array `inventoryData` do dashboard, reduzindo
o risco de corrupção por gravações simultâneas.

> **Atenção:** nunca edite manualmente a região entre `//<DATA_START>` e
> `//<DATA_END>` — ela é gerenciada pelo consolidador. A estrutura do dashboard
> (HTML/CSS/JS) pode ser editada livremente fora dessa região.

### Score de saúde

Cada máquina recebe uma nota de 0–100 calculada no navegador (`calcScore` /
`getReasons` no template). Parte de 100 e desconta por motivo encontrado:

| Peso | Motivos |
|---|---|
| −18 (`bad`) | Disco C com < 10% livre; RAM < 4 GB; ≥ 20 updates pendentes; Windows não ativado (só Windows); firewall desativado; antivírus inativo; coleta com > 15 dias |
| −9 (`warn`) | Disco C com < 20% livre; RAM < 8 GB; ≥ 5 updates pendentes; sem WSUS (só Windows); coleta com > 7 dias; sistema 32 bits; Windows 10 ou build < 22000 (só Windows) |
| −3 (`info`) | Disco mecânico (HDD) |
| −8 cada | `ConsumoCPU_Percentual` > 85; `ConsumoRAM_Percentual` > 85 |

Faixas: `< 60` Crítico, `60–79` Atenção, `≥ 80` OK. Regras marcadas
"(só Windows)" usam `Plataforma` (com fallback para `SO`) e são ignoradas
em Linux, onde os campos equivalentes valem `N/A`.

Exemplo: máquina com RAM 4 GB (−9), 9 updates pendentes (−9), coleta com
168 dias (−18), 32 bits (−9), Win10/build antigo (−9) e HDD (−3) = **43/100**.

> **Notas:** o score decai com o tempo mesmo sem mudanças na máquina, pois a
> idade da coleta (`DataHora_Coleta` vs. data atual) conta como motivo. E a
> checagem de ativação usa substring (`includes("ativado")`), então o valor
> padrão `Nao Ativado` do coletor não dispara o alerta — só textos que não
> contenham "ativado".

### Topologia física (Divisão/Setor)

A aba 🗺️ Topologia tem dois modos: **Divisão / Setor** (organizacional) e
**Sub-rede** (por /24 do IP, automático). O modo organizacional funciona em
duas camadas:

1. **Regra automática pelo hostname** (sem digitar nada): `DEPMSMRJ-1xx` →
   Divisão 10, `2xx` → Divisão 20, `3xx` → Divisão 30 (vale para 2 ou 3
   dígitos, com letra opcional: `204A`, `30A`); sufixo não-numérico
   (`SECOM`, `CPD`…) vira setor próprio fora das divisões.
2. **Override manual** em `topologia_fisica.json` (na raiz, ao lado do
   `parque.conf`, fora do Git): `{"DEPMSMRJ-01": {"Divisao": null, "Setor":
   "Gabinete"}}`. Use o modelo `topologia_fisica.example.json` como base.
   O consolidador (`.sh` e `.ps1`) injeta `Divisao`/`Setor` em cada registro;
   JSON inválido é ignorado com aviso, sem quebrar a consolidação.

Sem mapeamento e sem prefixo reconhecido, a máquina cai em "Não mapeado".
A barra de núcleo mostra gateway/DNS majoritários (derivados do inventário).
A aba traz ainda: KPIs animados (máquinas, com IP, críticas, sem mapeamento),
donut de SO e barras de cobertura clicáveis como filtro, tooltip rico por
máquina (score, local, IP/MAC/SO/coleta) e CSS de impressão.

---

## Implantação

### Windows (passo a passo)

1. Copie toda a pasta do projeto para um compartilhamento acessível por todas
   as máquinas (ex.: `\\servidor\parque$`).
2. Ajuste `parque.conf` se necessário (ou deixe vazio para usar a pasta local).
3. Em cada máquina-alvo:
   - Rode `install_deps` equivalente apenas para o Linux; no Windows não há
     dependências extras.
   - Para coleta manual: execute `1 - coletar.bat`.
   - Para automação contínua: agende `agente.bat` como **tarefa agendada**
     (Executar com privilégios elevados, ao iniciar o sistema).

### Linux

1. Monte o compartilhamento em todas as máquinas (ex.: `/mnt/parque`).
2. Em cada máquina, instale as dependências:
   ```bash
   sudo ./install_deps_ubuntu.sh
   ```
3. Execute a coleta:
   ```bash
   sudo ./linux.sh
   ```
4. No posto operador, consolide:
   ```bash
   ./consolidar_inventario.sh
   ```
5. Para automação contínua no Linux, rode o agente como root
   (só a ação `inventario`; demais ações são recusadas com log):
   ```bash
   sudo ./agente.sh
   ```

### Permissões

- Os scripts de coleta precisam de **privilégios administrativos** (root no
  Linux, Administrador no Windows) para acessar dados de hardware via
  `dmidecode`/WMI.
- A pasta compartilhada deve permitir leitura/escrita para os usuários das
  máquinas-alvo.

---

## Solução de problemas

### O agente não executa o comando

- Verifique se o arquivo tem o nome **exato** do host da máquina-alvo
  (`comandos/<HOSTNAME>.json`), incluindo maiúsculas/minúsculas.
- Confira se o JSON está bem-formado (vírgulas, aspas). Veja os erros em
  `retorno/<HOSTNAME>.log` — erros de parse aparecem lá. Após 3 leituras com
  erro, o arquivo é arquivado como
  `executados/<HOST>.invalido-<timestamp>.json` (a fila é liberada; corrija e
  publique de novo). O `retorno/<HOSTNAME>.json` mostra o status estruturado
  do último comando (`Sucesso`, `CodigoSaida`, `Mensagem`).
- Confirme o `INTERVALO_AGENTE_SEG` no `parque.conf` (padrão: 60s).

### Comando bloqueado pela allowlist

- `Caminho fora da allowlist (PERMITIR_CAMINHOS)` no log = origem/destino
  fora das pastas liberadas. Ajuste `PERMITIR_CAMINHOS` no `parque.conf`
  (lista separada por `;`) ou mova os arquivos para dentro dela.

### Comando interrompido por timeout

- `excedeu o timeout` no log = processo travou além de
  `TEMPO_MAX_COMANDO_SEG` (padrão 600s) e foi finalizado. Para `executar`,
  use `timeout_seg` próprio no JSON; a saída parcial fica em
  `retorno/<HOST>-executar.out.log`.

### A instalação remota falha

- MSI com código `1603` (erro fatal de instalação): verifique o log em
  `%TEMP%\<HOSTNAME>_<timestamp>.log` (caminho indicado em `retorno/`).
- "%1 não é um aplicativo Win32 válido": o `.exe` é de arquitetura incompatível
  (ex.: x86 num SO só x64, ou vice-versa) — ou um `.msi` foi passado onde se
  esperava `.exe`. MSI é tratado automaticamente pelo agente.
- `ArgumentList nulo`: o JSON não incluiu `parametros`. O agente agora trata
  isso como string vazia.

### O HTML central corrompe / perde dados

- Os coletores não gravam mais diretamente no HTML central. Rode novamente
  `consolidar_inventario.ps1` ou `consolidar_inventario.sh`; o consolidador
  recria o bloco central a partir dos JSONs individuais e deixa backup do HTML.
- Mantenha os marcadores `//<DATA_START>` / `//<DATA_END>` intactos no HTML.

### Caminhos não resolvem

- Confirme `PROJECT_DIR` no `parque.conf`. Vazio = pasta dos scripts.
- Caminhos relativos são relativos a `PROJECT_DIR`. Use caminhos absolutos se
  a estrutura de pastas for diferente entre máquinas.

---

## Notas de versão

- **3.4** — Aba Topologia: visão por Divisão/Setor (regra por hostname +
  override manual `topologia_fisica.json`) e por sub-rede, com KPIs, donut de
  SO, tooltip e núcleo L3; mesmos efeitos no Dashboard (count-up, barras
  animadas, alertas clicáveis, print CSS).
- **3.3** — Agente com novas ações: `desinstalar` (GUID/.msi/.exe/DisplayName),
  `executar` (`.ps1`/`.bat`/`.exe` com timeout próprio) e `copiar` real;
  allowlist `PERMITIR_CAMINHOS`, timeout `TEMPO_MAX_COMANDO_SEG`, status
  estruturado em `retorno/<HOST>.json`, histórico com timestamp em
  `executados/`; novo `agente.sh` para Linux (ação `inventario`).
- **3.2** — Dashboard gerencial (Plus) como template: abas Dashboard/Alertas/
  Inventário, score de saúde por máquina, top prioridades e exportação CSV;
  funciona offline (sem CDN). Correção do bloco `inventoryData` para dentro
  de `<script>`. Documentação do cálculo do score no README.
- **3.1** — Centralização da configuração em `parque.conf`; remoção de caminhos
  hardcoded dos scripts (`windows.ps1`, `linux.sh`, `agente.ps1`). O sistema
  agora funciona zero-config e é portável entre ambientes.
