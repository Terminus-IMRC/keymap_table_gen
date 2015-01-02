#ifndef __HIDMAP_H_INCLUDED__
#define __HIDMAP_H_INCLUDED__

#include <stdint.h>
#include "spbits.h"

	struct hidmap_t {
		uint8_t from_hid;
		uint8_t from_spbits;
		union {
			uint8_t to_hid, to_cons1;
		};
		union {
			uint8_t to_spbits, to_cons2;
		};
		struct hidmap_t *next;
	};

	extern struct hidmap_t *hidmap;

	void hidmap_load(const char *path);

#endif /* __HIDMAP_H_INCLUDED__ */
