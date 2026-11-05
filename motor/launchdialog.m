/*
 launchdialog.m - tela inicial do Half-Life no iPhone (hlios)
 Copyright (C) 2016 mittorn (diálogo original do port de iOS do Xash3D FWGS)
 Copyright (C) 2026 hlios (escolha do jogo e opções, no lugar da caixa de texto)

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
*/

// O motor chama IOS_LaunchDialog() e IOS_GetArgs() antes de iniciar (launcher.c), e
// IOS_GetDocsDir(), IOS_GetExecDir(), IOS_GetUDID() e IOS_Log() quando precisa.
// No iOS o motor não reinicia sozinho: o jogo é escolhido aqui, na abertura do app.
// Este arquivo é compilado sem ARC (o original também era).

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

// usadas pelo motor (engine/platform/platform.h, common/sys_con.c e client/identification.c)
const char *IOS_GetDocsDir( void );
const char *IOS_GetExecDir( void );
void IOS_LaunchDialog( void );
int IOS_GetArgs( char ***out );
char *IOS_GetUDID( void );
void IOS_Log( const char *text );
void IOS_Encerrar( int codigo ); // chamada pelo engine/common/launcher.c (patch 0002)

typedef struct
{
	const char *pasta;     // pasta do jogo em Documentos (vira o -game)
	const char *libs;      // prefixo dos frameworks com as bibliotecas do jogo
	const char *titulo;
	const char *subtitulo;
	const char *args;      // argumentos próprios do jogo
} hl_jogo_t;

static const hl_jogo_t s_jogos[] =
{
	{ "valve",   "valve",   "Half-Life",          "A campanha original",       "" },
	{ "gearbox", "gearbox", "Opposing Force",     "Expansão: Adrian Shephard", "" },
	{ "bshift",  "valve",   "Blue Shift",         "Expansão: Barney Calhoun",  "-dll @hl" },
	{ "cstrike", "cstrike", "Counter-Strike 1.6", "Offline, contra bots",      "" },
	{ "dmc",     "dmc",     "Deathmatch Classic", "Multiplayer, sem bots",     "" },
};

#define HL_NUM_JOGOS ((int)( sizeof( s_jogos ) / sizeof( s_jogos[0] )))

static int s_argc = 0;
static char **s_argv = NULL;
static BOOL s_pronto = NO;
static UIWindow *s_janela = nil;

static NSString *HL_Texto( const char *s )
{
	return [NSString stringWithUTF8String:s];
}

static UIColor *HL_Laranja( void )
{
	return [UIColor colorWithRed:1.0 green:0.54 blue:0.12 alpha:1.0];
}

static NSUserDefaults *HL_Prefs( void )
{
	NSUserDefaults *p = [NSUserDefaults standardUserDefaults];

	[p registerDefaults:@{
		@"hl.giroscopio": @NO,
		@"hl.olharatira": @YES,
		@"hl.som": @YES,
		@"hl.diagnostico": @YES,
		@"hl.hd": @YES,
		@"hl.addon": @YES,
		@"hl.mira": @2,
		@"hl.toque": @1,
		@"hl.fov": @90,
		@"hl.fovarmas": @90,
		@"hl.extras": @"",
		@"hl.jogo": @"valve"
	}];

	// até a 0.1.10 o "toque no olhar atira" era um interruptor: se estava desligado, continua desligado
	if( ![p boolForKey:@"hl.migrou.toque"] )
	{
		if( ![p boolForKey:@"hl.olharatira"] )
			[p setInteger:0 forKey:@"hl.toque"];
		[p setBool:YES forKey:@"hl.migrou.toque"];
	}

	return p;
}

const char *IOS_GetDocsDir( void )
{
	static char *dir = NULL;

	if( !dir )
	{
		NSArray *paths = NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES );
		NSString *docs = [paths objectAtIndex:0];

		[[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:NULL];
		dir = strdup( [docs fileSystemRepresentation] ); // a string do NSString é temporária
		NSLog( @"IOS_GetDocsDir: %s", dir );
	}

	return dir;
}

const char *IOS_GetExecDir( void )
{
	static char *dir = NULL;

	if( !dir )
	{
		dir = strdup( [[[NSBundle mainBundle] bundlePath] fileSystemRepresentation] );
		NSLog( @"IOS_GetExecDir: %s", dir );
	}

	return dir;
}

static NSString *HL_Docs( void )
{
	return HL_Texto( IOS_GetDocsDir( ));
}

// a pasta do jogo foi copiada para Documentos?
static BOOL HL_TemPasta( const char *pasta )
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = [HL_Docs() stringByAppendingPathComponent:HL_Texto( pasta )];

	return [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"liblist.gam"]]
		|| [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"gameinfo.txt"]];
}

// esta build trouxe as bibliotecas do jogo? (o Counter-Strike é opcional na build)
static BOOL HL_TemBibliotecas( const char *prefixo )
{
	NSString *fw = [[NSBundle mainBundle] privateFrameworksPath];
	NSArray *itens = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fw error:NULL];
	NSString *inicio = [NSString stringWithFormat:@"%s__", prefixo];

	for( NSString *item in itens )
	{
		if( [item hasPrefix:inicio] )
			return YES;
	}

	return NO;
}

// cria o LEIA-ME em Documentos: também faz a pasta do app aparecer no app Arquivos
static void HL_CriarLeiaMe( void )
{
	NSString *caminho = [HL_Docs() stringByAppendingPathComponent:@"LEIA-ME.txt"];
	NSString *texto =
		@"Half-Life no iPhone\n"
		@"\n"
		@"Copie para esta pasta (Arquivos > No Meu iPhone > Half-Life) as pastas dos jogos,\n"
		@"tiradas da sua instalação da Steam (Steam\\steamapps\\common\\Half-Life):\n"
		@"\n"
		@"  valve     Half-Life (obrigatória, as outras dependem dela)\n"
		@"  gearbox   Opposing Force\n"
		@"  bshift    Blue Shift\n"
		@"  cstrike   Counter-Strike 1.6\n"
		@"  dmc       Deathmatch Classic\n"
		@"\n"
		@"As pastas terminadas em _hd (valve_hd, gearbox_hd, bshift_hd) são opcionais:\n"
		@"têm os modelos em alta definição.\n"
		@"\n"
		@"Os saves ficam na pasta save de cada jogo. O log fica em engine.log, aqui mesmo.\n"
		@"Para trocar de jogo, saia pelo menu do jogo e abra o app de novo.\n";

	if( ![[NSFileManager defaultManager] fileExistsAtPath:caminho] )
		[texto writeToFile:caminho atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

// botões de toque do app: pulo longo (agachar + pular) em todos os jogos e, no HL, no OF e no BS,
// guardar e sacar a arma (impulse 200, patch jogos/*/0003-guardar-arma.patch)
static void HL_PrepararPuloLongo( const char *pasta )
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *dir = [HL_Docs() stringByAppendingPathComponent:HL_Texto( pasta )];
	NSString *touch = [dir stringByAppendingPathComponent:@"touch.cfg"];
	BOOL ehHL = !strcmp( pasta, "valve" ) || !strcmp( pasta, "gearbox" ) || !strcmp( pasta, "bshift" );
	NSMutableArray *nomes = [NSMutableArray arrayWithObject:@"pulolongo"];
	NSMutableArray *botoes = [NSMutableArray arrayWithObject:
		@"touch_addbutton \"pulolongo\" \"touch_default/jump\" \"+pulolongo\" 0.64 0.30 0.76 0.53 255 160 0 200 0 1\n"];

	// console, no alto da tela, entre os números das armas e o botão de guardar
	[nomes addObject:@"console"];
	[botoes addObject:@"touch_addbutton \"console\" \"touch_default/keyboard\" \"toggleconsole\" 0.612 0 0.668 0.12 255 255 255 200 0 1\n"];

	if( ehHL )
	{
		// guardar e sacar a arma, no lugar do spray (que só aparece no multiplayer)
		[nomes addObject:@"guardar"];
		[botoes addObject:@"touch_addbutton \"guardar\" \"touch_default/show_weapons\" \"impulse 200\" 0.68 0.00 0.76 0.142 120 200 255 200 0 1\n"];

		// números das armas fixos no alto: 5 grupos no HL e no BS, 7 no OF (os dois a mais ficam entre o
		// botão de editar e o de guardar)
		{
			const int grupos = !strcmp( pasta, "gearbox" ) ? 7 : 5;
			int n;

			for( n = 1; n <= grupos; n++ )
			{
				const float x = ( n <= 5 ) ? 0.130f + 0.056f * ( n - 1 ) : 0.500f + 0.056f * ( n - 6 );

				[nomes addObject:[NSString stringWithFormat:@"num%d", n]];
				[botoes addObject:[NSString stringWithFormat:
					@"touch_addbutton \"num%d\" \"touch_default/key_%d\" \"slot%d\" %.3f 0 %.3f 0.12 255 255 255 200 0 1\n",
					n, n, n, x, x + 0.056f]];
			}
		}
	}
	NSMutableString *cfg = [NSMutableString stringWithString:@"// gerado pelo app: pulo longo (agachar + pular) num botão só\n"
		@"alias +pulolongo \"+duck;+jump\"\n"
		@"alias -pulolongo \"-jump;-duck\"\n"];
	NSMutableString *faltando = [NSMutableString string];
	NSString *atual;
	NSUInteger i;

	for( i = 0; i < [nomes count]; i++ )
		[cfg appendString:[botoes objectAtIndex:i]];

	// hlios.cfg roda na abertura (+exec): cria o comando e, na primeira vez, o botão
	[cfg writeToFile:[dir stringByAppendingPathComponent:@"hlios.cfg"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

	// o motor carrega o touch.cfg por cima no começo da partida: o botão precisa estar nele também
	// (só acrescenta se não estiver, para não desfazer uma posição que você mudou no editor)
	if( ![fm fileExistsAtPath:touch] )
		return;

	atual = [NSString stringWithContentsOfFile:touch encoding:NSUTF8StringEncoding error:NULL];
	if( atual == nil )
		atual = [NSString stringWithContentsOfFile:touch encoding:NSISOLatin1StringEncoding error:NULL];

	if( atual == nil )
		return;

	for( i = 0; i < [nomes count]; i++ )
	{
		NSString *marca = [NSString stringWithFormat:@"\"%@\"", [nomes objectAtIndex:i]];

		if( [atual rangeOfString:marca].location == NSNotFound )
			[faltando appendString:[botoes objectAtIndex:i]];
	}

	if( [faltando length] > 0 )
	{
		NSString *novo = [atual hasSuffix:@"\n"] ? [atual stringByAppendingString:faltando]
			: [NSString stringWithFormat:@"%@\n%@", atual, faltando];
		[novo writeToFile:touch atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		atual = novo;
	}

	// versões até a 0.1.3 criavam o botão com a marca "não editável" (flag 2): tira só essa marca,
	// mantendo posição, tamanho e cor
	{
		NSArray *linhas = [atual componentsSeparatedByString:@"\n"];
		NSMutableArray *saida = [NSMutableArray arrayWithCapacity:[linhas count]];
		BOOL mudou = NO;

		for( NSString *linha in linhas )
		{
			NSString *nova = linha;
			NSString *limpa = [linha stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

			if( [limpa hasPrefix:@"touch_addbutton \"pulolongo\""] )
			{
				NSMutableArray *partes = [NSMutableArray array];

				for( NSString *t in [limpa componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] )
				{
					if( [t length] > 0 )
						[partes addObject:t];
				}

				// touch_addbutton nome textura comando x1 y1 x2 y2 r g b a flags [aspecto]
				if( [partes count] >= 13 )
				{
					int flags = [[partes objectAtIndex:12] intValue];

					if( flags & 2 )
					{
						[partes replaceObjectAtIndex:12 withObject:[NSString stringWithFormat:@"%d", flags & ~2]];
						nova = [partes componentsJoinedByString:@" "];
						mudou = YES;
					}
				}
			}

			[saida addObject:nova];
		}

		if( mudou )
			[[saida componentsJoinedByString:@"\n"] writeToFile:touch atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	}
}

static void HL_Juntar( NSMutableArray *lista, NSString *texto )
{
	NSArray *partes;

	if( texto == nil )
		return;

	partes = [texto componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	for( NSString *p in partes )
	{
		if( [p length] > 0 )
			[lista addObject:p];
	}
}

// o motor lê as pastas extras (_hd e _addon) do vfs.cfg do jogo logo que abre, antes dos argumentos;
// gravar aqui faz a opção valer já nesta abertura (o motor regrava o arquivo ao sair)
static void HL_PrepararVFS( const char *pasta )
{
	NSUserDefaults *p = HL_Prefs();
	NSString *dir = [HL_Docs() stringByAppendingPathComponent:HL_Texto( pasta )];
	NSString *cfg = [dir stringByAppendingPathComponent:@"vfs.cfg"];
	NSString *atual = [NSString stringWithContentsOfFile:cfg encoding:NSUTF8StringEncoding error:NULL];
	NSMutableArray *linhas = [NSMutableArray array];

	if( atual == nil )
		atual = [NSString stringWithContentsOfFile:cfg encoding:NSISOLatin1StringEncoding error:NULL];

	if( atual != nil )
	{
		for( NSString *l in [atual componentsSeparatedByString:@"\n"] )
		{
			NSString *limpa = [l stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

			if( [limpa length] == 0 || [limpa hasPrefix:@"fs_mount_hd"] || [limpa hasPrefix:@"fs_mount_addon"] )
				continue;

			[linhas addObject:limpa];
		}
	}

	[linhas addObject:[NSString stringWithFormat:@"fs_mount_hd \"%d\"", [p boolForKey:@"hl.hd"] ? 1 : 0]];
	[linhas addObject:[NSString stringWithFormat:@"fs_mount_addon \"%d\"", [p boolForKey:@"hl.addon"] ? 1 : 0]];

	[[[linhas componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"]
		writeToFile:cfg atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void HL_MontarArgs( const hl_jogo_t *jogo )
{
	NSUserDefaults *p = HL_Prefs();
	NSMutableArray *a = [NSMutableArray array];
	int i;

	[a addObject:@"xash3d"];
	[a addObject:@"-game"];
	[a addObject:HL_Texto( jogo->pasta )];
	HL_Juntar( a, HL_Texto( jogo->args ));

	// log em Documentos/engine.log
	[a addObject:@"-log"];
	[a addObject:@"engine.log"];

	// console liberado (abre pelo botão de teclado no alto da tela)
	[a addObject:@"-console"];

	// campo de visão do mundo (default_fov, em 4:3; a tela larga só abre os lados) e o da arma em primeira
	// pessoa (r_viewmodel_fov, patch 0004 do motor), na mesma escala
	[a addObject:@"+default_fov"];
	[a addObject:[NSString stringWithFormat:@"%d", (int)[p integerForKey:@"hl.fov"]]];
	[a addObject:@"+r_viewmodel_fov"];
	[a addObject:[NSString stringWithFormat:@"%d", (int)[p integerForKey:@"hl.fovarmas"]]];

	if( [p boolForKey:@"hl.diagnostico"] )
	{
		[a addObject:@"-dev"];
		[a addObject:@"2"];
	}

	// sem chat de voz: o app não pede o microfone
	[a addObject:@"+voice_enable"];
	[a addObject:@"0"];
	[a addObject:@"+gyro_enable"];
	[a addObject:[p boolForKey:@"hl.giroscopio"] ? @"1" : @"0"];

	// toque rápido na área de olhar atira; toque duplo e segurar atira sem parar (patch 0003 do motor).
	// 1 rigoroso: o dedo quase parado e rápido; 2 solto: a regra das versões até a 0.1.10
	{
		NSInteger toque = [p integerForKey:@"hl.toque"];

		[a addObject:@"+touch_look_fire"];
		[a addObject:( toque > 0 ) ? @"1" : @"0"];
		[a addObject:@"+touch_look_fire_time"];
		[a addObject:( toque == 2 ) ? @"0.25" : @"0.18"];
		[a addObject:@"+touch_look_fire_move"];
		[a addObject:( toque == 2 ) ? @"0.02" : @"0.005"];
	}

	// mira assistida (patch jogos/*/0001-mira-assistida.patch): só no HL, no OF e no BS
	if( !strcmp( jogo->pasta, "valve" ) || !strcmp( jogo->pasta, "gearbox" ) || !strcmp( jogo->pasta, "bshift" ))
	{
		// os botões de número trocam de arma no toque, sem abrir a lista do grupo
		[a addObject:@"+hud_fastswitch"];
		[a addObject:@"1"];

		[a addObject:@"+sv_aim_assist"];
		[a addObject:[NSString stringWithFormat:@"%d", (int)[p integerForKey:@"hl.mira"]]];
	}

	// modelos HD e conteúdo extra (veja HL_PrepararVFS)
	HL_PrepararVFS( jogo->pasta );

	// pulo longo (veja HL_PrepararPuloLongo)
	HL_PrepararPuloLongo( jogo->pasta );
	[a addObject:@"+exec"];
	[a addObject:@"hlios.cfg"];

	HL_Juntar( a, [p stringForKey:@"hl.extras"] );

	s_argc = (int)[a count];
	s_argv = (char **)calloc( (size_t)s_argc + 1, sizeof( char * ));

	for( i = 0; i < s_argc; i++ )
		s_argv[i] = strdup( [[a objectAtIndex:(NSUInteger)i] UTF8String] );

	s_argv[s_argc] = NULL;

	NSLog( @"hlios: argumentos: %@", [a componentsJoinedByString:@" "] );
}

static UIButtonConfiguration *HL_EstiloBotao( BOOL destaque )
{
	SEL sel = NSSelectorFromString( destaque ? @"prominentGlassButtonConfiguration" : @"glassButtonConfiguration" );
	Class cls = [UIButtonConfiguration class];
	UIButtonConfiguration *c;

	// Liquid Glass no iOS 26 ou mais novo; antes disso, os estilos comuns
	if( [cls respondsToSelector:sel] )
		c = (UIButtonConfiguration *)[cls performSelector:sel];
	else if( destaque )
		c = [UIButtonConfiguration filledButtonConfiguration];
	else
		c = [UIButtonConfiguration grayButtonConfiguration];

	return c;
}

@interface HLTela : UIViewController
{
	UIStackView *listaJogos;
	UISwitch *chaveGiro;
	UISegmentedControl *escolhaToque;
	UISwitch *chaveSom;
	UISwitch *chaveDiag;
	UISwitch *chaveHD;
	UISwitch *chaveAddon;
	UISegmentedControl *escolhaMira;
	UISlider *barraFov, *barraFovArmas;
	UILabel *rotuloFov, *rotuloFovArmas;
	UIButton *botaoExtras;
}
- (void)recarregar;
@end

@implementation HLTela

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
	return YES;
}

- (UILabel *)rotulo:(NSString *)texto tamanho:(CGFloat)tamanho peso:(UIFontWeight)peso cor:(UIColor *)cor
{
	UILabel *l = [[UILabel alloc] init];

	l.text = texto;
	l.font = [UIFont systemFontOfSize:tamanho weight:peso];
	l.textColor = cor;
	l.numberOfLines = 0;
	l.adjustsFontSizeToFitWidth = YES;
	l.minimumScaleFactor = 0.7;

	return l;
}

- (UIView *)linha:(NSString *)texto chave:(UISwitch *)chave
{
	UILabel *l = [self rotulo:texto tamanho:15 peso:UIFontWeightRegular cor:[UIColor whiteColor]];
	UIStackView *linha = [[UIStackView alloc] initWithArrangedSubviews:@[ l, chave ]];

	linha.axis = UILayoutConstraintAxisHorizontal;
	linha.alignment = UIStackViewAlignmentCenter;
	linha.spacing = 12;

	return linha;
}

- (UISwitch *)chave:(NSString *)chavePref
{
	UISwitch *s = [[UISwitch alloc] init];

	s.on = [HL_Prefs() boolForKey:chavePref];
	s.onTintColor = HL_Laranja();
	[s addTarget:self action:@selector(mudouOpcao:) forControlEvents:UIControlEventValueChanged];

	return s;
}

- (void)viewDidLoad
{
	NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
	NSString *versao = [NSString stringWithFormat:@"versão %@ (build %@)",
		[info objectForKey:@"CFBundleShortVersionString"], [info objectForKey:@"CFBundleVersion"]];
	UIStackView *esquerda, *direita, *colunas;
	UILabel *titulo, *subtitulo, *escolha, *ajuda, *rotuloMira, *rotuloToque;
	UIScrollView *rolagem;
	UILayoutGuide *area;

	[super viewDidLoad];

	self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.06 alpha:1.0];

	// coluna da esquerda: os jogos
	escolha = [self rotulo:@"Escolha o jogo" tamanho:15 peso:UIFontWeightSemibold cor:[UIColor lightGrayColor]];
	listaJogos = [[UIStackView alloc] init];
	listaJogos.axis = UILayoutConstraintAxisVertical;
	listaJogos.spacing = 8;
	esquerda = [[UIStackView alloc] initWithArrangedSubviews:@[ escolha, listaJogos ]];
	esquerda.axis = UILayoutConstraintAxisVertical;
	esquerda.spacing = 10;

	// coluna da direita: título e opções
	titulo = [self rotulo:@"Half-Life" tamanho:30 peso:UIFontWeightHeavy cor:HL_Laranja()];
	subtitulo = [self rotulo:versao tamanho:12 peso:UIFontWeightRegular cor:[UIColor grayColor]];
	chaveGiro = [self chave:@"hl.giroscopio"];
	escolhaToque = [[UISegmentedControl alloc] initWithItems:@[ @"Desligado", @"Rigoroso", @"Solto" ]];
	escolhaToque.selectedSegmentIndex = (NSInteger)[HL_Prefs() integerForKey:@"hl.toque"];
	escolhaToque.selectedSegmentTintColor = HL_Laranja();
	[escolhaToque addTarget:self action:@selector(mudouToque:) forControlEvents:UIControlEventValueChanged];
	rotuloToque = [self rotulo:@"Toque no olhar atira" tamanho:15 peso:UIFontWeightRegular
		cor:[UIColor whiteColor]];
	chaveSom = [self chave:@"hl.som"];
	chaveDiag = [self chave:@"hl.diagnostico"];
	chaveHD = [self chave:@"hl.hd"];
	chaveAddon = [self chave:@"hl.addon"];

	// campo de visão (60 a 120; 90 é o original), do mundo e da arma em primeira pessoa
	rotuloFov = [self rotulo:@"" tamanho:15 peso:UIFontWeightRegular cor:[UIColor whiteColor]];
	rotuloFovArmas = [self rotulo:@"" tamanho:15 peso:UIFontWeightRegular cor:[UIColor whiteColor]];
	barraFov = [self barra:@"hl.fov"];
	barraFovArmas = [self barra:@"hl.fovarmas"];
	[self atualizarFov];

	// mira assistida: 0 desligada, 1 normal (a do jogo, também no Difícil), 2 forte, 3 muito forte
	rotuloMira = [self rotulo:@"Mira assistida (vale também no Difícil)" tamanho:15 peso:UIFontWeightRegular
		cor:[UIColor whiteColor]];
	escolhaMira = [[UISegmentedControl alloc] initWithItems:@[ @"Desligada", @"Normal", @"Forte", @"Muito forte" ]];
	escolhaMira.selectedSegmentIndex = (NSInteger)[HL_Prefs() integerForKey:@"hl.mira"];
	escolhaMira.selectedSegmentTintColor = HL_Laranja();
	[escolhaMira addTarget:self action:@selector(mudouMira:) forControlEvents:UIControlEventValueChanged];

	// argumentos extras: abrem numa janelinha, que o iPhone põe acima do teclado
	botaoExtras = [UIButton buttonWithConfiguration:HL_EstiloBotao( NO ) primaryAction:nil];
	botaoExtras.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	[botaoExtras addTarget:self action:@selector(editarExtras:) forControlEvents:UIControlEventTouchUpInside];
	[self atualizarBotaoExtras];

	ajuda = [self rotulo:@"Arquivos › No Meu iPhone › Half-Life: copie para lá as pastas valve, gearbox e bshift "
		@"(e cstrike e dmc, se quiser) da sua instalação da Steam. Para trocar de jogo, saia pelo menu do jogo e "
		@"abra o app de novo."
		tamanho:12 peso:UIFontWeightRegular cor:[UIColor grayColor]];

	direita = [[UIStackView alloc] initWithArrangedSubviews:@[
		titulo, subtitulo,
		[self linha:@"Mira pelo giroscópio" chave:chaveGiro],
		[self linha:@"Som no modo silencioso" chave:chaveSom],
		[self linha:@"Log detalhado (diagnóstico)" chave:chaveDiag],
		[self linha:@"Modelos HD" chave:chaveHD],
		[self linha:@"Conteúdo extra (pastas _addon)" chave:chaveAddon],
		rotuloToque, escolhaToque,
		rotuloMira, escolhaMira,
		rotuloFov, barraFov,
		rotuloFovArmas, barraFovArmas,
		botaoExtras, ajuda
	]];
	direita.axis = UILayoutConstraintAxisVertical;
	direita.spacing = 8;
	direita.translatesAutoresizingMaskIntoConstraints = NO;
	[direita setCustomSpacing:12 afterView:subtitulo];
	[direita setCustomSpacing:6 afterView:rotuloToque];
	[direita setCustomSpacing:12 afterView:escolhaToque];
	[direita setCustomSpacing:6 afterView:rotuloMira];
	[direita setCustomSpacing:12 afterView:escolhaMira];
	[direita setCustomSpacing:2 afterView:rotuloFov];
	[direita setCustomSpacing:10 afterView:barraFov];
	[direita setCustomSpacing:2 afterView:rotuloFovArmas];
	[direita setCustomSpacing:12 afterView:barraFovArmas];

	// a coluna da direita rola, para caber em qualquer iPhone
	rolagem = [[UIScrollView alloc] init];
	rolagem.showsHorizontalScrollIndicator = NO;
	rolagem.alwaysBounceVertical = NO;
	[rolagem addSubview:direita];
	[NSLayoutConstraint activateConstraints:@[
		[direita.topAnchor constraintEqualToAnchor:rolagem.contentLayoutGuide.topAnchor],
		[direita.bottomAnchor constraintEqualToAnchor:rolagem.contentLayoutGuide.bottomAnchor],
		[direita.leadingAnchor constraintEqualToAnchor:rolagem.contentLayoutGuide.leadingAnchor],
		[direita.trailingAnchor constraintEqualToAnchor:rolagem.contentLayoutGuide.trailingAnchor],
		[direita.widthAnchor constraintEqualToAnchor:rolagem.frameLayoutGuide.widthAnchor]
	]];

	colunas = [[UIStackView alloc] initWithArrangedSubviews:@[ esquerda, rolagem ]];
	colunas.axis = UILayoutConstraintAxisHorizontal;
	colunas.alignment = UIStackViewAlignmentTop;
	colunas.distribution = UIStackViewDistributionFillEqually;
	colunas.spacing = 28;
	colunas.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:colunas];

	area = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[colunas.topAnchor constraintEqualToAnchor:area.topAnchor constant:16],
		[colunas.leadingAnchor constraintEqualToAnchor:area.leadingAnchor constant:20],
		[colunas.trailingAnchor constraintEqualToAnchor:area.trailingAnchor constant:-20],
		[colunas.bottomAnchor constraintLessThanOrEqualToAnchor:area.bottomAnchor constant:-8],
		[rolagem.heightAnchor constraintEqualToAnchor:area.heightAnchor constant:-24]
	]];

	[self recarregar];

	// voltando do app Arquivos, a lista se atualiza sozinha
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(recarregar)
		name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)recarregar
{
	NSArray *antigos = [NSArray arrayWithArray:listaJogos.arrangedSubviews];
	NSString *ultimo = [HL_Prefs() stringForKey:@"hl.jogo"];
	BOOL temValve = HL_TemPasta( "valve" );
	int i, mostrados = 0;

	for( UIView *v in antigos )
	{
		[listaJogos removeArrangedSubview:v];
		[v removeFromSuperview];
	}

	for( i = 0; i < HL_NUM_JOGOS; i++ )
	{
		const hl_jogo_t *j = &s_jogos[i];
		BOOL pronto;
		UIButtonConfiguration *c;
		UIButton *b;

		// sem as bibliotecas nesta build, o jogo nem aparece
		if( !HL_TemBibliotecas( j->libs ))
			continue;

		pronto = HL_TemPasta( j->pasta ) && temValve;
		c = HL_EstiloBotao( pronto && [ultimo isEqualToString:HL_Texto( j->pasta )] );
		c.title = HL_Texto( j->titulo );

		if( pronto )
			c.subtitle = HL_Texto( j->subtitulo );
		else if( !temValve )
			c.subtitle = @"Falta a pasta valve";
		else
			c.subtitle = [NSString stringWithFormat:@"Falta a pasta %s", j->pasta];

		c.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
		c.contentInsets = NSDirectionalEdgeInsetsMake( 9, 16, 9, 16 );
		c.cornerStyle = UIButtonConfigurationCornerStyleLarge;

		b = [UIButton buttonWithConfiguration:c primaryAction:nil];
		b.tag = i;
		b.enabled = pronto;
		b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
		[b addTarget:self action:@selector(jogar:) forControlEvents:UIControlEventTouchUpInside];
		[listaJogos addArrangedSubview:b];
		mostrados++;
	}

	if( mostrados == 0 )
	{
		[listaJogos addArrangedSubview:[self rotulo:@"Esta build não tem nenhum jogo." tamanho:15
			peso:UIFontWeightRegular cor:[UIColor whiteColor]]];
	}
}

- (void)mudouOpcao:(UISwitch *)s
{
	NSUserDefaults *p = HL_Prefs();

	if( s == chaveGiro )
		[p setBool:s.on forKey:@"hl.giroscopio"];
	else if( s == chaveSom )
		[p setBool:s.on forKey:@"hl.som"];
	else if( s == chaveDiag )
		[p setBool:s.on forKey:@"hl.diagnostico"];
	else if( s == chaveHD )
		[p setBool:s.on forKey:@"hl.hd"];
	else if( s == chaveAddon )
		[p setBool:s.on forKey:@"hl.addon"];
}

- (UISlider *)barra:(NSString *)chave
{
	UISlider *b = [[UISlider alloc] init];

	b.minimumValue = 60;
	b.maximumValue = 120;
	b.value = (float)[HL_Prefs() integerForKey:chave];
	b.minimumTrackTintColor = HL_Laranja();
	[b addTarget:self action:@selector(mudouFov:) forControlEvents:UIControlEventValueChanged];

	return b;
}

- (void)atualizarFov
{
	NSInteger fov = [HL_Prefs() integerForKey:@"hl.fov"], armas = [HL_Prefs() integerForKey:@"hl.fovarmas"];

	rotuloFov.text = [NSString stringWithFormat:@"Campo de visão: %d%@", (int)fov, fov == 90 ? @" (original)" : @""];
	rotuloFovArmas.text = [NSString stringWithFormat:@"Campo de visão das armas: %d%@", (int)armas,
		armas == 90 ? @" (original)" : @""];
}

- (void)mudouFov:(UISlider *)b
{
	// de 1 em 1, e "gruda" no 90 (o original) quando passa perto
	NSInteger v = (NSInteger)lroundf( b.value );

	if( v >= 89 && v <= 91 )
		v = 90;

	b.value = (float)v;
	[HL_Prefs() setInteger:v forKey:( b == barraFov ) ? @"hl.fov" : @"hl.fovarmas"];
	[self atualizarFov];
}

- (void)mudouToque:(UISegmentedControl *)c
{
	[HL_Prefs() setInteger:c.selectedSegmentIndex forKey:@"hl.toque"];
}

- (void)mudouMira:(UISegmentedControl *)c
{
	[HL_Prefs() setInteger:c.selectedSegmentIndex forKey:@"hl.mira"];
}

- (void)atualizarBotaoExtras
{
	NSString *texto = [HL_Prefs() stringForKey:@"hl.extras"];
	UIButtonConfiguration *c = HL_EstiloBotao( NO );

	c.title = @"Argumentos extras";
	c.subtitle = [texto length] > 0 ? texto : @"nenhum (toque para escrever)";
	c.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
	c.contentInsets = NSDirectionalEdgeInsetsMake( 8, 14, 8, 14 );
	c.cornerStyle = UIButtonConfigurationCornerStyleLarge;
	botaoExtras.configuration = c;
}

- (void)editarExtras:(UIButton *)b
{
	__block UIAlertController *janela = [UIAlertController alertControllerWithTitle:@"Argumentos extras"
		message:@"Vão no fim da linha de comando do jogo. Ex.: +sv_cheats 1" preferredStyle:UIAlertControllerStyleAlert];

	[janela addTextFieldWithConfigurationHandler:^( UITextField *t ) {
		t.text = [HL_Prefs() stringForKey:@"hl.extras"];
		t.autocapitalizationType = UITextAutocapitalizationTypeNone;
		t.autocorrectionType = UITextAutocorrectionTypeNo;
		t.spellCheckingType = UITextSpellCheckingTypeNo;
		t.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];
	[janela addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
	[janela addAction:[UIAlertAction actionWithTitle:@"Salvar" style:UIAlertActionStyleDefault handler:^( UIAlertAction *acao ) {
		NSString *texto = [[janela.textFields objectAtIndex:0] text];

		(void)acao;

		[HL_Prefs() setObject:( texto ? texto : @"" ) forKey:@"hl.extras"];
		[self atualizarBotaoExtras];
	}]];

	[self presentViewController:janela animated:YES completion:nil];
}

- (void)jogar:(UIButton *)b
{
	NSUserDefaults *p = HL_Prefs();
	const hl_jogo_t *j;

	if( b.tag < 0 || b.tag >= HL_NUM_JOGOS )
		return;

	j = &s_jogos[b.tag];

	[p setObject:HL_Texto( j->pasta ) forKey:@"hl.jogo"];
	[p synchronize];

	// o SDL lê estes ajustes do ambiente quando abre a janela e o áudio
	setenv( "SDL_AUDIO_CATEGORY", [p boolForKey:@"hl.som"] ? "playback" : "ambient", 1 );
	setenv( "SDL_IOS_HIDE_HOME_INDICATOR", "2", 1 ); // esconde a barra do Início e segura os gestos das bordas

	HL_MontarArgs( j );

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	s_pronto = YES;
}

@end

void IOS_LaunchDialog( void )
{
	HLTela *tela;

	NSLog( @"hlios: iOS %@", [[UIDevice currentDevice] systemVersion] );

	// o engine.log e os arquivos relativos ficam em Documentos
	if( chdir( IOS_GetDocsDir( )) != 0 )
		NSLog( @"hlios: não consegui entrar em %s", IOS_GetDocsDir( ));

	HL_CriarLeiaMe();

	tela = [[HLTela alloc] init];
	s_janela = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	s_janela.windowLevel = UIWindowLevelNormal + 2; // por cima de uma tela de abertura do SDL, se houver
	s_janela.rootViewController = tela;
	[s_janela makeKeyAndVisible];

	while( !s_pronto )
	{
		@autoreleasepool
		{
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		}
	}

	// a janela do jogo (SDL) toma o lugar desta
	s_janela.hidden = YES;
	s_janela.rootViewController = nil;
}

int IOS_GetArgs( char ***out )
{
	*out = s_argv;
	return s_argc;
}

char *IOS_GetUDID( void )
{
	static char udid[256];
	NSString *uuid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];

	if( uuid != nil )
		strncpy( udid, [uuid UTF8String], sizeof( udid ) - 1 );
	else
		strncpy( udid, "hlios", sizeof( udid ) - 1 );

	udid[sizeof( udid ) - 1] = 0;

	return udid;
}

// ao sair do jogo (Quit ou erro): o iPhone não tem um jeito público de um app ir para a tela inicial
// sozinho, então usa o "suspend" do UIApplication (o mesmo efeito do botão de início), espera a animação
// e fecha. Se ele não existir, fecha direto, como antes
void IOS_Encerrar( int codigo )
{
	UIApplication *app = [UIApplication sharedApplication];
	SEL voltar = NSSelectorFromString( [@"sus" stringByAppendingString:@"pend"] );

	if( app != nil && [app respondsToSelector:voltar] )
	{
		NSDate *fim = [NSDate dateWithTimeIntervalSinceNow:1.0];

		[app performSelector:voltar];

		while( [fim timeIntervalSinceNow] > 0 )
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:fim];
	}

	exit( codigo );
}

void IOS_Log( const char *text )
{
	NSLog( @"Xash: %s", text );
}
