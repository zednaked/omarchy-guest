# The Quadro document format

A board is a folder of Markdown files. Each file is a tab. That is the whole
model - there is no database, no import step, and nothing to click to create a
document. An agent with shell access drops a `.md` in the folder and it shows up.

    ~/.local/share/omarchy-guest/quadro/*.md

Order is alphabetical, so a numeric prefix controls it: `10-ideia.md`,
`20-maquina.md`.

## Front matter

Optional, and only two keys matter.

```markdown
---
title: Mapa de Posse
mode: graph
---
```

- `title` - the tab label. Falls back to the filename without its prefix.
- `mode` - `graph` or `prose`. Defaults to `prose`, and to `graph` if the file
  contains a graph block.

Everything after the front matter is the document body.

## Prose mode

Plain Markdown, rendered with headings, paragraphs, lists, bold, code spans and
rules. Deliberately a small subset: this is a reading surface, not a browser.

## Graph mode

A fenced block. One statement per line, comments start with `#`.

````markdown
```graph
group entrada  #FFAA00  ponto de entrada
group host     #35C7BC  do host

[entrada] HYPRLAND_CONFIG :: variável :: Decide qual arquivo o Hyprland carrega.
  ! Sem mover isto, apagar o host deixa o próximo login sem sessão.
[host] hyde.lua :: arquivo :: O ponto de entrada de verdade.

HYPRLAND_CONFIG -> hyde.lua
```
````

**`group <id> <#hex> <label>`** declares a cluster: its colour and the name shown
in the legend. Each group gets its own gravity well, so groups separate on their
own without anyone positioning them.

**`[group] Nome :: tipo :: nota`** declares a node. `tipo` is the short kind
shown in the inspector; `nota` is the body text. Both are optional - `[host]
hyde.lua` alone is a valid node.

**A line starting with `!`**, indented under a node, is that node's risk. It
draws a red ring around the point and a marked block in the inspector. Use it
for "what breaks", not for emphasis - a board where everything is red says
nothing.

**`A -> B`** links two nodes by name.

**Size** comes from how many links a node has, so hubs are large without anyone
declaring them. Nothing in the format sets a position: the layout is the
simulation's, and dragging a node only nudges it.

## Why Markdown and not a UI

Because the point is that the agent writes it. A form that a human fills in is a
different product; this one is a surface two parties share, where one of them
happens to work in a terminal. The files are readable without the plugin, they
diff, and they survive it.
