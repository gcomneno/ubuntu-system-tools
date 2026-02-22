CONFIGDIR ?= $(HOME)/.config/ubuntu-system-tools
CONFIGFILE ?= $(CONFIGDIR)/config.env

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

TOOLS := bin/hdd_cleanup bin/security-health bin/who-uses

.PHONY: init-config install uninstall check print-prefix install-system uninstall-system

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
	@echo "PREFIX=$(PREFIX)"
	@echo "BINDIR=$(BINDIR)"
	@echo "DESTDIR=$(DESTDIR)"

install:
	@install -d "$(DESTDIR)$(BINDIR)" 2>/dev/null || { \
	  echo "ERROR: cannot write to $(DESTDIR)$(BINDIR)."; \
	  echo "Hint: system-wide install -> sudo make install PREFIX=/usr/local"; \
	  exit 1; \
	}
	install -m 0755 $(TOOLS) "$(DESTDIR)$(BINDIR)/"
	@echo "OK: installed to $(DESTDIR)$(BINDIR)"
	@echo "Hint: run 'command -v who-uses && who-uses --help'"

uninstall:
	@for t in $(notdir $(TOOLS)); do \
	  echo "RM $(DESTDIR)$(BINDIR)/$$t"; \
	  rm -f -- "$(DESTDIR)$(BINDIR)/$$t"; \
	done

install-system:
	@sudo $(MAKE) install PREFIX=/usr/local

uninstall-system:
	@sudo $(MAKE) uninstall PREFIX=/usr/local

check:
	tests/selftest_hdd_cleanup.sh