#!/usr/bin/env sh

# A MESMA inversao do 00-guest.sh, para o host que NAO cede a variavel.
#
# Os dois arquivos fazem a mesma coisa e voce instala UM. Qual depende de como
# o seu host define `HYPRLAND_CONFIG`, e a diferenca entre eles e so a ordem:
#
#   00-guest.sh  o host usa `${HYPRLAND_CONFIG:-...}` e cede para quem definiu
#                antes. Ordenar ANTES dele ganha.
#
#   99-guest.sh  o host atribui a variavel sem condicao. Definir antes nao
#                adianta - ele apaga. Ordenar DEPOIS ganha.
#
# COMO SABER QUAL E O SEU. Nao leia so o arquivo em `env-<compositor>.d/`: o
# HyDE, por exemplo, declara `HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-...}"` com o
# `:-` bonitinho, mas ANTES disso ele carrega
# `~/.local/lib/hyde/shell/activate`, e a versao de 08/2026 desse arquivo faz:
#
#       linha   3: [ -n "${HYDE_ACTIVATED:-}" ] && return 0
#       linha   8: HYPRLAND_CONFIG=""              <- zera, sem condicao
#       linha 130: HYPRLAND_CONFIG=$(find_hyde_lua)
#
# Quando o `:-` e avaliado a variavel ja foi zerada, entao o default dele
# sempre ganha. O contrato existe no texto e nao no efeito - foi o que a
# maquina de 16/09/2026 mostrou, com o 00-guest.sh instalado e o boot ainda
# apontando para o hyde.lua.
#
# NAO ADIVINHE: SIMULE. Uma linha responde, e responde antes de voce apostar um
# login. Rode com o arquivo ja instalado:
#
#   (unset HYPRLAND_CONFIG HYDE_ACTIVATED
#    for f in ~/.config/uwsm/env-hyprland.d/*.sh; do . "$f"; done
#    echo "$HYPRLAND_CONFIG")
#
# O `unset HYDE_ACTIVATED` e o que torna a simulacao fiel: sem ele o `activate`
# sai na linha 3 e voce simula um login que nao existe.
#
# POR QUE ORDENAR DEPOIS E SEGURO. O host monta o ambiente dele inteiro - XDG,
# PATH, variaveis de toolkit - e a unica coisa que a gente troca e qual arquivo
# o compositor carrega. Nao edita arquivo nenhum do host e nao mente sobre o
# estado dele (definir `HYDE_ACTIVATED=1` para pular o `activate` tambem
# funcionaria, e custa um ambiente pela metade).
#
# Para voltar ao host: apague este arquivo e refaca o login. O hyprland.lua tem
# dois papeis e volta a ser a camada de override sozinho.
HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.lua"
export HYPRLAND_CONFIG
