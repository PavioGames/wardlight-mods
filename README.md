# Wardlight: mods e pacotes de textura

[English](README.en.md)

Tudo para criar coisas para o Wardlight, à mão ou com uma IA (Claude ou
outra): os modelos, exemplos, as texturas do jogo como base e um verificador.

| Pasta | O que tem |
|---|---|
| `texturas/` | Pacotes de textura. `modelo/` para copiar; `base/` com as texturas do jogo, já um pacote |
| `mods/` | Mods: blocos, itens, receitas, sons e scripts. `modelo/` para copiar; `exemplo/` e `exemplo-wasm/` prontos |
| `nomes.txt` | Os nomes das texturas que um pacote pode trocar |
| `tools/check.py` | Confere um pacote ou mod antes de pôr no jogo |

## Pacote de textura ou mod?

- **Pacote de textura:** só muda a aparência. São só imagens, então é seguro
  por natureza. Um mundo ou servidor pode ter vários, e cada jogador escolhe
  o que usar, ou as texturas do jogo.
- **Mod:** soma ou troca partes do jogo (blocos, itens, receitas, sons,
  scripts). Roda no mundo de quem hospeda.

## Fazer um pacote de textura

1. Copie `texturas/modelo/` para `texturas/<nome-do-pacote>/`.
2. Preencha o `pack.txt`: nome, autor, versão e licença.
3. Escolha a resolução no `pack.txt`: `resolution = 16`, `32`, `64` ou
   `128`. Todas as imagens do pacote têm esse tamanho, quadradas.
4. Para cada desenho que quer trocar, ponha na pasta do pacote um **PNG**
   com o nome de `nomes.txt` (por exemplo `stone.png`, `grass_top.png`,
   `kiln_front.png`). O que não estiver no pacote fica com a textura do
   jogo. Comece pelas de `texturas/base/`. Um bloco de mod usa o nome dele
   (ou `<nome>_top`, `_side`, `_bottom`).
5. Rode `python3 tools/check.py texturas/<nome-do-pacote>`.
6. No jogo: compacte a pasta em .zip e adicione pelo botão **Texturas** do
   mundo (no PC, a pasta vai ao lado do save).

Um pacote tem só o `pack.txt` e os PNGs (e, se quiser, `README.md` e
`LICENSE`). Nada de scripts ou blocos novos: isso é mod.

**Resolução e celular:** cada aparelho mostra o pacote até onde a qualidade
gráfica deixa (Leve até 16, Médio até 32, Bonito a resolução do pacote).
Um pacote de 128 abre num celular simples, só menos nítido.

**Jogando junto:** os pacotes ficam no mundo de quem hospeda. Quem entra vê a
lista e escolhe um, ou as texturas do jogo; recebe só as imagens daquele
pacote, como dado (já reduzidas à qualidade dele), guardadas na memória
enquanto joga. O pacote próprio de
quem entra não vale no jogo de outra pessoa. Quem hospeda pode travar num
pacote só.

> A troca de texturas do jogo e a escolha por jogador estão sendo feitas
> agora; o formato pode mudar um pouco até sair numa atualização.

## Fazer um mod

1. Copie `mods/modelo/` para `mods/<nome-do-mod>/` e preencha o `pack.txt`.
2. Veja `mods/exemplo/`: um bloco novo, uma comida, receitas e um script.

| Arquivo | O que é |
|---|---|
| `pack.txt` | Nome, autor, versão, licença e descrição |
| `things.txt` | Blocos e itens novos |
| `recipes.txt` | Receitas novas, e receitas do jogo tiradas |
| `textures/` | PNG 16×16 dos blocos novos |
| `sounds/` | Sons Ogg que trocam ou somam aos do jogo (`sounds/sfx/break.ogg`...) |
| `init.lua` | Script em Lua |
| `*.wasm` | Scripts compilados para WebAssembly, de qualquer linguagem |

### things.txt

```
[block pedra_brilhante]
name = Glowing stone
name.pt = Pedra brilhante
color = #E0C860
accent = #8A6A20
texture = textures/pedra_brilhante.png
light = 1
tool = pick
tool_blows = 2

[item queijo]
name = Cheese
name.pt = Queijo
kind = food
food = 3
color = #F0D040
```

Blocos: `texture` (ou `texture.top`, `texture.side`, `texture.bottom`),
`light` (ilumina como lâmpada), `transparent`, `solid` (0: atravessa),
`blows` (golpes sem ferramenta; 0: não quebra na mão), `tool` e
`tool_blows`, `drops` (o que dá ao quebrar, por exemplo `stone 2`). Itens:
`kind` (`material`, `tool`, `food`, `clothing`) e `food` (de 0 a 10). Os
dois: `name`, `name.pt`, `color`, `accent`. As coisas do jogo têm nome em
minúsculas (`planks`, `stone`, `wood`, `stick`, `flint`, `knife`,
`raw_meat`, `campfire`...). Cabem uns 40 blocos e 6 itens novos por mundo.

### recipes.txt

```
stone 2, lamp 1 -> pedra_brilhante 2 | tool pick
berries 3 -> roasted_berries 1 | near campfire
remove planks
```

Até duas entradas e uma saída; `tool` pede uma ferramenta, `near` uma
bancada por perto (`kiln`, `stove`, `campfire`). `remove` tira as receitas
do jogo que fazem aquela coisa.

### Scripts

Eventos (todos opcionais): `on_start()`, `on_tick(dt)`,
`on_break(x, y, z, coisa)`, `on_place(x, y, z, coisa)`,
`on_cut(x, y, z, coisa)`, `on_eat(coisa)`, `on_craft(coisa, quantas)`.

Chamadas (em Lua, `blocks.nome(...)`): `get_block`, `set_block`,
`get_form`, `set_form`, `player`, `teleport`, `count`, `give`, `take`,
`health`, `food`, `warmth` (0 a 10), `time` (0 a 1), `day`, `say`,
`set(ajuste, valor)` (`hunger`, `cold`, `walk`, `jump`) e
`replace(sistema)` (`hunger` ou `cold`, para o script cuidar). Em
WebAssembly, veja `mods/exemplo-wasm/src/`.

```lua
function on_eat(coisa)
    if coisa == "queijo" then
        blocks.warmth(blocks.warmth() + 1)
        blocks.say("Que queijo bom")
    end
end
```

## O que um mod pode e não pode

Dentro do jogo, tudo. Fora do jogo, nada: um mod não lê nem apaga arquivos,
não acessa a internet e não roda programas. Lua tem só as bibliotecas
`table`, `string`, `math`, `utf8` e `coroutine`, até 32 MB; WebAssembly, até
64 MB. Um script que trava para só aquele mod. Mods não trazem shaders.

Quando um mod tem erro, o jogo escreve o motivo no relatório da partida
(linhas `blocks: [nome do mod] ...`) e os outros mods continuam.

## Mandar para este repositório

Abra um pull request com a sua pasta em `mods/` ou `texturas/`, depois de
`python3 tools/check.py` passar. Tudo aqui precisa ser original: nada de
personagens, texturas ou sons de outros jogos ou obras.

## Licenças

- Texturas e sons: **CC BY 4.0** ([LICENSE-ART.md](LICENSE-ART.md)): use à
  vontade, dando crédito ao autor.
- Scripts e ferramentas: **GPL-3.0** ([LICENSE](LICENSE)), a mesma do jogo.

Cada `pack.txt` diz o autor e a licença do pacote.
