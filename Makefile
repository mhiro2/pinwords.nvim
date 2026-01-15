.PHONY: deps deps-mini fmt lint stylua stylua-check selene test

NVIM ?= nvim
GIT ?= git
MINI_PATH ?= deps/mini.nvim

deps: deps-mini

deps-mini:
	@if [ ! -d "$(MINI_PATH)" ]; then \
		mkdir -p "$$(dirname "$(MINI_PATH)")"; \
		$(GIT) clone --depth 1 https://github.com/echasnovski/mini.nvim "$(MINI_PATH)"; \
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
	MINI_PATH="$(MINI_PATH)" \
		$(NVIM) --headless -u tests/minimal_init.lua -c "lua require('tests.run').run()" -c "qa"
