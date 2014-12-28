OBJS:=loadkeys.o loadkeys.analyze.o getfd.o ksyms.o xmalloc.o findfile.o

CC:=gcc
RM:=rm -f
YACC:=yacc
LEX:=lex

all: loadkeys

loadkeys: loadkeys.o loadkeys.analyze.o getfd.o ksyms.o xmalloc.o findfile.o

.PHONY: clean
clean:
	$(RM) loadkeys
	$(RM) $(OBJS)
	$(RM) loadkeys.c
	$(RM) loadkeys.analyze.c
