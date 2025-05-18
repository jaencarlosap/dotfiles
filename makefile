.PHONY: install_nvim clean_system

install_nvim:
	@echo "Installing Neovim..."
	@bash setup_nvim.sh

clean_system:
	@echo "Cleaning up system..."
	@bash clean_system.sh
	@echo "System cleaned."
	@echo "Please restart your terminal to apply changes."

