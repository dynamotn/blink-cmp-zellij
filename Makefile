.PHONY: test format lint

test:
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec {minimal_init = 'tests/minimal_init.lua', sequential = true}"

format:
	stylua lua tests

lint:
	stylua --check lua tests
