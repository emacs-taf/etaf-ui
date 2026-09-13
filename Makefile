.DEFAULT_GOAL := check
.NOTPARALLEL:
EMACS ?= emacs
LOAD_PATH = -L lisp -L ../etaf/lisp -L ../ebox/lisp -L ../ecss/lisp -L ../tp/lisp
SOURCES = lisp/etaf-ui-style.el lisp/etaf-ui-basic.el lisp/etaf-ui-table.el lisp/etaf-ui-data.el lisp/etaf-ui.el

TEST_FILES := $(wildcard tests/*-tests.el)

.PHONY: all compile test check checkdoc load clean

all: check

compile:
	rm -f lisp/*.elc tests/*.elc
	$(EMACS) -Q --batch $(LOAD_PATH) \
		--eval '(setq load-prefer-newer t byte-compile-error-on-warn t)' \
		--eval '(require (quote cl-lib))' \
		--eval '(unless (cl-every (function byte-compile-file) (quote ($(foreach file,$(SOURCES),"$(file)")))) (kill-emacs 1))'

test: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		$(foreach test,$(TEST_FILES),-l $(test)) -f ert-run-tests-batch-and-exit

load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(require (quote etaf-ui))' \
		--eval '(princ "etaf-ui load OK\n")'

checkdoc:
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (append (directory-files "lisp" t "\\.el$$") (directory-files-recursively "tests" "\\.el$$") (directory-files-recursively "scripts" "\\.el$$"))) (checkdoc-file file)))'

check: structure-check compile acceptance

clean:
	rm -f lisp/*.elc tests/*.elc

.PHONY: structure-check setup-hooks
structure-check:
	python3 scripts/check-repository.py
setup-hooks:
	git config --local core.hooksPath .githooks

.PHONY: acceptance
acceptance:
	python3 scripts/run-acceptance.py --emacs "$(EMACS)"
