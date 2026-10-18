EMACS ?= emacs
# Watchdog: batch ERT can hang on stdin/loops. Kill after TIMEOUT seconds.
TIMEOUT ?= 120

EL := devops.el devops-lob.el devops-drift.el
TEST := devops-test.el

# Trampolines off: mocking built-ins (completing-read) otherwise triggers
# a native compile, which fails on machines with a broken libgccjit.
BATCH := $(EMACS) --batch -L . \
  --eval "(setq native-comp-enable-subr-trampolines nil)"
WATCHDOG := perl -e 'alarm shift; exec @ARGV' $(TIMEOUT)

.PHONY: test test-% compile checkdoc clean

## Run full ERT suite (mirrors CI)
test:
	$(WATCHDOG) $(BATCH) \
	  --eval "(require 'devops)" \
	  --eval "(require 'devops-test)" \
	  -f ert-run-tests-batch-and-exit

## Run tests matching a regex: make test-PATTERN
test-%:
	$(WATCHDOG) $(BATCH) \
	  --eval "(require 'devops)" \
	  --eval "(require 'devops-test)" \
	  --eval "(ert-run-tests-batch-and-exit \"$*\")"

## Byte-compile sources, treat warnings as errors
compile:
	$(BATCH) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  -f batch-byte-compile $(EL) $(TEST)

## Run checkdoc on sources, fail on any warning
checkdoc:
	$(WATCHDOG) $(BATCH) \
	  --eval "(require 'checkdoc)" \
	  --eval "(let* ((n 0) \
	                 (orig checkdoc-create-error-function) \
	                 (checkdoc-create-error-function \
	                  (lambda (&rest args) (setq n (1+ n)) (apply orig args)))) \
	            (dolist (f command-line-args-left) (checkdoc-file f)) \
	            (kill-emacs (min n 1)))" \
	  $(EL)

clean:
	rm -f *.elc
