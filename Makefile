# Test targets. Sly and SLIME checkouts are expected in .deps/ (see `make deps`)
# or wherever SLY_DIR / SLIME_DIR point.

EMACS     ?= emacs
SBCL      ?= sbcl
SLY_DIR   ?= .deps/sly
SLIME_DIR ?= .deps/slime

EL    = on-main.el on-main-sly.el on-main-slime.el
BATCH = $(EMACS) -Q --batch -L .

.PHONY: test deps compile unit smoke integration clean

test: compile unit smoke integration

deps:
	test -d $(SLY_DIR)   || git clone --depth 1 https://github.com/joaotavora/sly.git $(SLY_DIR)
	test -d $(SLIME_DIR) || git clone --depth 1 https://github.com/slime/slime.git $(SLIME_DIR)

compile:
	$(BATCH) -L $(SLY_DIR) -L $(SLIME_DIR) \
	  --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile $(EL)
	rm -f *.elc

unit:
	$(BATCH) -l test/on-main-test.el -f ert-run-tests-batch-and-exit

smoke:
	$(SBCL) --non-interactive --load test/smoke.lisp
	ON_MAIN_BACKEND=slynk ON_MAIN_LOADER=$(abspath $(SLY_DIR))/slynk/slynk-loader.lisp \
	  $(SBCL) --non-interactive --load test/smoke.lisp
	ON_MAIN_BACKEND=swank ON_MAIN_LOADER=$(abspath $(SLIME_DIR))/swank-loader.lisp \
	  $(SBCL) --non-interactive --load test/smoke.lisp

integration:
	SBCL=$(SBCL) $(BATCH) -L $(SLY_DIR)   -l test/integration.el -f on-main-test-sly
	SBCL=$(SBCL) $(BATCH) -L $(SLIME_DIR) -l test/integration.el -f on-main-test-slime

clean:
	rm -f *.elc
