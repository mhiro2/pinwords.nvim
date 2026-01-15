.PHONY: deps deps-mini deps-telescope deps-plenary fmt lint stylua stylua-check selene test

NVIM ?= nvim
GIT ?= git
MINI_PATH ?= deps/mini.nvim
TELESCOPE_PATH ?= deps/telescope.nvim
PLUG_PATH ?= deps/plenary.nvim

deps: deps-mini deps-plenary deps-telescope

deps-mini:
	@if [ ! -d "$(MINI_PATH)" ]; then \
		mkdir -p "$$(dirname "$(MINI_PATH)")"; \
		$(GIT) clone --depth 1 https://github.com/echasnovski/mini.nvim "$(MINI_PATH)"; \
	fi

deps-plenary:
	@if [ ! -d "$(PLUG_PATH)" ]; then \
		mkdir -p "$$(dirname "$(PLUG_PATH)")"; \
		$(GIT) clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$(PLUG_PATH)"; \
	fi

deps-telescope: deps-plenary
	@if [ ! -d "$(TELESCOPE_PATH)" ]; then \
		mkdir -p "$$(dirname "$(TELESCOPE_PATH)")"; \
		$(GIT) clone --depth 1 https://github.com/nvim-telescope/telescope.nvim "$(TELESCOPE_PATH)"; \
	fi

fmt: stylua

lint: stylua-check selene

stylua:
	stylua .

stylua-check:
	stylua --check .

selene:
	selene ./lua ./plugin ./tests

test: deps
	MINI_PATH="$(MINI_PATH)" TELESCOPE_PATH="$(TELESCOPE_PATH)" PLUG_PATH="$(PLUG_PATH)" \
		$(NVIM) --headless -u tests/minimal_init.lua -c "lua require('tests.run').run()" -c "qa"
