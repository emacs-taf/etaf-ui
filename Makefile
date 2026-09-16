.DEFAULT_GOAL := check
.NOTPARALLEL:
EMACS ?= emacs
LOAD_PATH = -L . -L lisp -L ../etaf -L ../ebox -L ../ecss -L ../tp
SOURCES = lisp/etaf-ui-style.el lisp/etaf-ui-basic.el lisp/etaf-ui-input.el lisp/etaf-ui-selection.el lisp/etaf-ui-feedback.el lisp/etaf-ui-navigation.el lisp/etaf-ui-surface.el lisp/etaf-ui-table.el lisp/etaf-ui-data.el lisp/etaf-ui-advanced.el etaf-ui.el

TEST_FILES := $(wildcard tests/*-tests.el)
SOURCES += $(wildcard examples/*.el) $(wildcard benchmarks/*.el) scripts/etaf-ui-gui.el

.PHONY: all compile check checkdoc load clean

all: check

compile:
	rm -f *.elc lisp/*.elc tests/*.elc examples/*.elc benchmarks/*.elc scripts/*.elc
	$(EMACS) -Q --batch $(LOAD_PATH) \
		--eval '(setq load-prefer-newer t byte-compile-error-on-warn t)' \
		--eval '(require (quote cl-lib))' \
		--eval '(unless (cl-every (function byte-compile-file) (quote ($(foreach file,$(SOURCES),"$(file)")))) (kill-emacs 1))'

load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(require (quote etaf-ui))' \
		--eval '(princ "etaf-ui load OK\n")'

checkdoc:
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (append (directory-files "lisp" t "\\.el$$") (directory-files-recursively "tests" "\\.el$$") (directory-files-recursively "scripts" "\\.el$$"))) (checkdoc-file file)))'

check: structure-check compile acceptance api-check performance-tool-check

clean:
	rm -f *.elc lisp/*.elc tests/*.elc examples/*.elc benchmarks/*.elc scripts/*.elc

.PHONY: structure-check setup-hooks gui-check
structure-check:
	python3 scripts/check-repository.py
setup-hooks:
	git config --local core.hooksPath .githooks

GUI_EXAMPLE ?= surfaces
gui-check:
	scripts/run-gui-check.sh $(GUI_EXAMPLE)

PERF_ARGS ?=
.PHONY: perf-check performance-tool-check
perf-check:
	python3 scripts/run-gallery-performance.py $(PERF_ARGS)
performance-tool-check:
	python3 -m unittest discover -s tests/tools -p 'test_gallery_performance.py'

.PHONY: acceptance
acceptance:
	python3 scripts/run-acceptance.py --emacs "$(EMACS)"

.PHONY: api-check
api-check:
	$(EMACS) -Q --batch -L . $(API_PROVIDER_PATH) --eval '(setq load-prefer-newer t)' -l scripts/check-api.el
API_PROVIDER_PATH = -L ../ecss -L ../tp -L ../ekp -L ../ebox -L ../etaf -L ../etaf-db -L ../ebox-playground -L ../etaf-playground

.PHONY: test
test: acceptance
