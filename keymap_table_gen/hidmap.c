#define _BSD_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include "hidmap.h"
#include "string_utils.h"

struct hidmap_t *hidmap = NULL;
static struct hidmap_t *hidmap_orig = NULL;

static struct hidmap_t* hidmap_alloc();
static void hidmap_process_line(char *s, const int cnt);
static uint8_t hidmap_process_string_number(char **ss, char *store_name, int cnt);
static uint8_t hidmap_process_string_modifier(char **ss, char *store_name, int cnt);
static uint8_t hidmap_process_string_report(char **ss, int cnt);

static
struct hidmap_t*
hidmap_alloc()
{
	struct hidmap_t *p;

	if ((p = malloc(sizeof(struct hidmap_t))) == NULL) {
		fprintf(stderr, "%s:%d: error: failed to malloc p\n", __FILE__, __LINE__);
		exit(EXIT_FAILURE);
	}

	p->next = NULL;

	return p;
}

void
hidmap_load(const char *path)
{
	int cnt;
	FILE *fp;
	char s[0xffff];

	if ((fp = fopen(path, "r")) == NULL) {
		fprintf(stderr, "%s:%d: error: cannot open %s\n", __FILE__, __LINE__, path);
		exit(EXIT_FAILURE);
	}

	for (cnt = 0; fgets(s, 0xffff, fp) != NULL; cnt++) {
		if (s[strlen(s)-1] != '\n') {
			fprintf(stderr, "%s:%d: error: the input line %d is too long or does not end with '\\n'\n", __FILE__, __LINE__, cnt + 1);
			exit(EXIT_FAILURE);
		}
		hidmap_process_line(s, cnt + 1);
	}

	hidmap = hidmap_orig;
	
	return;
}

static
void
hidmap_process_line(char *s, const int cnt)
{
	if (hidmap == NULL)
		hidmap = hidmap_orig = hidmap_alloc();
	else {
		hidmap->next = hidmap_alloc();
		hidmap = hidmap->next;
	}

	hidmap->from_hid = hidmap_process_string_number(&s, "from_hid", cnt);
	hidmap->from_spbits = hidmap_process_string_modifier(&s, "from_spbits", cnt);
	hidmap->from_spbits |= hidmap_process_string_report(&s, cnt);
	switch (hidmap->from_spbits & SPBITS_REPORT_MASK) {
		case SPBITS_REPORT_OUTPUT:
			hidmap->to_hid = hidmap_process_string_number(&s, "to_hid", cnt);
			hidmap->to_spbits = hidmap_process_string_modifier(&s, "to_spbits", cnt);
			break;
		case SPBITS_REPORT_CONSUMER:
			hidmap->to_cons1 = hidmap_process_string_number(&s, "to_cons1", cnt);
			hidmap->to_cons2 = hidmap_process_string_number(&s, "to_cons2", cnt);
			break;
	}

	return;
}

static
uint8_t
hidmap_process_string_number(char **ss, char *store_name, int cnt)
{
	unsigned long hid_tmp;

	errno = 0;
	hid_tmp = strtoul(*ss, ss, 0);
	if (errno == ERANGE) {
		char *rs;

		switch (hid_tmp) {
			case LONG_MIN:
				rs = "underflow";
				break;
			case LONG_MAX:
				rs = "overflow";
				break;
			default:
				rs = "unknown";
		}

		fprintf(stderr, "%s:%d: error: cannot convert string to %s for the reason %s on the input line %d\n", __FILE__, __LINE__, store_name, rs, cnt);
		exit(EXIT_FAILURE);
	}

	if (hid_tmp > 0xff) {
		fprintf(stderr, "%s:%d: error: invalid the range of from_hid on the input line %d\n", __FILE__, __LINE__, cnt);
		exit(EXIT_FAILURE);
	}

	return hid_tmp;
}

static
uint8_t
hidmap_process_string_modifier(char **ss, char *store_name, int cnt)
{
	char *sn;
	uint8_t spbits = SPBITS_NONE;

	*ss = strcpbrk(*ss, " \t");
	if (*ss == NULL) {
		fprintf(stderr, "%s:%d: error: invalid format on the input line %d\n", __FILE__, __LINE__, cnt);
		exit(EXIT_FAILURE);
	}

	do {
		sn = strpbrk(*ss, ", \t\n");
		if (sn == NULL) {
			fprintf(stderr, "%s:%d: error: invalid format on the input line %d\n", __FILE__, __LINE__, cnt);
			exit(EXIT_FAILURE);
		}

		if(! strncasecmp(*ss, "ctrl", sn - *ss))
			spbits |= SPBITS_CTRL;
		else if(! strncasecmp(*ss, "shift", sn - *ss))
			spbits |= SPBITS_SHIFT;
		else if(! strncasecmp(*ss, "alt", sn - *ss))
			spbits |= SPBITS_ALT;
		else if(! strncasecmp(*ss, "gui", sn - *ss))
			spbits |= SPBITS_GUI;
		else if(! strncasecmp(*ss, "none", sn - *ss))
			spbits |= SPBITS_NONE;
		else {
			fprintf(stderr, "%s:%d: error: invalid modifier name for %s on the input line %d\n", __FILE__, __LINE__, store_name, cnt);
			exit(EXIT_FAILURE);
		}

		*ss = sn + 1;
	} while(*sn == ',');

	return spbits;
}

static
uint8_t
hidmap_process_string_report(char **ss, int cnt)
{
	char *sn;
	uint8_t spbits = SPBITS_NONE;

	sn = strpbrk(*ss, " \t");
	if (sn == NULL) {
		fprintf(stderr, "%s:%d: error: invalid format on the input line %d\n", __FILE__, __LINE__, cnt);
		exit(EXIT_FAILURE);
	}

	if (! strncasecmp(*ss, "output", sn - *ss))
		spbits = SPBITS_REPORT_OUTPUT;
	else if(! strncasecmp(*ss, "consumer", sn - *ss))
		spbits = SPBITS_REPORT_CONSUMER;
	else {
		fprintf(stderr, "%s:%d: error: invalid report name on the input line %d\n", __FILE__, __LINE__, cnt);
		exit(EXIT_FAILURE);
	}

	*ss = sn + 1;

	return spbits;
}
