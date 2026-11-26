# Relevo natural

Remodela um **mundo novo** com um terreno inspirado na forma do relevo e da
hidrografia reais, sem usar dados reais:

- um litoral ou uma ilha, com plataforma rasa e mar mais fundo longe da costa;
- serras ao longo da costa, com pedra exposta no alto e nas encostas íngremes;
- vales cavados pela erosão;
- rios que nascem no alto, se juntam e descem até o mar, mais largos a cada
  afluente, com margens de areia;
- lagos onde a água fica presa, e árvores mais densas nos vales.

Cada mundo sai diferente; o mesmo mundo sai sempre igual.

## Como funciona

O jogo cria o terreno dele e o mod o refaz em seguida, coluna por coluna, um
pouco a cada quadro. No começo o jogador espera no alto, parado, enquanto a
área em volta fica pronta (uns 4 s num mundo de 128 blocos, uns 22 s num de
384, medidos num PC); depois pode andar, e o resto do mundo continua sendo
feito ao longe.

- **Só mundos novos.** Num mundo já jogado sem o mod, nada muda.
- **Construções ficam.** Faróis, ruínas, a Luz e qualquer bloco que não seja
  terreno natural não são tocados; o terreno se ajusta à altura deles.
- O mod marca o que fez em alguns blocos no canto do mundo, no fundo (x de 0
  a 24, y = 1, z = 0). Não mexa neles: é assim que ele sabe que o mundo já
  está pronto.

## Limites

O mod trabalha dentro dos limites do jogo (`docs/limites-mods-terreno.md`):
largura de 128, 256 ou 384 blocos, 48 de altura e mar no nível 15. Com isso
as serras chegam a uns 30 blocos acima do mar.

Num jogo com outras pessoas, o mod roda no host e segura só o primeiro
jogador; quem entrar antes de terminar pode ver o terreno mudando.

---

**English:** reshapes a new world into a coast or an island with mountain
ranges, valleys carved by erosion, rivers that join on their way down to the
sea, and lakes. The player waits up in the air while the area around them is
made, then the rest is made as they play. Worlds already played without the
mod, and anything built (beacons, ruins), are left alone.
