# Wardlight: limites dos mods para terreno

24/11/2026

## Resumo

Um mod consegue deixar o terreno mais natural dentro do mundo atual, mas **não consegue** ter mundo infinito, altura maior nem mar no nível 0: esses três limites estão no motor do jogo (`game/world.c`), fora do alcance dos scripts.

O pedido do autor era um terreno inspirado na forma do relevo e da hidrografia reais (serras, erosão, rios até o mar, lagos), sem usar dados reais. Além disso: altura positiva e negativa bem maiores, nível do mar em 0, largura "infinita", mar e litoral.

Este documento junta o que o código do jogo permite hoje a um mod, para levar à sessão integradora. O repositório `wardlight` foi só lido; nada foi mudado lá.

## Limites do mundo

O mundo tem borda, 48 blocos de altura e mar fixo em 15; um mod não muda nenhum desses números.

| Limite | Valor hoje | Onde está | Um mod muda? |
| --- | --- | --- | --- |
| Largura do mundo | 128, 256 ou 384 blocos (8, 16 ou 24 chunks de 16), escolhida ao criar o mundo | `MAX_CHUNKS 24` (`world.c`); `SIZES = listOf(8, 16, 24)` (`BlocksWorlds.kt`) | Não |
| Borda | `set_block` e `teleport` ignoram x ou z fora de 0 até a largura | `api_set_block`, `l_teleport` (`scripts.c`) | Não |
| Altura total | 48 blocos (`WY 48`), y de 0 a 47 | `world.c` | Não |
| Altura que um mod escreve | y de 1 a 47 (y = 0 é o fundo, intocável) | `api_set_block` (`scripts.c`) | Não |
| Altura negativa | Não existe; os blocos são guardados por y a partir de 0 | `Column` (`world.c`) | Não |
| Nível do mar | 15 (`WATER_LEVEL`); a geração põe água até ele | `world.c` | Não (o mod pode pôr `water` em qualquer y, mas o jogo continua gerando até 15) |
| Geração do terreno | Feita pelo jogo, da semente, quando algo toca a coluna (`column_from_seed`, `terrain_height`) | `world.c` | Não; só remodela depois |
| Lugar onde o mod age | O lugar (dimensão) do primeiro jogador | `game_for(gm, first)` antes de `scripts_tick` (`step.c`) | Não |
| Estruturas protegidas | `set_block` recusa a estrutura de um laboratório | `block_may_change` (`inventory.c`) | Não |

## API de scripts

Um script só reage a eventos e troca blocos um a um, com um teto de 2 milhões de passos por evento; não há evento de geração nem como guardar dados no save.

**Eventos** (`scripts.c`): `on_start()`, `on_tick(dt)` a cada quadro sem pausa, `on_break`, `on_place`, `on_cut` (x, y, z, coisa), `on_eat(coisa)`, `on_craft(coisa, quantas)`. Nenhum avisa quando uma coluna é gerada ou carregada.

**Chamadas:** `get_block`, `set_block`, `get_form`, `set_form`, `player`, `teleport`, `count`, `give`, `take`, `health`, `food`, `warmth`, `time`, `day`, `say`, `set` (`hunger`, `cold`, `walk`, `jump`) e `replace` (`hunger`, `cold`). Nenhuma lê a altura do terreno, a semente, o tamanho do mundo ou o nível do mar.

| Limite | Lua (`init.lua`) | WebAssembly (`*.wasm`) |
| --- | --- | --- |
| Memória por mod | 32 MB (`SCRIPT_MEMORY`) | 64 MB (`WASM_MEMORY`) |
| Custo por evento | 2 milhões de instruções (`SCRIPT_STEPS`); passou, o jogo para o script ("the script took too long") | 2 milhões de chamadas e voltas de laço (`WASM_STEPS`) |
| Bibliotecas | `table`, `string`, `math`, `utf8`, `coroutine`; sem `io`, `os`, `package`, `debug`, `load`, `require` | Só as chamadas do módulo `blocks` |

**Consequências para um mod de terreno:**

- **Guardar o progresso:** não há como salvar dados do script. Para saber que uma área já foi remodelada, o mod teria que marcar no próprio mundo, com um bloco num lugar escondido.
- **Trabalhar aos poucos:** a remodelação tem que ser dividida em `on_tick`, alguns milhares de blocos por quadro, para caber no teto e não pesar no celular.
- **Jogo com outras pessoas:** os mods rodam só no host, e `on_tick` age pelo primeiro jogador e no lugar dele. Os outros recebem os blocos mudados pela rede (`set_block` marca o chunk em `chunk_news`).
- **Construções:** `set_block` não pergunta `land_lets` (terras com dono). Um mod de terreno teria que se cuidar sozinho para não apagar construções.

## O que um mod de terreno consegue hoje

Nos limites atuais, um mod remodela o terreno já gerado: em 384 × 384 blocos dá uma paisagem pequena com relevo, rio e litoral, com no máximo 32 blocos acima do mar.

- **Relevo:** uma serra ou morros de até 32 blocos acima do mar (de 15 a 47), vales e encostas suavizadas, pedra exposta onde é íngreme.
- **Rios e lagos:** um rio que nasce no alto e desce até um lago ou o mar no nível 15, com margens de areia.
- **Litoral:** mar numa parte do mapa, com praia e fundo de até 14 blocos (y = 1 a 15).
- **Vegetação:** árvores mais densas nos vales e mais raras no alto.
- **Preparação antes de jogar:** segurar o jogador (`set("walk", 0)`, `set("jump", 0)`), remodelar em volta durante alguns `on_tick` com uma mensagem de progresso (`say`) e soltá-lo depois. Não há tela de carregamento de verdade.

**O que fica de fora:** o jogo continua gerando o terreno original antes, e cavernas e minérios dele podem ser cortados pela remodelação. Um mundo de 128 × 128 (o menor) dá pouco espaço para uma rede de rios.

## O que precisa mudar no jogo

O pedido completo depende de seis mudanças no motor, a maioria da Sessão B; a ordem abaixo é uma sugestão para a sessão integradora decidir.

| Mudança | O que envolve | Sessão (pelo `CLAUDE.md`) |
| --- | --- | --- |
| Mundo sem borda | Trocar a grade fixa de até 24 × 24 chunks por uma tabela que cresce e descartar o que fica longe; é o passo 3 em aberto do roadmap ("mundos maiores que 24 x 24"). Teto de 300 MB no celular (`memory.c`) | B (mundo e memória) |
| Altura maior, com y negativo | `Column` guarda 16 × 48 × 16 de uma vez; passaria a pedaços verticais. `WY` aparece em uns 120 lugares do jogo. Novo layout de save | B; save novo pega o próximo HPBW livre (28, pelo `CLAUDE.md`) |
| Mar no nível 0 | Mudar `WATER_LEVEL` e o que depende dele; mundos antigos têm que continuar abrindo, deslocados | B |
| Gerador novo | Continentes e oceanos, serras com erosão, rios até o mar, lagos; calculado por região a partir da semente, igual para todos os jogadores | B (`world.c`) |
| Chunks longe mais simples (LOD) | Com visão maior e serras altas, o Galaxy M12 precisa disso; item em aberto no roadmap (pergunta 37.4) | Arte |
| Rede | Mapas maiores e y negativo mexem no envio de chunks (`net.c`); pode pedir nova `NET_VERSION` | A |

**Para mods** (mesmo sem as mudanças acima), ajudariam:

- Um evento `on_generate(chunk)`, para o mod mudar a coluna quando ela é gerada em vez de remodelar depois.
- Chamadas que leiam o tamanho do mundo, o nível do mar, a altura e a semente.
- Um jeito de o script guardar dados pequenos no save.

## Perguntas em aberto e verificação

Tudo acima foi lido no código do `wardlight` (último commit `78cffb4`, 24/11/2026); nada foi rodado no jogo.

- [ ] Quantos blocos por quadro `set_block` aguenta no Galaxy M12 sem travar? (Cada um refaz a malha do chunk; só um teste no aparelho diz.)
- [ ] A água posta por um mod escorre ou fica parada? Não achei regra de água que escorre no código; falta confirmar no jogo.
- [ ] `set_block` longe do jogador gera a coluna da semente antes de trocar o bloco? Pelo código, sim (`column_from_seed` quando algo toca a coluna); falta medir o custo.
- [ ] O mundo sem borda e a altura maior cabem no teto de 300 MB do celular? Depende do desenho da Sessão B.
- [ ] A sessão integradora prefere abrir a API de mods (`on_generate`) antes ou depois das mudanças no motor?

Arquivos lidos no `wardlight`: `game/world.c`, `game/scripts.c`, `game/scripts_wasm.c`, `game/step.c`, `game/blocks.c`, `app/src/main/kotlin/io/github/paviogames/wardlight/BlocksWorlds.kt`, `app/src/main/kotlin/io/github/paviogames/wardlight/BlocksSession.kt`, `docs/roadmap.md`, `CLAUDE.md`.
