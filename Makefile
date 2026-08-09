CONFIGDIR ?= $(HOME)/.config/ubuntu-system-tools
CONFIGFILE ?= $(CONFIGDIR)/config.env

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
FORCE ?= 0

TOOLS := bin/hdd_cleanup bin/security-health bin/who-uses bin/printer-doctor bin/garbage-collector bin/bulk-epub-to-azw3 bin/bulk-ebook-convert bin/pdf2epub bin/safe-uninstall bin/audio-transcribe bin/kernel-health

.PHONY: \
	init-config \
	install \
	install-links \
	install-copy \
	uninstall \
	check \
	print-prefix \
	install-system \
	uninstall-system

init-config:
	@mkdir -p "$(CONFIGDIR)"
	@if [ -f "$(CONFIGFILE)" ]; then \
	  echo "INFO: config already exists: $(CONFIGFILE)"; \
	else \
	  cp config/config.env.example "$(CONFIGFILE)"; \
	  echo "OK: created config: $(CONFIGFILE)"; \
	  echo "Edit it to match your paths."; \
	fi

print-prefix:
	@echo "REPO_ROOT=$(REPO_ROOT)"
	@echo "PREFIX=$(PREFIX)"
	@echo "BINDIR=$(BINDIR)"
	@echo "DESTDIR=$(DESTDIR)"
	@echo "FORCE=$(FORCE)"

install: install-links

install-links:
	@if [ -n "$(DESTDIR)" ]; then \
	  echo "ERROR: DESTDIR is not supported for symlink installation."; \
	  echo "Use 'make install-copy DESTDIR=... PREFIX=...' instead."; \
	  exit 1; \
	fi
	@install -d "$(BINDIR)" 2>/dev/null || { \
	  echo "ERROR: cannot write to $(BINDIR)."; \
	  exit 1; \
	}
	@set -eu; \
	for tool in $(TOOLS); do \
	  src="$(REPO_ROOT)/$$tool"; \
	  name="$${tool##*/}"; \
	  dest="$(BINDIR)/$$name"; \
	  if [ -L "$$dest" ]; then \
	    current="$$(readlink -- "$$dest")"; \
	    if [ "$$current" = "$$src" ]; then \
	      echo "OK   $$dest -> $$src"; \
	      continue; \
	    fi; \
	    echo "ERROR: refusing to replace foreign symlink: $$dest -> $$current"; \
	    exit 1; \
	  elif [ -e "$$dest" ]; then \
	    if [ -f "$$dest" ] && cmp -s -- "$$src" "$$dest"; then \
	      echo "MIGRATE identical copy: $$dest"; \
	      rm -f -- "$$dest"; \
	    else \
	      echo "ERROR: refusing to replace unrelated file: $$dest"; \
	      exit 1; \
	    fi; \
	  fi; \
	  ln -s -- "$$src" "$$dest"; \
	  echo "LINK $$dest -> $$src"; \
	done
	@echo "OK: linked tools into $(BINDIR)"
	@echo "NOTE: moving or deleting this repository will break these links."
	@echo "Hint: use 'make install-copy' for autonomous copies."
	@echo "Hint: bulk-ebook-convert needs Calibre for real conversions — sudo apt install calibre"

install-copy:
	@install -d "$(DESTDIR)$(BINDIR)" 2>/dev/null || { \
	  echo "ERROR: cannot write to $(DESTDIR)$(BINDIR)."; \
	  echo "Hint: system-wide install -> sudo make install-copy PREFIX=/usr/local"; \
	  exit 1; \
	}
	@set -eu; \
	for tool in $(TOOLS); do \
	  src="$(REPO_ROOT)/$$tool"; \
	  name="$${tool##*/}"; \
	  dest="$(DESTDIR)$(BINDIR)/$$name"; \
	  if [ -e "$$dest" ] || [ -L "$$dest" ]; then \
	    if [ "$(FORCE)" != "1" ] && { [ -L "$$dest" ] || [ ! -f "$$dest" ] || ! cmp -s -- "$$src" "$$dest"; }; then \
	      echo "ERROR: refusing to overwrite unrelated destination: $$dest"; \
	      echo "Use FORCE=1 only after verifying the destination."; \
	      exit 1; \
	    fi; \
	  fi; \
	  install -m 0755 -- "$$src" "$$dest"; \
	  echo "COPY $$src -> $$dest"; \
	done
	@echo "OK: copied tools into $(DESTDIR)$(BINDIR)"

uninstall:
	@set -eu; \
	failed=0; \
	for tool in $(TOOLS); do \
	  src="$(REPO_ROOT)/$$tool"; \
	  name="$${tool##*/}"; \
	  dest="$(DESTDIR)$(BINDIR)/$$name"; \
	  if [ ! -e "$$dest" ] && [ ! -L "$$dest" ]; then \
	    continue; \
	  fi; \
	  if [ "$(FORCE)" = "1" ]; then \
	    echo "RM $$dest"; \
	    rm -f -- "$$dest"; \
	  elif [ -L "$$dest" ] && [ "$$(readlink -- "$$dest")" = "$$src" ]; then \
	    echo "RM $$dest"; \
	    rm -f -- "$$dest"; \
	  elif [ -f "$$dest" ] && cmp -s -- "$$src" "$$dest"; then \
	    echo "RM $$dest"; \
	    rm -f -- "$$dest"; \
	  else \
	    echo "ERROR: refusing to remove unrelated or divergent destination: $$dest"; \
	    failed=1; \
	  fi; \
	done; \
	exit "$$failed"

install-system:
	@sudo $(MAKE) install-copy PREFIX=/usr/local

uninstall-system:
	@sudo $(MAKE) uninstall PREFIX=/usr/local FORCE=1

check:
	tests/selftest_hdd_cleanup.sh
	tests/selftest_printer_doctor.sh
	tests/selftest_garbage_collector.sh
	tests/selftest_bulk_epub_to_azw3.sh
	tests/selftest_kernel_health.sh
	tests/selftest_pdf2epub.sh
	tests/selftest_safe_uninstall.sh
	tests/selftest_audio_transcribe.sh
	tests/selftest_install.sh
