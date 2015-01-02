#include <stdio.h>

char*
strcpbrk(const char *s, const char *accept)
{
	while (*s != '\0') {
		const char *a = accept;

		while (*a != '\0')
			if (*a++ == *s)
				goto outer;
		return (char*)s;
outer:
		s++;
	}

	return NULL;
}
