/*
 * loadkeys.y
 *
 * For history, see older versions.
 */

%token EOL NUMBER LITERAL CHARSET KEYMAPS KEYCODE EQUALS
%token PLAIN SHIFT CONTROL ALT ALTGR SHIFTL SHIFTR CTRLL CTRLR CAPSSHIFT
%token COMMA DASH STRING STRLITERAL COMPOSE TO CCHAR ERROR PLUS
%token UNUMBER ALT_IS_META STRINGS AS USUAL ON FOR

%{
#include <errno.h>
#include <stdio.h>
#include <getopt.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <fcntl.h>
#include <ctype.h>
#include <sys/param.h>
#include <sys/ioctl.h>
#include <linux/kd.h>
#include <linux/keyboard.h>
#include <unistd.h>

#include "paths.h"
#include "findfile.h"
#include "ksyms.h"
#include "modifiers.h"
#include "xmalloc.h"
#include "version.h"

#define U(x) ((x) ^ 0xf000)

#ifdef KDSKBDIACRUC
typedef struct kbdiacruc accent_entry;
#else
typedef struct kbdiacr accent_entry;
#endif

#ifndef KT_LETTER
#define KT_LETTER KT_LATIN
#endif

#undef NR_KEYS
#define NR_KEYS 256

/* What keymaps are we defining? */
char defining[MAX_NR_KEYMAPS];
char keymaps_line_seen = 0;
int max_keymap = 0;	/* from here on, defining[] is false */
int alt_is_meta = 0;

/* the kernel structures we want to set or print */
u_short *key_map[MAX_NR_KEYMAPS];
char *func_table[MAX_NR_FUNC];

accent_entry accent_table[MAX_DIACR];
unsigned int accent_table_size = 0;

char key_is_constant[NR_KEYS];
char *keymap_was_set[MAX_NR_KEYMAPS];
char func_buf[4096];	/* should be allocated dynamically */
char *fp = func_buf;

int key_buf[MAX_NR_KEYMAPS];
int mod;
int private_error_ct = 0;

extern int rvalct;
extern struct kbsentry kbs_buf;

void lkfatal(const char *fmt, ...);
int yyerror(const char *s);

extern char *filename;
extern int line_nr;

extern void stack_push(FILE *fd, int ispipe, char *filename);
extern int prefer_unicode;

#include "ksyms.h"
int yylex(void);

static void attr_noreturn usage(void)
{
	fprintf(stderr, _("loadkeys version %s\n"
			  "\n"
			  "Usage: loadkeys [option...] [mapfile...]\n"
			  "\n"
			  "Valid options are:\n"
			  "\n"
			  "  -a --ascii         force conversion to ASCII\n"
			  "  -d --default       load \"%s\"\n"
			  "  -h --help          display this help text\n"
				"  -t --suffix        suffix of the output table name (use with -m)\n"
			  "  -q --quiet         suppress all normal output\n"
			  "  -u --unicode       force conversion to Unicode\n"
			  "  -v --verbose       report the changes\n"),
		PACKAGE_VERSION, DEFMAP);
	exit(EXIT_FAILURE);
}

char **dirpath;
char *dirpath1[] = { "", DATADIR "/" KEYMAPDIR "/**", KERNDIR "/", 0 };
char *dirpath2[] = { 0, 0 };
char *suffixes[] = { "", ".kmap", ".map", 0 };

char **args;
int opta = 0;
int optd = 0;
int optu = 0;
int verbose = 0;
int quiet = 0;

int yyerror(const char *s)
{
	fprintf(stderr, "%s:%d: %s\n", filename, line_nr, s);
	private_error_ct++;
	return (0);
}

void attr_noreturn attr_format_1_2 lkfatal(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fprintf(stderr, "%s: %s:%d: ", progname, filename, line_nr);
	vfprintf(stderr, fmt, ap);
	fprintf(stderr, "\n");
	va_end(ap);
	exit(EXIT_FAILURE);
}

static void addmap(int i, int explicit)
{
	if (i < 0 || i >= MAX_NR_KEYMAPS)
		lkfatal(_("addmap called with bad index %d"), i);

	if (!defining[i]) {
		if (keymaps_line_seen && !explicit)
			lkfatal(_("adding map %d violates explicit keymaps line"), i);

		defining[i] = 1;
		if (max_keymap <= i)
			max_keymap = i + 1;
	}
}

/* unset a key */
static void killkey(int k_index, int k_table)
{
	/* roughly: addkey(k_index, k_table, K_HOLE); */

	if (k_index < 0 || k_index >= NR_KEYS)
		lkfatal(_("killkey called with bad index %d"), k_index);

	if (k_table < 0 || k_table >= MAX_NR_KEYMAPS)
		lkfatal(_("killkey called with bad table %d"), k_table);

	if (key_map[k_table])
		(key_map[k_table])[k_index] = K_HOLE;

	if (keymap_was_set[k_table])
		(keymap_was_set[k_table])[k_index] = 0;
}

static void addkey(int k_index, int k_table, int keycode)
{
	int i;

	if (keycode == CODE_FOR_UNKNOWN_KSYM)
		/* is safer not to be silent in this case, 
		 * it can be caused by coding errors as well. */
		lkfatal(_("addkey called with bad keycode %d"), keycode);

	if (k_index < 0 || k_index >= NR_KEYS)
		lkfatal(_("addkey called with bad index %d"), k_index);

	if (k_table < 0 || k_table >= MAX_NR_KEYMAPS)
		lkfatal(_("addkey called with bad table %d"), k_table);

	if (!defining[k_table])
		addmap(k_table, 0);

	if (!key_map[k_table]) {
		key_map[k_table] =
		    (u_short *) xmalloc(NR_KEYS * sizeof(u_short));
		for (i = 0; i < NR_KEYS; i++)
			(key_map[k_table])[i] = K_HOLE;
	}

	if (!keymap_was_set[k_table]) {
		keymap_was_set[k_table] = (char *)xmalloc(NR_KEYS);
		for (i = 0; i < NR_KEYS; i++)
			(keymap_was_set[k_table])[i] = 0;
	}

	if (alt_is_meta && keycode == K_HOLE
	    && (keymap_was_set[k_table])[k_index])
		return;

	//printf("addkey: %d %d 0x%04x\n", k_table, k_index, keycode);
	(key_map[k_table])[k_index] = keycode;
	(keymap_was_set[k_table])[k_index] = 1;

	if (alt_is_meta) {
		int alttable = k_table | M_ALT;
		int type = KTYP(keycode);
		int val = KVAL(keycode);

		if (alttable != k_table && defining[alttable] &&
		    (!keymap_was_set[alttable] ||
		     !(keymap_was_set[alttable])[k_index]) &&
		    (type == KT_LATIN || type == KT_LETTER) && val < 128)
			addkey(k_index, alttable, K(KT_META, val));
	}
}

static void addfunc(struct kbsentry kbs)
{
	int sh, i, x;
	char *ptr, *q, *r;

	x = kbs.kb_func;

	if (x >= MAX_NR_FUNC) {
		fprintf(stderr, _("%s: addfunc called with bad func %d\n"),
			progname, kbs.kb_func);
		exit(EXIT_FAILURE);
	}

	q = func_table[x];
	if (q) {		/* throw out old previous def */
		sh = strlen(q) + 1;
		ptr = q + sh;
		while (ptr < fp)
			*q++ = *ptr++;
		fp -= sh;

		for (i = x + 1; i < MAX_NR_FUNC; i++) {
			if (func_table[i])
				func_table[i] -= sh;
		}
	}

	ptr = func_buf;		/* find place for new def */
	for (i = 0; i < x; i++) {
		if (func_table[i]) {
			ptr = func_table[i];
			while (*ptr++) ;
		}
	}

	func_table[x] = ptr;
	sh = strlen((char *)kbs.kb_string) + 1;

	if (fp + sh > func_buf + sizeof(func_buf)) {
		fprintf(stderr, _("%s: addfunc: func_buf overflow\n"), progname);
		exit(EXIT_FAILURE);
	}
	q = fp;
	fp += sh;
	r = fp;
	while (q > ptr)
		*--r = *--q;
	strcpy(ptr, (char *)kbs.kb_string);
	for (i = x + 1; i < MAX_NR_FUNC; i++) {
		if (func_table[i])
			func_table[i] += sh;
	}
}

static void compose(int diacr, int base, int res)
{
	accent_entry *ptr;
	int direction;

#ifdef KDSKBDIACRUC
	if (prefer_unicode)
		direction = TO_UNICODE;
	else
#endif
		direction = TO_8BIT;

	if (accent_table_size == MAX_DIACR) {
		fprintf(stderr, _("compose table overflow\n"));
		exit(EXIT_FAILURE);
	}

	ptr = &accent_table[accent_table_size++];
	ptr->diacr = convert_code(diacr, direction);
	ptr->base = convert_code(base, direction);
	ptr->result = convert_code(res, direction);
}


static void do_constant_key(int i, u_short key)
{
	int typ, val, j;

	typ = KTYP(key);
	val = KVAL(key);

	if ((typ == KT_LATIN || typ == KT_LETTER) &&
	    ((val >= 'a' && val <= 'z') || (val >= 'A' && val <= 'Z'))) {
		u_short defs[16];
		defs[0] = K(KT_LETTER, val);
		defs[1] = K(KT_LETTER, val ^ 32);
		defs[2] = defs[0];
		defs[3] = defs[1];

		for (j = 4; j < 8; j++)
			defs[j] = K(KT_LATIN, val & ~96);

		for (j = 8; j < 16; j++)
			defs[j] = K(KT_META, KVAL(defs[j - 8]));

		for (j = 0; j < max_keymap; j++) {
			if (!defining[j])
				continue;

			if (j > 0 &&
			    keymap_was_set[j] && (keymap_was_set[j])[i])
				continue;

			addkey(i, j, defs[j % 16]);
		}

	} else {
		/* do this also for keys like Escape,
		   as promised in the man page */
		for (j = 1; j < max_keymap; j++) {
			if (defining[j] &&
			    (!(keymap_was_set[j]) || !(keymap_was_set[j])[i]))
				addkey(i, j, key);
		}
	}
}

static void do_constant(void)
{
	int i, r0 = 0;

	if (keymaps_line_seen) {
		while (r0 < max_keymap && !defining[r0])
			r0++;
	}

	for (i = 0; i < NR_KEYS; i++) {
		if (key_is_constant[i]) {
			u_short key;

			if (!key_map[r0])
				lkfatal(_("impossible error in do_constant"));

			key = (key_map[r0])[i];
			do_constant_key(i, key);
		}
	}
}

static void strings_as_usual(void)
{
	/*
	 * 26 strings, mostly inspired by the VT100 family
	 */
	char *stringvalues[30] = {
		/* F1 .. F20 */
		"\033[[A",  "\033[[B",  "\033[[C",  "\033[[D",  "\033[[E",
		"\033[17~", "\033[18~", "\033[19~", "\033[20~", "\033[21~",
		"\033[23~", "\033[24~", "\033[25~", "\033[26~",
		"\033[28~", "\033[29~",
		"\033[31~", "\033[32~", "\033[33~", "\033[34~",
		/* Find,    Insert,     Remove,     Select,     Prior */
		"\033[1~",  "\033[2~",  "\033[3~",  "\033[4~",  "\033[5~",
		/* Next,    Macro,      Help,       Do,         Pause */
		"\033[6~",  0,          0,          0,          0
	};
	int i;

	for (i = 0; i < 30; i++) {
		if (stringvalues[i]) {
			struct kbsentry ke;
			ke.kb_func = i;
			strncpy((char *)ke.kb_string, stringvalues[i],
				sizeof(ke.kb_string));
			ke.kb_string[sizeof(ke.kb_string) - 1] = 0;
			addfunc(ke);
		}
	}
}

static void compose_as_usual(char *charset)
{
	if (charset && strcmp(charset, "iso-8859-1")) {
		fprintf(stderr, _("loadkeys: don't know how to compose for %s\n"),
			charset);
		exit(EXIT_FAILURE);

	} else {
		struct ccc {
			unsigned char c1, c2, c3;
		} def_latin1_composes[68] = {
			{ '`', 'A', 0300 }, { '`', 'a', 0340 },
			{ '\'', 'A', 0301 }, { '\'', 'a', 0341 },
			{ '^', 'A', 0302 }, { '^', 'a', 0342 },
			{ '~', 'A', 0303 }, { '~', 'a', 0343 },
			{ '"', 'A', 0304 }, { '"', 'a', 0344 },
			{ 'O', 'A', 0305 }, { 'o', 'a', 0345 },
			{ '0', 'A', 0305 }, { '0', 'a', 0345 },
			{ 'A', 'A', 0305 }, { 'a', 'a', 0345 },
			{ 'A', 'E', 0306 }, { 'a', 'e', 0346 },
			{ ',', 'C', 0307 }, { ',', 'c', 0347 },
			{ '`', 'E', 0310 }, { '`', 'e', 0350 },
			{ '\'', 'E', 0311 }, { '\'', 'e', 0351 },
			{ '^', 'E', 0312 }, { '^', 'e', 0352 },
			{ '"', 'E', 0313 }, { '"', 'e', 0353 },
			{ '`', 'I', 0314 }, { '`', 'i', 0354 },
			{ '\'', 'I', 0315 }, { '\'', 'i', 0355 },
			{ '^', 'I', 0316 }, { '^', 'i', 0356 },
			{ '"', 'I', 0317 }, { '"', 'i', 0357 },
			{ '-', 'D', 0320 }, { '-', 'd', 0360 },
			{ '~', 'N', 0321 }, { '~', 'n', 0361 },
			{ '`', 'O', 0322 }, { '`', 'o', 0362 },
			{ '\'', 'O', 0323 }, { '\'', 'o', 0363 },
			{ '^', 'O', 0324 }, { '^', 'o', 0364 },
			{ '~', 'O', 0325 }, { '~', 'o', 0365 },
			{ '"', 'O', 0326 }, { '"', 'o', 0366 },
			{ '/', 'O', 0330 }, { '/', 'o', 0370 },
			{ '`', 'U', 0331 }, { '`', 'u', 0371 },
			{ '\'', 'U', 0332 }, { '\'', 'u', 0372 },
			{ '^', 'U', 0333 }, { '^', 'u', 0373 },
			{ '"', 'U', 0334 }, { '"', 'u', 0374 },
			{ '\'', 'Y', 0335 }, { '\'', 'y', 0375 },
			{ 'T', 'H', 0336 }, { 't', 'h', 0376 },
			{ 's', 's', 0337 }, { '"', 'y', 0377 },
			{ 's', 'z', 0337 }, { 'i', 'j', 0377 }
		};
		int i;
		for (i = 0; i < 68; i++) {
			struct ccc ptr = def_latin1_composes[i];
			compose(ptr.c1, ptr.c2, ptr.c3);
		}
	}
}

/*
 * mktable.c
 *
 */
static char *modifiers[8] = {
	"shift", "altgr", "ctrl", "alt", "shl", "shr", "ctl", "ctr"
};

static char *mk_mapname(char modifier)
{
	static char buf[60];
	int i;

	if (!modifier)
		return "plain";
	buf[0] = 0;
	for (i = 0; i < 8; i++)
		if (modifier & (1 << i)) {
			if (buf[0])
				strcat(buf, "_");
			strcat(buf, modifiers[i]);
		}
	return buf;
}

static void attr_noreturn mktable(char *table_suffix)
{
	int j;
	unsigned int i;

	printf("#include <stdint.h>\n");
	printf("#include <linux/keyboard.h>\n");

	for (i = 0; i < MAX_NR_KEYMAPS; i++){
		if(i&0xf0)
			continue;
		printf("\nstatic uint16_t %s_map%s[NR_KEYS] = {", mk_mapname(i), table_suffix?table_suffix:"");
		for (j = 0; j < NR_KEYS; j++) {
			if (!(j % 8))
				printf("\n");
			printf("\t0x%04x,", key_map[i]?U((key_map[i])[j]):0xf200);
		}
		printf("\n};\n");
	}

	exit(0);
}

%}

%%
keytable	:
		| keytable line
		;
line		: EOL
		| charsetline
		| altismetaline
		| usualstringsline
		| usualcomposeline
		| keymapline
		| fullline
		| singleline
		| strline
                | compline
		;
charsetline	: CHARSET STRLITERAL EOL
			{
				set_charset((char *) kbs_buf.kb_string);
			}
		;
altismetaline	: ALT_IS_META EOL
			{
				alt_is_meta = 1;
			}
		;
usualstringsline: STRINGS AS USUAL EOL
			{
				strings_as_usual();
			}
		;
usualcomposeline: COMPOSE AS USUAL FOR STRLITERAL EOL
			{
				compose_as_usual((char *) kbs_buf.kb_string);
			}
		  | COMPOSE AS USUAL EOL
			{
				compose_as_usual(0);
			}
		;
keymapline	: KEYMAPS range EOL
			{
				keymaps_line_seen = 1;
			}
		;
range		: range COMMA range0
		| range0
		;
range0		: NUMBER DASH NUMBER
			{
				int i;
				for (i = $1; i <= $3; i++)
					addmap(i,1);
			}
		| NUMBER
			{
				addmap($1,1);
			}
		;
strline		: STRING LITERAL EQUALS STRLITERAL EOL
			{
				if (KTYP($2) != KT_FN)
					lkfatal(_("'%s' is not a function key symbol"),
						syms[KTYP($2)].table[KVAL($2)]);
				kbs_buf.kb_func = KVAL($2);
				addfunc(kbs_buf);
			}
		;
compline        : COMPOSE compsym compsym TO compsym EOL
                        {
				compose($2, $3, $5);
			}
		 | COMPOSE compsym compsym TO rvalue EOL
			{
				compose($2, $3, $5);
			}
                ;
compsym		: CCHAR		{	$$ = $1;		}
		| UNUMBER	{	$$ = $1 ^ 0xf000;	}
		;
singleline	:	{
				mod = 0;
			}
		  modifiers KEYCODE NUMBER EQUALS rvalue EOL
			{
				addkey($4, mod, $6);
			}
		| PLAIN KEYCODE NUMBER EQUALS rvalue EOL
			{
				addkey($3, 0, $5);
			}
		;
modifiers	: modifiers modifier
		| modifier
		;
modifier	: SHIFT		{ mod |= M_SHIFT;	}
		| CONTROL	{ mod |= M_CTRL;	}
		| ALT		{ mod |= M_ALT;		}
		| ALTGR		{ mod |= M_ALTGR;	}
		| SHIFTL	{ mod |= M_SHIFTL;	}
		| SHIFTR	{ mod |= M_SHIFTR;	}
		| CTRLL		{ mod |= M_CTRLL;	}
		| CTRLR		{ mod |= M_CTRLR;	}
		| CAPSSHIFT	{ mod |= M_CAPSSHIFT;	}
		;
fullline	: KEYCODE NUMBER EQUALS rvalue0 EOL
			{
				int i, j;

				if (rvalct == 1) {
					/* Some files do not have a keymaps line, and
					 * we have to wait until all input has been read
					 * before we know which maps to fill. */
					key_is_constant[$2] = 1;

					/* On the other hand, we now have include files,
					 * and it should be possible to override lines
					 * from an include file. So, kill old defs. */
					for (j = 0; j < max_keymap; j++) {
						if (defining[j])
							killkey($2, j);
					}
				}

				if (keymaps_line_seen) {
					i = 0;

					for (j = 0; j < max_keymap; j++) {
						if (defining[j]) {
							if (rvalct != 1 || i == 0)
								addkey($2, j, (i < rvalct) ? key_buf[i] : K_HOLE);
							i++;
						}
					}

					if (i < rvalct)
						lkfatal(_("too many (%d) entries on one line"), rvalct);
				} else {
					for (i = 0; i < rvalct; i++)
						addkey($2, i, key_buf[i]);
				}
			}
		;

rvalue0		:
		| rvalue1 rvalue0
		;
rvalue1		: rvalue
			{
				if (rvalct >= MAX_NR_KEYMAPS)
					lkfatal(_("too many key definitions on one line"));
				key_buf[rvalct++] = $1;
			}
		;
rvalue		: NUMBER	{ $$ = convert_code($1, TO_AUTO);		}
                | PLUS NUMBER	{ $$ = add_capslock($2);			}
		| UNUMBER	{ $$ = convert_code($1^0xf000, TO_AUTO);	}
		| PLUS UNUMBER	{ $$ = add_capslock($2^0xf000);			}
		| LITERAL	{ $$ = $1;					}
                | PLUS LITERAL	{ $$ = add_capslock($2);			}
		;
%%

static void parse_keymap(FILE *fd) {
	stack_push(fd, 0, pathname);

	if (yyparse()) {
		fprintf(stderr, _("syntax error in map file\n"));

		exit(EXIT_FAILURE);
	}
}

int main(int argc, char *argv[])
{
	const char *short_opts = "a:dht:uqvV";
	const struct option long_opts[] = {
		{ "ascii",		no_argument, NULL, 'a' },
		{ "default",		no_argument, NULL, 'd' },
		{ "help",		no_argument, NULL, 'h' },
		{ "suffix", required_argument, NULL, 't'},
		{ "unicode",		no_argument, NULL, 'u' },
		{ "quiet",		no_argument, NULL, 'q' },
		{ "verbose",		no_argument, NULL, 'v' },
		{ "version",		no_argument, NULL, 'V' },
		{ NULL, 0, NULL, 0 }
	};
	int c, i;
	char *table_suffix = NULL;

	set_progname(argv[0]);

	setlocale(LC_ALL, "");
	bindtextdomain(PACKAGE_NAME, LOCALEDIR);
	textdomain(PACKAGE_NAME);

	while ((c = getopt_long(argc, argv, short_opts, long_opts, NULL)) != -1) {
		switch (c) {
		case 'a':
			opta = 1;
			break;
		case 'd':
			optd = 1;
			break;
		case 't':
			table_suffix = optarg;
			break;
		case 'u':
			optu = 1;
			break;
		case 'q':
			quiet = 1;
			break;
		case 'v':
			verbose++;
			break;
		case 'V':
			print_version_and_exit();
		case 'h':
		case '?':
			usage();
		}
	}

	if (optu && opta) {
		fprintf(stderr,
			_("%s: Options --unicode and --ascii are mutually exclusive\n"),
			progname);
		exit(EXIT_FAILURE);
	}

	prefer_unicode = optu;

	for (i = optind; argv[i]; i++) {
		FILE *f;
		char *ev;

		dirpath = dirpath1;
		if ((ev = getenv("LOADKEYS_KEYMAP_PATH")) != NULL) {
			dirpath2[0] = ev;
			dirpath = dirpath2;
		}

		if (optd) {
			/* first read default map - search starts in . */
			optd = 0;
			if ((f = findfile(DEFMAP, dirpath, suffixes)) == NULL) {
				fprintf(stderr, _("Cannot find %s\n"), DEFMAP);
				exit(EXIT_FAILURE);
			}
			goto gotf;
		}

		if (!strcmp(argv[i], "-")) {
			f = stdin;
			strcpy(pathname, "<stdin>");

		} else if ((f = findfile(argv[i], dirpath, suffixes)) == NULL) {
			fprintf(stderr, _("cannot open file %s\n"), argv[i]);
			exit(EXIT_FAILURE);
		}

 gotf:
		parse_keymap(f);
	}

	if (optind == argc) {
		strcpy(pathname, "<stdin>");
		parse_keymap(stdin);
	}

	do_constant();

	mktable(table_suffix);

	exit(EXIT_SUCCESS);
}
