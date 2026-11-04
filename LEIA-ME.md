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
   app aberto numa tela preta. O patch fecha o app; ao abrir de novo, volta a tela inicial.
3. **`launchdialog.m`**: tela inicial com a escolha do jogo e as opções, no lugar da caixa de texto do port.
   Compilado sem ARC, como o original.

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
| `compilar-jogos.sh` | hlsdk-portable: mobile_hacks, opfor e dmc (em Debug, como o script de iOS do Xash) |
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
- **Som no modo silencioso**: o som toca mesmo com o iPhone no silencioso.
- **Log detalhado (diagnóstico)**: `-dev 2`. Mais informação no `engine.log` e mensagens na tela no
  carregamento.
- **Argumentos extras**: vão no fim da linha de comando. Ex.: `+fs_mount_hd 1` liga os modelos HD (vale a
  partir da abertura seguinte).
- **Trocar de jogo**: Quit no menu do jogo (o app fecha) e abrir o app de novo (no iOS o motor não reinicia sozinho).
- **Pulo longo**: todo jogo ganha um botão laranja de pulo (à esquerda das miras) que agacha e pula ao mesmo
  tempo (`+pulolongo`). O app grava `hlios.cfg` na pasta do jogo e acrescenta o botão ao `touch.cfg` se ele não
  estiver lá. Dá para mover e redimensionar no editor (engrenagem), e a posição fica. Até a 0.1.3 o botão
  saía travado (flag 2, "não editável"); a partir da 0.1.4 o app tira essa marca sozinho, sem mudar a posição.
- Sempre vai junto: `-game <pasta> -log engine.log +voice_enable 0 +gyro_enable 0|1 +exec hlios.cfg`, e
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
