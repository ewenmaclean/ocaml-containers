
INTERFACE_FILES = $(shell find -name '*.mli')
IMPLEMENTATION_FILES = $(shell find -name '*.ml')

TARGETS_LIB = containers.cmxa containers.cma
TARGET_THREAD_LIB = thread_containers.cmxa thread_containers.cma
OPTIONS = -use-ocamlfind

all: lib

# like lib, but with thread-specific modules
all_thread: lib lib_thread

lib:
	ocamlbuild $(OPTIONS) $(TARGETS_LIB)

lib_thread:
	ocamlbuild $(OPTIONS) $(TARGETS_LIB) $(TARGET_THREAD_LIB)

tests:
	ocamlbuild $(OPTIONS) -thread -package oUnit -I . tests/run_tests.native

bench:
	ocamlbuild $(OPTIONS) -package bench -package unix -I . tests/benchs.native

clean:
	ocamlbuild -clean

tags:
	otags *.ml *.mli

.PHONY: all all_thread clean tests tags

