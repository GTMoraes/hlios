# hlios: Half-Life no iPhone

App de iPhone que roda **Half-Life**, **Opposing Force** e **Blue Shift** (e, quando a build traz,
**Counter-Strike 1.6** e **Deathmatch Classic**) com o [Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs),
um motor de código aberto compatível com o GoldSrc. O app sai pelo GitHub Actions direto no TestFlight,
sem Mac.

**Nada da Valve neste repositório.** Os arquivos dos jogos vêm da Steam e só existem no iPhone. O ícone
vem do segredo `APP_ICON_PNG`. O `.gitignore` bloqueia as pastas dos jogos, `.png` e `.ico`.

## Peças

| Peça | De onde vem |
|---|---|
| Motor | Xash3D FWGS no commit de `versoes.env`, com as mudanças da pasta `motor/` |
| Half-Life e Blue Shift | hlsdk-portable, ramo `mobile_hacks` (uma biblioteca só, com o modo Blue Shift) |
| Opposing Force | hlsdk-portable, ramo `opfor` |
| Deathmatch Classic | hlsdk-portable, ramo `dmc` (não tem bots: offline é mapa vazio) |
| Counter-Strike 1.6 | cs16-client, com servidor (ReGameDLL) e bots. **Opcional**: se não compilar, o app sai sem ele |
| SDL2 | 2.32.10, compilado no runner (a mesma versão do CI do Xash) |

### Mudanças no motor (`motor/`)

1. **`0001-ios-bibliotecas-em-frameworks.patch`**: o App Store Connect recusa `.dylib` solto dentro de um
   app (ITMS-90171). O `scripts/embrulhar.py` põe cada biblioteca em `Frameworks/<nome>.framework`, e o
   patch faz o motor procurar lá (`engine/platform/posix/lib_posix.c`; `platform.h` também, para a checagem
   de bibliotecas que o motor faz na abertura).
   - Regra do nome, igual nos dois lados: caminho dentro do app, sem o `.dylib`, com `/` trocado por `__` e
     cada caractere fora de `[A-Za-z0-9_-]` trocado por `_`.
   - Exemplo: `valve/cl_dlls/client_ios_arm64.dylib` vira `Frameworks/valve__cl_dlls__client_ios_arm64.framework`.
   - Jogo sem biblioteca própria usa a do `valve`. É assim que o Blue Shift roda (com `-dll @hl`).
2. **`0002-ios-fechar-o-app-ao-sair.patch`**: no iOS, quando o motor termina (Quit ou travamento), o SDL deixa o
   app aberto numa tela preta. O patch chama `IOS_Encerrar` (no `launchdialog.m`), que manda o app para a tela
   inicial do iPhone com a animação normal, pelo `suspend` do `UIApplication`, e fecha o app 1 s depois. O
   `suspend` não é uma função pública da Apple: se o envio para o TestFlight for recusado por causa dele, é só
   trocar por um `exit` direto. Ao abrir de novo, volta a tela de escolha.
3. **`0003-ios-toque-no-olhar-atira.patch`**: cria a cvar `touch_look_fire`. Ligada, a área de olhar (lado
   direito) também atira: um toque rápido com o dedo quase parado dá um disparo da primária, e toque duplo e
   segurar (segundo toque até 0,3 s depois do primeiro) atira sem parar enquanto o dedo fica na tela, mirando
   ao arrastar. O que conta como toque fica em `touch_look_fire_time` (tempo máximo, padrão 0,18 s) e
   `touch_look_fire_move` (quanto o dedo pode andar, em fração da tela, padrão 0,005). Toque que cai num botão
   (pulo, agachar etc.) não conta como tiro. O disparo do toque rápido sai quando o dedo solta. Vale para
   todos os jogos.
4. **`0004-ios-fov-das-armas.patch`**: cria a cvar `r_viewmodel_fov`, o campo de visão só da arma em primeira
   pessoa, na mesma escala do `default_fov` (vale para 4:3, e a tela larga só abre os lados). `0` usa o mesmo
   do mundo, como o original (abaixo de 10 também). A arma é desenhada com uma projeção própria e depois volta a
   do mundo. Cria também a cvar `fov_arma`, o campo de visão só da arma na mão: no console, com a arma na mão,
   `fov_arma 60` (e `fov_arma 0` volta ao `r_viewmodel_fov`). Fica em `fov_armas.txt`, na pasta do jogo, por
   modelo (o nome e o tamanho do arquivo, então um modelo trocado numa pasta `_addon` tem o seu). Ao trocar de
   arma, a cvar passa a mostrar o valor da nova. Do mesmo jeito, `arma_frente`, `arma_lado` e `arma_altura`
   mudam a posição da arma na mão (em unidades do jogo, junto com a câmera; só o desenho, a mira e os tiros
   continuam iguais), e o comando `ajustar_arma <frente|lado|altura|fov> <passo>` (ou `ajustar_arma zerar`)
   soma um passo e mostra os valores no meio da tela. Uma linha `modelo:*` (as que o app copia de outro jogo)
   vale para o modelo com esse nome quando não tem a linha do modelo exato; zerar uma arma assim grava a linha
   exata zerada, para a copiada não voltar. A posição vale também para os eventos da arma (o clarão do tiro
   nasce onde a arma está), e a cvar `r_viewmodel_escala` (o motor grava, não é para mudar) diz ao cliente
   quanto acertar os pontos da arma para o FOV dela (patch `jogos/*/0007`).
5. **`0005-ios-fov-no-menu-do-jogo.patch`** (no `3rdparty/mainui`, o menu do jogo): três barras em
   Configuration › Video › Video options, à direita da imagem de teste: Field of view (`default_fov`), Weapon
   FOV (`r_viewmodel_fov`) e Weapon in hand FOV (`fov_arma`, só com um jogo aberto). Mudam na hora e mostram o
   valor; o ponto mais à esquerda das duas das armas é "igual ao do mundo" e "igual ao Weapon FOV".
6. **`0006-ios-botoes-padrao.patch`**: o padrão dos botões de toque (o de um jogo sem `touch.cfg` e o do Reset
   no menu Touch) passa a vir do `touch_padrao.cfg` da pasta do jogo, quando ele existe. O app grava esse
   arquivo no HL, no OF e no BS a cada abertura.
7. **`launchdialog.m`**: tela inicial com a escolha do jogo e as opções, no lugar da caixa de texto do port.
   Compilado sem ARC, como o original.

### Mudanças nos jogos (`jogos/`)

- **`hl/0001-mira-assistida.patch`** e **`opfor/0001-mira-assistida.patch`** (Half-Life e Blue Shift usam a
  mesma biblioteca): criam a cvar `sv_aim_assist`. `0` é o jogo original. `1`, `2` e `3` ligam a mira
  assistida também no Difícil (o original desliga nele), multiplicam o alcance dela por 1, 2 ou 3 (pistola e
  Python: 10° no original; MP5 e escopeta: 5°) e pintam a mira de vermelho quando o tiro vai pegar num alvo.
  Valem mesmo com `sv_aim` e `sv_allow_autoaim` desligados (no Xash o `sv_allow_autoaim` vem desligado).
  Só muda a mira: dano, inimigos e munição do Difícil ficam iguais.
- **`0002-mira-sem-amigos.patch`**: com a `sv_aim_assist` ligada, a mira só puxa para quem está contra o
  jogador (inclusive um aliado provocado) ou para quem ele detesta e não é aliado dele. Cientistas, guardas,
  soldados aliados do Opposing Force e caixas quebráveis ficam de fora; um aliado na frente não deixa a mira
  vermelha.
- **`0003-guardar-arma.patch`**: `impulse 200` guarda a arma (animação de guardar e o modelo some) ou saca de
  novo. Guardada, ela não atira, não recarrega, não bate e não lança nada; a lanterna e o "usar" continuam.
  Escolher qualquer arma também saca. O estado vai junto no save.
- **`0004-guardar-animacao.patch`**: ao guardar, a arma toca a animação de guardar dela (na pistola e na escopeta,
  a que o modelo tem e o original não usava) e desce para fora da tela em 0,45 s, depois some. Vale para
  qualquer modelo, inclusive os trocados. Mexe também no cliente (`cl_dll/view.cpp` e `hl_weapons.cpp`): o
  servidor avisa pela mensagem `HlGuarda`, e o cliente não prevê tiro com a arma guardada. Sacar usa a
  animação de sacar de cada arma.
- **`0005-guardar-descida.patch`**: a pistola deixa de tocar a animação de guardar (a dos modelos dela é ruim) e
  só desce. As armas que só descem (pistola, MP5, hivehand, snark) caem 100 unidades em 0,3 s, acelerando, e
  só somem fora da tela; as que têm animação de guardar continuam como na 0004. Depois de carregar um save com
  a arma guardada, ela já aparece escondida. A descida segue a câmera (`pparams->up`), então vai para baixo na
  tela olhando em qualquer direção.
- **`0006-sacar-animacao.patch`**: meio segundo depois de sacar, o cliente não prevê a arma. Com dados de um
  quadro atrasado, ele achava a arma parada e trocava a animação de sacar pela de parada, e a arma surgia de
  repente.
- **`0007-clarao-na-arma.patch`**: com o FOV próprio da arma na mão, o clarão do tiro e os raios (gauss, egon)
  saem dos pontos da arma, mas são desenhados com a lente do mundo. O cliente traz esses pontos para mais perto
  da câmera, na mesma linha de visão, na proporção que o motor passa em `r_viewmodel_escala`: eles caem na boca
  do cano e o clarão cresce junto com a arma. A menos de 6 unidades da câmera ele seria cortado; aí para ali e
  se afasta do centro da vista o que falta, ficando no lugar certo e um pouco menor.
- O `scripts/compilar-jogos.sh` aplica `jogos/<nome>/*.patch`, em ordem, depois de baixar cada hlsdk.

### Mudança no Counter-Strike (`cs16/`)

- **`0001-regamedll-filesystem-ios.patch`**: o servidor do CS (ReGameDLL) abre o `filesystem_stdio` por conta
  própria, pelo nome solto. No iPhone ele está em `Frameworks/`; sem o patch o servidor fica sem sistema de
  arquivos e cai ao montar a partida (`signal 11 at 0x0` logo depois de "Executing listen server config file").
- O YaPB (bot à parte) não compila para iPhone e fica de fora; os bots são os do próprio CS (`bot_add`).

### Por que o Xcode 26

Com o SDK do iOS 27, app que não adota o ciclo de vida UIScene não abre, e o SDL2 não adota. Compilado
com o Xcode 26 (SDK 26), o app abre no iOS 27. Quando a Apple passar a exigir o SDK 27 nos envios
(costuma ser em abril), o caminho é trocar para o SDL3, que já tem UIScene e que o motor suporta.
O `scripts/escolher-xcode.sh` para a build com um erro claro se o runner não tiver mais o Xcode 26.

## Build

- **Cada push gera uma build** e manda ao TestFlight (mudança só em `.md` não gera). Sem push:
  Actions › Gerar app (TestFlight) › Run workflow.
- **Número da build** = número da execução do workflow. Não renomeie o `build-ipa.yml`, ou o contador zera.
- **Artifacts** de cada execução:
  - `HalfLife-ipa-N`: IPA com assinatura provisória (só instala reassinado, por exemplo pelo LiveContainer);
  - `logs-N`: todos os logs da build.
- **Segredos** (Settings › Secrets and variables › Actions): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
  `APPLE_TEAM_ID` (os mesmos do nfios) e `APP_ICON_PNG` (o ícone em base64; sem ele sai um ícone simples).
- **Assinatura**: a gerenciada pela Apple, como no nfios. O app é montado à mão (o motor compila com waf e
  cmake, não com projeto Xcode), vira um `.xcarchive` e vai pelo `xcodebuild -exportArchive`.

Passos do workflow (`scripts/`):

| Script | Faz |
|---|---|
| `escolher-xcode.sh` | escolhe o Xcode 26 mais novo |
| `sdl2.sh` | compila o SDL2 para iPhone (fica em cache) |
| `baixar-motor.sh` | baixa o Xash no commit fixado e aplica `motor/` |
| `compilar-motor.sh` | `waf configure --enable-lto --ios`, `build` e `install` |
| `compilar-jogos.sh` | hlsdk-portable: mobile_hacks, opfor e dmc (em Debug, como o script de iOS do Xash), com `jogos/` |
| `compilar-cs16.sh` | cs16-client (pode falhar sem parar a build) |
| `montar-app.sh` | junta tudo, embrulha as bibliotecas, ícone, Info.plist, assinatura provisória e IPA |
| `enviar-testflight.sh` | monta o `.xcarchive` e envia |
| `resumo-erros.sh` | junta as linhas de erro dos logs, quando a build falha |

### Dia a dia (PowerShell, na pasta do projeto)

```powershell
git add -A
git commit -m "<o que mudou>"
git push
```

## No iPhone

### Copiar os jogos

Da pasta da Steam (`Steam\steamapps\common\Half-Life`) para **Arquivos › No Meu iPhone › Half-Life**:

| Pasta | Jogo |
|---|---|
| `valve` | Half-Life (obrigatória: as outras dependem dela) |
| `gearbox` | Opposing Force |
| `bshift` | Blue Shift |
| `cstrike` | Counter-Strike 1.6 |
| `dmc` | Deathmatch Classic |
| `valve_hd`, `gearbox_hd`, `bshift_hd` | opcionais: modelos em alta definição |

- Jeito simples: zipar as pastas no PC, mandar pelo Tailscale (Taildrop), descompactar no app Arquivos e
  mover para a pasta do Half-Life.
- Versão dos arquivos: a atual da Steam (25th Anniversary). Se algum jogo reclamar, a antiga fica em
  Propriedades › Betas › `steam_legacy`.
- Os saves ficam na pasta `save` de cada jogo. O log fica em `engine.log`, na pasta do app.

### Tela inicial

- **Jogos**: só aparecem os que a build trouxe. Os que ainda não foram copiados ficam apagados, com o nome
  da pasta que falta. A lista se atualiza ao voltar do app Arquivos.
- **Mira pelo giroscópio**: `gyro_enable`.
- **Toque no olhar atira**: Desligado, Rigoroso (padrão: até 0,18 s e 0,5% da tela) ou Solto (a regra até a
  0.1.10: até 0,25 s e 2% da tela). Vira `touch_look_fire`, `touch_look_fire_time` e `touch_look_fire_move`.
- **Som no modo silencioso**: o som toca mesmo com o iPhone no silencioso.
- **Log detalhado (diagnóstico)**: `-dev 2`. Mais informação no `engine.log` e mensagens na tela no
  carregamento.
- **Modelos HD** e **Conteúdo extra (pastas _addon)**: `fs_mount_hd` e `fs_mount_addon`. O app grava os dois
  no `vfs.cfg` do jogo antes de abrir, então valem já na mesma abertura. Ligados por padrão. As pastas
  `<jogo>_addon` (por exemplo, armas trocadas) ficam ao lado de `valve`, `gearbox` e `bshift` e passam na
  frente das `_hd` e das originais.
- **Campo de visão** (60 a 120) e **Campo de visão das armas** (10 a 120, ou "igual ao do mundo"): 90 é o
  original. Viram `default_fov` e `r_viewmodel_fov`. Menos que 90 aproxima (alvos maiores, menos coisa nas
  laterais); na arma, menos que 90 é uma lente que a aumenta a partir do centro da tela. Cada jogo guarda os
  seus no `config.cfg`, e eles também mudam no menu do jogo: as barras mostram os do último jogo aberto e só
  vão para o jogo quando alguém mexe nelas (valem para o próximo jogo aberto).
- **Abrir no último save (HL, OF e BS)**: desligado por padrão. Ligado, o app procura o `.sav` mais novo na
  pasta `save` do jogo (os de nome, os automáticos e o rápido) e passa `+load <nome>` no fim da linha de
  comando. Sem save, abre o menu normal. A pasta pode se chamar `save` ou `SAVE` (a que vem da Steam). O que o
  app decidiu fica no `engine.log`, numa linha que começa com `hlios:`.
- **Botões padrão (HL, OF e BS)**: o layout da 0.1.15, com o 6 e o 7 do OF logo depois do 5 e os
  botões de ajustar a arma. Vale num jogo sem `touch.cfg` e no Reset do menu Touch.
- **Copiar do Half-Life para o OF e o BS**: botão na tela inicial que pergunta o que copiar (Botões, Ajustes
  das armas ou Os dois). Botões: copia o `valve/touch.cfg` para `gearbox` e `bshift`. Ajustes das armas: copia
  o `valve/fov_armas.txt` como linhas `modelo:*` (as mãos mudam de jogo para jogo, e o arquivo do modelo
  junto), substituindo as armas de mesmo nome e mantendo as outras; se o HL tem dois ajustes para o mesmo nome,
  vai o do modelo que o HL usa hoje (pastas `_addon` e `_hd` ligadas ou não). O de antes fica como
  `touch-antigo.cfg` e `fov_armas-antigo.txt` (ou `-antigo-2` e assim por diante, sem apagar nenhum).
- **Ajustar a arma (HL, OF e BS)**: o botão laranja AJUSTAR ARMA mostra e esconde um bloco de botões no meio da
  tela: PERTO, LONGE, SUBIR, DESCER, ESQ., DIR. (0,5 unidade por toque), FOV - e FOV + (2 por toque) e ZERAR.
  Tudo vale para a arma na mão e fica salvo por modelo. O botão AJUSTAR ARMA dá para esconder no editor.
- **Console**: o app sempre passa `-console`, e põe um botão de teclado no alto da tela (`"console"`,
  `toggleconsole`) em todos os jogos.
- **Mira assistida**: Desligada, Normal, Forte (padrão) ou Muito forte, vira o `sv_aim_assist` 0 a 3 (só no
  HL, no OF e no BS).
- **Argumentos extras**: vão no fim da linha de comando, e vencem as opções acima. O botão abre uma janelinha
  acima do teclado.
- **Trocar de jogo**: Quit no menu do jogo (o app fecha) e abrir o app de novo (no iOS o motor não reinicia sozinho).
- **Pulo longo**: todo jogo ganha um botão laranja de pulo (à esquerda das miras) que agacha e pula ao mesmo
  tempo (`+pulolongo`). O app grava `hlios.cfg` na pasta do jogo e acrescenta o botão ao `touch.cfg` se ele não
  estiver lá. Dá para mover e redimensionar no editor (engrenagem), e a posição fica. Até a 0.1.3 o botão
  saía travado (flag 2, "não editável"); a partir da 0.1.4 o app tira essa marca sozinho, sem mudar a posição.
- **Guardar a arma**: no HL, no OF e no BS o app acrescenta também um botão azul no alto (`"guardar"`,
  `impulse 200`), no lugar do spray (que só aparece no multiplayer). Também dá para mover no editor.
- **Números das armas**: no HL, no OF e no BS o app põe botões fixos com os números (`"num1"` a `"num5"`, e
  `"num6"` e `"num7"` no OF, que tem 7 grupos), numa fileira no alto da tela, e liga `hud_fastswitch 1` para o
  toque trocar de arma direto. Tocar de novo no mesmo número passa para a próxima arma do grupo.
- Sempre vai junto: `-game <pasta> -log engine.log +voice_enable 0 +gyro_enable 0|1 +touch_look_fire 0|1 +touch_look_fire_time +touch_look_fire_move +hud_fastswitch 1 -console +sv_aim_assist 0-3 +exec hlios.cfg`, e
  `-dll @hl` no Blue Shift. Sem chat de voz, o app não pede o microfone.
- O `engine.log` é refeito a cada abertura: depois de um travamento, pegue o log **antes** de abrir o app de novo.

### Quando algo der errado

- **Build**: artifact `logs-N` e o passo "Resumo dos erros" do Actions.
- **No iPhone**: `engine.log` na pasta do app (Arquivos), com o "Log detalhado" ligado.

## Atualizar o Xash ou os jogos

1. Trocar o commit em `versoes.env` (e subir a `APP_VERSAO`).
2. Conferir se o patch aplica: `git apply --check motor/0001-ios-bibliotecas-em-frameworks.patch` num clone
   do Xash nesse commit.
3. Se o `engine/platform/ios/launchdialog.m` original mudou, conferir se ele ainda exporta as mesmas funções
   que o nosso: `IOS_GetDocsDir`, `IOS_GetExecDir`, `IOS_LaunchDialog`, `IOS_GetArgs`, `IOS_GetUDID` e `IOS_Log`.

## Licenças

Xash3D FWGS: GPLv3. hlsdk-portable: licença do SDK do Half-Life (uso não comercial, para quem tem o jogo).
cs16-client e ReGameDLL: ver os repositórios. Os scripts e patches daqui seguem a GPLv3 do motor.
