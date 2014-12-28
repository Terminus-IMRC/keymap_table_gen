/*
 * Copyright (c) 2014 Yukimasa Sugizaki
 */

/*
 * Author: Yukimasa Sugizaki; derived from kbd-1.15.3
 */

#include "kbd.h"
#include "nls.h"
#include "config.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

char *progname;

static inline void
set_progname(char *name) {
	char *p;

	p = strrchr(name, '/');
	progname = (p ? p+1 : name);
}

static inline void attr_noreturn
print_version_and_exit(void) {
	printf(_("%s from %s\n"), progname, PACKAGE_STRING);
	exit(0);
}
