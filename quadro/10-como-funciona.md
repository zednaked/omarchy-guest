---
title: como funciona
mode: prose
---

# Este quadro é uma pasta

Cada arquivo `.md` em `~/.local/share/omarchy-guest/quadro/` vira uma aba, em
ordem alfabética. O prefixo numérico serve só pra ordenar.

Não existe botão de criar documento aqui dentro, e isso é de propósito. O
sentido é o contrário: **eu escrevo um arquivo pelo terminal e ele aparece**,
igual à linha de voz que eu já mando no fim de cada resposta. A pasta fica sendo
observada, então nem precisa recarregar.

# Dois modos

**prose** — Markdown lido. Títulos, listas, negrito, código, régua. Um
subconjunto pequeno de propósito: isso aqui é superfície de leitura, não
navegador.

**graph** — um bloco cercado que vira grafo com física. O tamanho de cada ponto
sai do **número de ligações**, então os centros de gravidade aparecem sozinhos,
sem ninguém declarar quem é importante.

# O bloco de grafo

    group entrada  #FFAA00  ponto de entrada
    [entrada] HYPRLAND_CONFIG :: variável :: Decide o que o Hyprland carrega.
      ! Sem mover isto, apagar o host deixa o login sem sessão.
    HYPRLAND_CONFIG -> hyde.lua

Uma linha começando com `!` vira o risco daquele ponto: anel vermelho no grafo e
bloco marcado no inspetor. É pra "o que quebra", não pra ênfase — um quadro onde
tudo é vermelho não diz nada.

# Por que Markdown e não uma interface

Porque os arquivos continuam legíveis sem o plugin, entram em diff, e
sobrevivem a ele. Se um dia o Quadro sumir, o que a gente conversou continua
sendo texto numa pasta.

# Atalhos

- **Tab** ou setas — troca de aba
- **hover** — inspeciona
- **clique** — trava a seleção
- **arrastar** — move o ponto
- **R** — relê a pasta
- **Esc** — solta a seleção, ou fecha
