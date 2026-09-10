#!/usr/bin/env sh

# Quem o Hyprland carrega. Esta linha e a inversao de posse inteira.
#
# POR QUE AQUI E NAO NO environment.d. A primeira tentativa (09/09/2026) pos
# isto em ~/.config/environment.d/61-hyprland-config.conf e o boot mostrou
# HYPRLAND_CONFIG=.../hyde.lua mesmo assim. O motivo: o uwsm monta o ambiente
# do compositor executando os arquivos daqui num shell que NAO enxerga o que o
# environment.d definiu, e depois exporta o resultado por cima do ambiente do
# gerenciador. Entao o `${HYPRLAND_CONFIG:-...}` do 00-hyde.sh avaliava com a
# variavel vazia e o default dele ganhava.
#
# No MESMO mecanismo a conta muda: os arquivos sao lidos em ordem, "00-guest"
# vem antes de "00-hyde", e o `:-` deles preserva o que ja estiver definido.
#
# Para voltar ao HyDE: apague este arquivo e refaca o login. Nao precisa mexer
# em mais nada - o hyprland.lua tem dois papeis e volta a ser a camada de
# override quando quem carrega e o hyde.lua.
HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.lua"
export HYPRLAND_CONFIG
