EMACS ?= emacs
LOAD_PATH = -L . -L ../etaf -L ../ebox -L ../ecss -L ../tp
SOURCES = etaf-ui-style.el etaf-ui-basic.el etaf-ui-table.el etaf-ui-data.el etaf-ui.el

TEST_FILES := $(wildcard tests/*-tests.el)

.PHONY: all compile test m0a-inventory check checkdoc load clean

all: check

compile:
	rm -f *.elc tests/*.elc
	$(EMACS) -Q --batch $(LOAD_PATH) \
		--eval '(setq load-prefer-newer t byte-compile-error-on-warn t)' \
		--eval '(require (quote cl-lib))' \
		--eval '(unless (cl-every (function byte-compile-file) (quote ($(foreach file,$(SOURCES),"$(file)")))) (kill-emacs 1))'

test: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		$(foreach test,$(TEST_FILES),-l $(test)) -f ert-run-tests-batch-and-exit

m0a-inventory:
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		-l scripts/etaf-ui-m0a-inventory.el -f etaf-ui-m0a-inventory-batch

load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(require (quote etaf-ui))' \
		--eval '(princ "etaf-ui load OK\n")'

checkdoc:
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (append (directory-files "." t "\\.el$$") (directory-files-recursively "tests" "\\.el$$") (directory-files-recursively "scripts" "\\.el$$"))) (checkdoc-file file)))'

check: checkdoc compile test

clean:
	rm -f *.elc tests/*.elc
