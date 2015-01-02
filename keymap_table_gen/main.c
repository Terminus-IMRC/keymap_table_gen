#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "defkeymap_table.h"
#include "defkeymap_table_jp106.h"
#include "HIDKeyboard.h"
#include "keycode2hidusage_table.h"
#include "spbits.h"

struct keymap_node_t{
	uint8_t from_hid, to_hid;
	uint8_t from_spbits, to_spbits;
	struct keymap_node_t *next;
};

typedef struct keymap_node_t keymap_node_t;

keymap_node_t *knodes[0xff];
int max_element_depth=0;

void entry_init()
{
	int i;

	for(i=0; i<0xff; i++)
		knodes[i]=NULL;

	return;
}

keymap_node_t* allocate_entry()
{
	keymap_node_t *p;

	p=malloc(sizeof(keymap_node_t));
	if(p==NULL){
		fprintf(stderr, "%s:%d: error: failed to malloc p\n", __FILE__, __LINE__);
		exit(EXIT_FAILURE);
	}

	p->next=NULL;

	return p;
}

void add_entry(int from_hid, uint8_t from_spbits, int to_hid, uint8_t to_spbits)
{
	int e;
	keymap_node_t *p;

	if(from_hid==0)
		return;

	e=(from_hid+from_spbits)%0xff;

	p=knodes[e];
	if(p==NULL){
		p=allocate_entry();
		knodes[e]=p;
	}else{
		int element_depth=0;

		for(;;){
				return;
			element_depth++;
			if(p->next==NULL)
				break;
			p=p->next;
		}
		if(element_depth>max_element_depth)
			max_element_depth=element_depth;
		p->next=allocate_entry();
		p=p->next;
	}

	p->from_hid=from_hid;
	p->from_spbits=from_spbits;
	p->to_hid=to_hid;
	p->to_spbits=to_spbits;

	return;
}

void print_entries()
{
	int i, j;
	keymap_node_t *p;

	printf("#include <stdint.h>\n");
	printf("#include <avr/pgmspace.h>\n");

	printf("\n");

	printf("#define KEYMAP_NELEMENTS %d\n", max_element_depth+1);
	printf("#define KEYMAP_HASH_MAX %d\n", 0xff);

	printf("\n");

#ifndef __2DIM
	printf("#define read_keymap_table(i, j, k) (pgm_read_byte(&(keymap_table[i][j][k])))\n");
#else
	printf("#define read_keymap_table(i, j, k) (pgm_read_byte(&(keymap_table[i][j*4+k])))\n");
#endif

	printf("\n");

#ifndef __2DIM
	printf("static const uint8_t keymap_table[KEYMAP_HASH_MAX][KEYMAP_NELEMENTS][4] PROGMEM ={\n");
#else
	printf("static const uint8_t keymap_table[KEYMAP_HASH_MAX][KEYMAP_NELEMENTS*4] PROGMEM ={\n");
#endif
	for(i=0; i<0xff; i++){
		printf("	{\n");
		for(j=0, p=knodes[i]; j<max_element_depth+1; j++, p=(p!=NULL?p->next:NULL)){
#ifndef __2DIM
			printf("		{");
#endif
			printf("%d, ", p!=NULL?p->from_hid:0);
			printf("%d, ", p!=NULL?p->from_spbits:0);
			printf("%d, ", p!=NULL?p->to_hid:0);
			printf("%d", p!=NULL?p->to_spbits:0);
#ifndef __2DIM
			printf("},\n");
#else
			printf(",\n");
#endif
		}
		printf("	},\n");
	}
	printf("};\n");

	return;
}

void process_table(uint16_t defmap[NR_KEYS], uint16_t map[NR_KEYS], uint8_t from_spbits)
{
	int i;

	for(i=0; i<NR_KEYS; i++){
		if((defmap[i]&0xff)!=(map[i]&0xff)){
			int from_hid, to_hid;
			uint8_t to_spbits=0;

			from_hid=keycode2hidusage_table[i];
			to_hid=HIDTable[map[i]&0xff];
			switch(modifierTable[map[i]&0xff]){
				case SHIFT:
					to_spbits|=SPBITS_SHIFT;
					break;
				case 0:
					to_spbits=0;
					break;
			}

			add_entry(from_hid, from_spbits, to_hid, to_spbits);
		}
	}

	return;
}
				
int main()
{
	entry_init();

	process_table(plain_map, plain_map_jp106, SPBITS_NONE);
	process_table(shift_map, shift_map_jp106, SPBITS_SHIFT);
	process_table(altgr_map, altgr_map_jp106, SPBITS_GUI);
	process_table(shift_altgr_map, shift_altgr_map_jp106, SPBITS_SHIFT|SPBITS_GUI);
	process_table(ctrl_map, ctrl_map_jp106, SPBITS_CTRL);
	process_table(shift_ctrl_map, shift_ctrl_map_jp106, SPBITS_SHIFT|SPBITS_CTRL);
	process_table(altgr_ctrl_map, altgr_ctrl_map_jp106, SPBITS_GUI|SPBITS_CTRL);
	process_table(shift_altgr_ctrl_map, shift_altgr_ctrl_map_jp106, SPBITS_SHIFT|SPBITS_GUI|SPBITS_CTRL);
	process_table(alt_map, alt_map_jp106, SPBITS_ALT);
	process_table(shift_alt_map, shift_alt_map_jp106, SPBITS_SHIFT|SPBITS_ALT);
	process_table(altgr_alt_map, altgr_alt_map_jp106, SPBITS_GUI|SPBITS_ALT);
	process_table(shift_altgr_alt_map, shift_altgr_alt_map_jp106, SPBITS_SHIFT|SPBITS_GUI|SPBITS_ALT);
	process_table(ctrl_alt_map, ctrl_alt_map_jp106, SPBITS_CTRL|SPBITS_ALT);
	process_table(shift_ctrl_alt_map, shift_ctrl_alt_map_jp106, SPBITS_SHIFT|SPBITS_CTRL|SPBITS_ALT);
	process_table(altgr_ctrl_alt_map, altgr_ctrl_alt_map_jp106, SPBITS_GUI|SPBITS_CTRL|SPBITS_ALT);
	process_table(shift_altgr_ctrl_alt_map, shift_altgr_ctrl_alt_map_jp106, SPBITS_SHIFT|SPBITS_GUI|SPBITS_CTRL|SPBITS_ALT);

	print_entries();

	return 0;
}
