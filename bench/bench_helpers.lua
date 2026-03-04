local M = {}

--- Run fn `iterations` times, return stats in nanoseconds.
--- Discards 5 warmup iterations before measuring.
---@param fn function
---@param iterations? integer
---@return { total_ns: integer, mean_ns: number, min_ns: integer, max_ns: integer, iterations: integer }
function M.measure(fn, iterations)
  iterations = iterations or 100

  for _ = 1, 5 do
    fn()
  end

  local min_ns = math.huge
  local max_ns = 0
  local total_ns = 0

  for _ = 1, iterations do
    local start = vim.uv.hrtime()
    fn()
    local elapsed = vim.uv.hrtime() - start
    total_ns = total_ns + elapsed
    if elapsed < min_ns then
      min_ns = elapsed
    end
    if elapsed > max_ns then
      max_ns = elapsed
    end
  end

  return {
    total_ns = total_ns,
    mean_ns = total_ns / iterations,
    min_ns = min_ns,
    max_ns = max_ns,
    iterations = iterations,
  }
end

--- Print a list of benchmark results as a formatted table.
---@param results { name: string, stats: table }[]
function M.print_results(results)
  local header = string.format("%-45s %8s %12s %12s %12s", "Benchmark", "Iters", "Mean (us)", "Min (us)", "Max (us)")
  print(string.rep("-", #header))
  print(header)
  print(string.rep("-", #header))
  for _, r in ipairs(results) do
    print(
      string.format(
        "%-45s %8d %12.1f %12.1f %12.1f",
        r.name,
        r.stats.iterations,
        r.stats.mean_ns / 1000,
        r.stats.min_ns / 1000,
        r.stats.max_ns / 1000
      )
    )
  end
  print(string.rep("-", #header))
end

--- Create N windows showing the same buffer.
---@param n integer
---@return integer[]
function M.create_windows(n)
  local buf = vim.api.nvim_get_current_buf()
  local wins = { vim.api.nvim_get_current_win() }
  for _ = 2, n do
    local win = vim.api.nvim_open_win(buf, false, { split = "right" })
    table.insert(wins, win)
  end
  return wins
end

--- Fill N slots in global state with dummy patterns.
---@param n integer
function M.fill_slots(n)
  local state = require("pinwords.state")
  for i = 1, n do
    local word = "benchword" .. i
    state.set_slot(i, {
      raw = word,
      pattern = "\\V\\c\\<" .. word .. "\\>",
      hl_group = "PinWord" .. i,
    })
    state.touch_slot(i)
  end
  state.flush_sync()
end

--- Close extra windows, clear matches and state.
function M.teardown()
  local wins = vim.api.nvim_list_wins()
  for i = #wins, 2, -1 do
    if vim.api.nvim_win_is_valid(wins[i]) then
      vim.api.nvim_win_close(wins[i], true)
    end
  end
  vim.fn.clearmatches()
  require("pinwords.state").clear_all()
  require("pinwords.state").flush_sync()
end

--- Set buffer content with 1000 lines containing benchmark words.
function M.setup_buffer_with_content()
  local lines = {}
  for i = 1, 1000 do
    lines[i] = "benchword1 some text benchword2 more benchword3 line" .. i
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

return M
