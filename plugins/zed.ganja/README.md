# zed.ganja

Uma planta de cannabis que cresce na sua barra.

O mesmo grow do [Ganja-TUI](https://github.com/zed/Ganja-TUI) — os 35 strains
com genética real, a mesma arte ASCII procedural de 70×28, o mesmo formato de
save — dentro do shell do Omarchy, em QML puro. Sem binário, sem processo
residente, sem Rust instalado. Fechada, a planta inteira custa **um Timer de 60
segundos** fazendo aritmética sobre números que já estão na memória.

Na barra: um glifo por estágio e um ponto que acende quando há o que fazer.
Clique esquerdo abre a growing room; clique direito rega.

---

## Instalar

```sh
omarchy-guest install        # copia plugins/ para ~/.config/omarchy/plugins/
```

Depois, uma linha em `~/.config/omarchy/shell.json`, dentro de
`bar.layout.left`, `center` ou `right`:

```jsonc
{ "id": "zed.ganja" }
```

Ou, sem editar nada à mão:

```sh
omarchy-shell shell putBarWidget zed.ganja '{"section":"right"}'
```

O plugin só carrega se o id aparecer no `shell.json` — é assim que o
`PluginRegistry` decide o que está habilitado. Depois, **reinicie o shell**:

```sh
omarchy-restart-shell
```

Isso não é opcional nem é cerimônia: o Omarchy sobe o Quickshell com
`QS_DISABLE_FILE_WATCHER=1` de propósito, e nem `rescanPlugins` nem
`Qt.clearComponentCache()` trocam um QML de plugin já compilado. Enquanto não
reiniciar, uma edição no plugin não aparece — e não dá erro nenhum, o que é
pior. A planta nasce sozinha na primeira carga.

O save fica em `~/.local/share/omarchy-guest/ganja/save.json`.

---

## Teclas

Dentro do overlay:

| tecla | o que faz |
|---|---|
| `w` | rega (+40, parando no topo da faixa ótima) |
| `n` | alimenta, NPK (+40, idem) |
| `a` | **modo automático**: a planta se cuida sozinha |
| `t` | tamanho da janela: cheio → grande → médio → pequeno → janela |
| `h` | colhe, se estiver pronta |
| `v` | cicla as cores: Normal → Zen → Rainbow → Matrix |
| `f` | liga/desliga a **demonstração**: 130000x numa cópia |
| `Shift+F` | liga/desliga o **turbo**: 130000x na planta de verdade |
| `Tab` | abre/fecha a aba de colheitas |
| `r` | relê o `save.json` do disco (se o TUI ou outra sessão escreveu nele) |
| `q` / `Esc` | fecha |

Na barra: esquerdo abre, **direito rega** (com um flash no ícone, porque ação
sem resposta visível parece que não aconteceu).

Por IPC, para scripts e agentes:

```sh
omarchy-shell ganja toggle
omarchy-shell ganja water
omarchy-shell ganja feed
omarchy-shell ganja harvest
omarchy-shell ganja mode
omarchy-shell ganja auto
omarchy-shell ganja turbo
omarchy-shell ganja window medio    # ou vazio para ciclar
omarchy-shell ganja status     # "Purple Kush · Flowering · dia 61 · agua 68% · npk 72%"
```

### Modo automático

`a` liga o auto-cuidado do TUI, com os limiares e os valores exatos dele
(`src/app.rs:128`): água abaixo de 40 volta com +50, NPK abaixo de 50 volta com
+40. Com ele ligado a planta nunca passa fome nem sede, o ponto de alerta na
barra só acende para a colheita, e o cabeçalho mostra `AUTO`.

É o modo "só quero ver crescer". Desligado — que é o padrão — regar é a única
coisa que você faz, e é o que dá consequência ao abandono.

### Tamanho e tipo de janela

`t` cicla cinco modos, e o último é de outra espécie:

| modo | o que é |
|---|---|
| `cheio` | a tela inteira (padrão) |
| `grande` | um cartão de até 1280×880, centralizado |
| `medio` | até 980×660 |
| `pequeno` | até 720×450 — some o painel do strain e sobram água, NPK e a colheita |
| `janela` | uma **janela de verdade**, que o Hyprland arruma junto com as outras |

Nos quatro primeiros a sala é uma camada sobre a tela e clicar fora fecha. No
`janela` é uma toplevel comum: dá para deixar a planta num canto do workspace,
lado a lado com o que você está fazendo, em vez de abrir e fechar.

O modo escolhido vai para o save — preferência que volta ao padrão a cada boot
não é preferência.

Nos tamanhos menores a sala corta o que é leitura e mantém o que é
acompanhamento: primeiro sai o painel do strain, depois as linhas de medidor que
menos mudam. A planta nunca sai.

### Os dois modos rápidos

O fator original do Ganja-TUI — 130000x, o ciclo inteiro de 90 dias em 60
segundos — está aqui de duas formas, e elas são coisas diferentes. Por isso duas
teclas, e as duas são liga/desliga:

| | `f` — demonstração | `Shift+F` — turbo |
|---|---|---|
| roda em | uma **cópia** | a planta **de verdade** |
| escreve no save | nunca | sim |
| as colheitas contam | não | sim |
| ao desligar | a planta volta onde estava | fica onde chegou |
| cor no cabeçalho | âmbar | vermelho |

A demonstração é o que se grava para mostrar o plugin a alguém: do broto à
colheita na sua frente, e nada daquilo aconteceu. Deixada ligada, ela colhe e
replanta em loop — uma espécie de protetor de tela.

O turbo é para quando você quer chegar lá. É o TUI inteiro: o mesmo ritmo, as
mesmas consequências.

Os dois **desligam sozinhos quando a sala fecha**, e nenhum dos dois vai para o
save. Um ritmo que queima um ciclo por minuto é coisa que se faz olhando; se
sobrevivesse à janela fechada ou ao reinício do shell, a planta iria embora sem
ninguém ver — e o tempo acumulado é o único bem que ela tem.

---

## O relógio

O TUI roda a 130000x — o ciclo inteiro de 90 dias em 60 segundos. Isso está
certo para algo que você abre, olha crescer e fecha; numa barra significaria uma
colheita por minuto e um ícone piscando sem parar.

Aqui o padrão é **`timeScale` 40**: um ciclo completo em ~54 horas de sessão, ou
seja **cerca de uma semana** de uso normal. Abrir a barra na quarta mostra uma
planta diferente da de segunda, que é o ponto inteiro de acompanhar uma planta.

Para mudar, edite `timeScale` no `manifest.json`:

| ciclo dura | `timeScale` |
|---|---|
| 60 s (o TUI) | 130000 |
| 1 dia de sessão | 90 |
| ~1 semana de uso (padrão) | 40 |
| ~1 mês de uso | 10 |

`turboScale` no mesmo arquivo é o fator do `Shift+F`, e o padrão é o 130000 do
TUI.

**O tempo só corre com o shell rodando.** Máquina desligada, planta parada. Você
volta na segunda e ela está onde você deixou na sexta, não morta de sede. O
campo `last_tick` do save existe só para detectar um save mais novo — nunca para
avançar o relógio.

Água e NPK drenam a `careScale` (0,2 no padrão) da taxa do TUI. Com isso um vaso
cheio dura cerca de um dia de sessão: existe para dar consequência ao abandono,
não para virar tarefa diária.

---

## O ciclo não termina

Colheu, planta outra, automaticamente — dez dias depois de ficar pronta, como o
`auto_harvest` do TUI, só que aqui é o comportamento e não uma opção. `h` colhe
antes, se você não quiser esperar.

O que não se perde é o histórico. `Tab` abre a lista: strain, dia, peso,
qualidade, THC/CBD e quantos sustos a planta levou. É o que separa uma planta
bonita de algo que acumula — a décima colheita tem dez histórias atrás dela. O
arquivo guarda as 100 últimas e descarta as mais velhas.

---

## O save, e o TUI

Formato: os mesmos campos da serialização serde de `App` (`src/app.rs` do
Ganja-TUI), em arquivo próprio. Levar uma planta de um lado para o outro é uma
cópia de arquivo:

```sh
cp ~/.local/share/omarchy-guest/ganja/save.json ~/.local/share/ganjatui/save.json
```

Escrita é sempre atômica (`.tmp` no mesmo diretório, depois `mv`), e o `.tmp`
leva o PID no nome para que duas instâncias do shell não costurem dois JSONs no
mesmo arquivo. Abrir o overlay relê o save: se o do disco for mais novo, ele
ganha. Última escrita vence, sem lock.

**Atenção, e isto é comportamento e não bug:** abrir o `ganjatui` por um minuto
com o save copiado consome um ciclo inteiro da planta. O TUI roda a 130000x e
não sabe que a planta dele mora numa barra. É exatamente o que o `Shift+F` faz
aqui — a diferença é que ali você não escolheu.

---

## Fidelidade

A arte é uma porta de `src/ascii/art.rs`, linha por linha, com os mesmos números
mágicos — inclusive os que parecem errados (o bloco de folhagem só pinta o
quadrante superior esquerdo porque sobrou da versão 35×14 da arte; está portado
como está lá, de propósito).

Duas coisas exigiram cuidado, e são a parte do projeto que podia ter saído
silenciosamente errada:

**O gerador de números.** `SimpleRng` é um LCG de 64 bits, e o motor de JS do
QML (V4, Qt 6.11) **não tem BigInt** — nem o literal `1n`, que é erro de
sintaxe e derruba o parse do arquivo inteiro, nem a função `BigInt()`, que é
`ReferenceError`. O estado de 64 bits é mantido em quatro limbs de 16 bits com a
multiplicação feita à mão. `Number` sozinho não serve: `lo * 1103515245` passa
de 2^53 e perde bits baixos em silêncio.

**A precisão.** O Rust calcula em `f32` e o JS em `f64`. Onde o resultado vira
inteiro (`as u32`, `.ceil()`) ou cruza um limiar (`> 0.5`), um bit muda um
caractere. Todo passo que era f32 lá passa por `Math.fround` aqui.

### O que está verificado, e o que não está

```sh
make test      # tudo
make check     # o LCG e as divisões de 64 bits contra o BigInt do Node
make diff      # a saída de hoje contra as fixtures de test/frames/
make verify    # as fixtures contra o motor de JS do QML
make glyphs    # os sete ícones da barra contra a fonte instalada
```

- **Verificado:** a aritmética de 64 bits feita à mão bate com `BigInt` em 14
  seeds × 4000 passos; o motor do QML produz os 64 frames de referência
  caractere por caractere idênticos aos do Node; e os sete glifos da barra são
  os desenhos certos na fonte instalada — `make glyphs` existe porque a primeira
  versão pôs um logo de open source no lugar da muda, sem erro nenhum.
- **Não verificado:** o `diff` contra o **Ganja-TUI de verdade**. Isso precisa de
  uma máquina com `cargo`, rodando o TUI com as mesmas 8 seeds e os mesmos 8
  dias e comparando com `test/frames/`. Enquanto esse passo não acontecer, a
  fidelidade aqui é **declarada, não comprovada**. Ver `test/README.md`.

---

## Divergências deliberadas

Seis, todas descendo da mesma decisão: isto mora numa barra, não numa janela
que você abre por um minuto. Estão marcadas com `DIVERGE` no código.

1. **O relógio é de sessão, não de parede.** `Utc::now() - last_tick` nunca é
   usado para recuperar o intervalo em que o plugin não existia.
2. **`days_alive` tem piso 1.** O TUI calcula `total_hours / 24`, o que dá dia 0
   no começo — e `calculate_stage(0)` cai no ramo `_`, "pronta para colher". Lá
   isso dura meio segundo; a 40x duraria 36 minutos, com um broto anunciando
   colheita.
3. **O auto-cuidado não vem ligado.** No TUI a planta se rega sozinha porque a
   ideia é assistir; aqui regar é o que você faz, e uma planta que se rega
   sozinha faz do `w` um botão que não liga nada. O comportamento do TUI
   continua inteiro atrás do `a`, com os mesmos limiares.
4. **Colher é o comportamento, não uma opção.** Por isso não existe a tecla `a`
   do TUI: não há auto-harvest para alternar.
5. **O Rainbow cicla o matiz por frame.** No Rust isso é um TODO e o matiz está
   parado; sem o ciclo o modo é só "cores diferentes", não psicodélico.
6. **A planta nasce no dia 5, e regar para no topo da faixa ótima.** O tronco só
   existe a partir de `day * growth_rate >= 1`, então os dias 1 a 4 são um vaso
   com terra e nada mais — três segundos no TUI, três horas aqui, e justo as
   três primeiras depois de instalar. E `calculate_health` chama de crítica a
   planta com água acima de 95: no TUI o auto-cuidado nunca chega lá, aqui dois
   cliques chegariam, e um botão que pune quem o aperta está errado.

Uma coisa a mais que o TUI não tem: as três cores que lá eram nomes de ANSI
(`Color::Green` no caule de muda, `Color::DarkGray`, `Color::Yellow` nos
primeiros cálices) precisaram virar RGB, porque nome de ANSI não carrega cor —
quem decide é o terminal. Estão em `Palette.js`, escolhidas dentro da própria
paleta do Ganja.

---

## Custo

| estado | custo |
|---|---|
| shell carregado, overlay fechado | 1 Timer de 60 s, aritmética pura, 0 IO |
| overlay aberto | 10 quadros/s: 70×28 células + a animação |
| ação do usuário | 1 escrita atômica de JSON |
| boot do shell | 1 `cat` do save |
| a cada 10 min, ou quando o estágio vira | 1 escrita atômica de JSON |

A última linha é um acréscimo à SPEC, que pedia escrita só em ação do usuário.
Sem ela, um shell que reinicia sem descarregar direito perde as horas
acumuladas — que é o único bem que esta planta tem.

Não há `inotifywait` aqui, ao contrário do `zed.quadro`: ninguém escreve no save
pelas costas exceto o próprio TUI, e para isso já existe a releitura ao abrir.

---

## Arquivos

```
manifest.json    schemaVersion 1, kinds bar-widget + overlay, timeScale, careScale
qmldir           singleton Grow + Room (assim que existe qmldir, ele é a lista)
Grow.qml         estado, save, relógio, simulação  (a metade acordada)
BarWidget.qml    o glifo, o alerta, o tooltip
Ganja.qml        as janelas, as teclas, o IPC
Room.qml         o que se vê por dentro, igual nas duas janelas
Art.js           porta de ascii/art.rs - SimpleRng, PlantStructure, render
Palette.js       porta de ui/colors.rs - as quatro paletas
Strains.js       gerado de strains.json por `make strains`
test/            fixtures de frame, o harness de Node e o de QML
```

`Strains.js` é gerado, não editado à mão:

```sh
make strains GANJA_TUI=~/Projetos/Ganja-TUI
```

---

MIT, como o Ganja-TUI. A planta é do ZeD; a barra é do Omarchy.
