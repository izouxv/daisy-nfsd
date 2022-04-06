DFY_FILES := $(shell find src -name "*.dfy")
OK_FILES := $(DFY_FILES:.dfy=.dfy.ok)

# use DAFNY_CORES instead of a load factor since /vcsLoad is broken in Dafny 3.5.0
#DAFNY_LOAD := 0.5

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	NUM_CORES := $(shell sysctl -n hw.ncpu)
else
	NUM_CORES := $(shell nproc)
endif
DAFNY_CORES ?= $(shell expr $(NUM_CORES) / 2)

# these arguments don't affect verification outcomes
DAFNY_BASIC_ARGS = /compile:0 /compileTarget:go /timeLimit:20 /vcsCores:$(DAFNY_CORES)

DAFNY_ARGS := /noNLarith /arith:5
DAFNY=./etc/dafnyq $(DAFNY_BASIC_ARGS) $(DAFNY_ARGS)

Q:=@

default: all

compile: dafnygen/dafnygen.go

verify: $(OK_FILES)

all: verify compile

.dafnydeps.d: $(DFY_FILES) etc/dafnydep
	@echo "DAFNYDEP"
	$(Q)./etc/dafnydep $(DFY_FILES) > $@

# do not try to build dependencies if cleaning
ifeq ($(filter clean,$(MAKECMDGOALS)),)
-include .dafnydeps.d
endif

# allow non-linear reasoning for nonlin directory specifically
src/nonlin/%.dfy.ok: DAFNY_ARGS = /arith:1

%.dfy.ok: %.dfy
	@echo "DAFNY $<"
	$(Q)$(DAFNY) "$<"
	$(Q)touch "$@"

# Compilation produces output in dafnygen-go, which we preprocess with
# dafnygen-imports.py to change import paths (for go module compatibility) and
# to place the output under dafnygen without a src directory.
#
# We then run gofmt to simplify the code for readability and goimports to clean
# up unused imports emitted by Dafny.
dafnygen/dafnygen.go: src/compile.dfy $(DFY_FILES)
	@echo "DAFNY COMPILE $<"
	$(Q)$(DAFNY) /countVerificationErrors:0 /spillTargetCode:2 /out dafnygen $<
	$(Q)rm -rf dafnygen
	$(Q)cd dafnygen-go/src && ../../etc/dafnygen-imports.py ../../dafnygen
	$(Q)rm -r dafnygen-go
	$(Q)gofmt -w -r '(a) -> a' ./dafnygen
	$(Q)goimports -w ./dafnygen

clean:
	@echo "CLEAN"
	$(Q)find . -name "*.dfy.ok" -delete
	$(Q)rm -f .dafnydeps.d
	$(Q)rm -rf dafnygen
	$(Q)rm -f daisy-nfsd cpu.prof mem.prof nfs.out
