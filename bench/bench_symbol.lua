local h = require("bench.bench_helpers")

local M = {}

function M.run()
  local results = {}

  h.teardown()
  require("pinwords").setup({ flash = { enabled = false } })

  -- Use Lua code as buffer content for Treesitter parsing
  local lines = {}
  for i = 1, 200 do
    lines[#lines + 1] = string.format("local function bench_func_%d(x, y)", i)
    lines[#lines + 1] = "  return x + y"
    lines[#lines + 1] = "end"
    lines[#lines + 1] = ""
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "lua"

  -- Check if Lua parser is available
  local parser_ok, parser = pcall(vim.treesitter.get_parser, 0, "lua")
  if not parser_ok then
    print("SKIP: lua treesitter parser not available")
    return results
  end
  parser:parse()

  local symbol = require("pinwords.symbol")

  -- Bench: get_symbol_at_cursor on identifier node
  vim.api.nvim_win_set_cursor(0, { 1, 16 }) -- on function name
  local stats = h.measure(function()
    symbol.get_symbol_at_cursor()
  end, 200)
  table.insert(results, {
    name = "symbol: get_symbol (on identifier)",
    stats = stats,
  })

  -- Bench: get_symbol_at_cursor on keyword (needs parent traversal)
  vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- on "function" keyword
  stats = h.measure(function()
    symbol.get_symbol_at_cursor()
  end, 200)
  table.insert(results, {
    name = "symbol: get_symbol (on keyword)",
    stats = stats,
  })

  -- Bench: set() with source="symbol" (full pipeline)
  local pinwords = require("pinwords")
  local state = require("pinwords.state")
  vim.api.nvim_win_set_cursor(0, { 1, 16 })
  stats = h.measure(function()
    pinwords.set(1, { source = "symbol" })
    state.flush_sync()
    pinwords.clear(1)
    state.flush_sync()
  end, 50)
  table.insert(results, {
    name = "symbol: set+clear cycle (source=symbol)",
    stats = stats,
  })

  -- Bench: set() with cword for comparison
  vim.api.nvim_win_set_cursor(0, { 1, 16 })
  stats = h.measure(function()
    pinwords.set(1)
    state.flush_sync()
    pinwords.clear(1)
    state.flush_sync()
  end, 50)
  table.insert(results, {
    name = "symbol: set+clear cycle (source=cword)",
    stats = stats,
  })

  h.teardown()
  return results
end

return M
