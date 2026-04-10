PREFIX ?= $(HOME)/.local

install:
	@ln -sf "$(CURDIR)/bin/rill" "$(PREFIX)/bin/rill"
	@echo "Installed: $(PREFIX)/bin/rill -> $(CURDIR)/bin/rill"

uninstall:
	@rm -f "$(PREFIX)/bin/rill"
	@echo "Removed: $(PREFIX)/bin/rill"

.PHONY: install uninstall
