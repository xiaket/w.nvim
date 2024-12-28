GROUP_DEPTH ?= 1
NVIM_EXEC ?= nvim

all: test

test:
	$(NVIM_EXEC) --version | head -n 1 && echo ''
	$(NVIM_EXEC) --headless --noplugin -u ./tests/init_tests.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua MiniTest.run({ execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = $(GROUP_DEPTH) }) } })"

test_file:
	$(NVIM_EXEC) --version | head -n 1 && echo ''
	$(NVIM_EXEC) --headless --noplugin -u ./tests/init_tests.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua MiniTest.run_file('$(FILE)', { execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = $(GROUP_DEPTH) }) } })"

# make test_case FILE=tests/test_layout.lua CASE="should_handle_complex_split_operations"
test_case:
	$(NVIM_EXEC) --version | head -n 1 && echo ''
	$(NVIM_EXEC) --headless --noplugin -u ./tests/init_tests.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua local T = dofile('$(FILE)'); if T.setup then T.setup() end" \
		-c "lua MiniTest.run_file('$(FILE)', { execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = $(GROUP_DEPTH) }) }, collect = {filter_cases = function(case) return case.desc[3] == '$(CASE)' end }})"
