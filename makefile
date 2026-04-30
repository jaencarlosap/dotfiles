.PHONY: install_nvim clean_system clean_system_dry dtool install_dtool

# The shell scripts live in older_scripts/ as a fallback during the migration
# to dtool. They will be removed once dtool is verified.
install_nvim:
	@echo "Installing Neovim..."
	@bash older_scripts/setup_nvim.sh

clean_system:
	@bash older_scripts/clean_system.sh

clean_system_dry:
	@bash older_scripts/clean_system.sh --dry-run

dtool:
	cd dtool && go build -o dtool .

install_dtool: dtool
	mkdir -p $(HOME)/.local/bin
	cp dtool/dtool $(HOME)/.local/bin/dtool
	@echo "Installed to $(HOME)/.local/bin/dtool — make sure that dir is on your PATH."

