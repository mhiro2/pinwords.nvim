-- Benchmark runner for pinwords.nvim
-- Usage: nvim --headless -u NONE -c "lua dofile('bench/run.lua')" -c "qa"

local cwd = vim.fn.getcwd()

vim.opt.runtimepath:append(cwd)

package.path = table.concat({
  cwd .. "/?.lua",
  cwd .. "/?/init.lua",
  package.path,
}, ";")

vim.opt.swapfile = false
vim.opt.writebackup = false
vim.opt.shortmess:append("W")

local bench_modules = {
  "bench.bench_reapply",
  "bench.bench_apply",
  "bench.bench_clear",
  "bench.bench_set_clear",
  "bench.bench_jump",
  "bench.bench_cword",
  "bench.bench_symbol",
}

local helpers = require("bench.bench_helpers")
local all_results = {}

for _, mod_name in ipairs(bench_modules) do
  local ok, mod = pcall(require, mod_name)
  if ok and mod.run then
    print("\n== " .. mod_name .. " ==")
    helpers.teardown()
    local results = mod.run()
    helpers.print_results(results)
    for _, r in ipairs(results) do
      table.insert(all_results, r)
    end
  else
    print("SKIP: " .. mod_name .. " (" .. tostring(mod) .. ")")
  end
end

print("\n== SUMMARY ==")
helpers.print_results(all_results)
