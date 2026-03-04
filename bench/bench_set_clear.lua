local h = require("bench.bench_helpers")

local M = {}

function M.run()
  local results = {}

  for _, num_wins in ipairs({ 1, 5, 10 }) do
    h.teardown()
    require("pinwords").setup({ flash = { enabled = false } })
    h.create_windows(num_wins)
    h.setup_buffer_with_content()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local pinwords = require("pinwords")
    local state = require("pinwords.state")

    local stats = h.measure(function()
      pinwords.set(1)
      state.flush_sync()
      pinwords.clear(1)
      state.flush_sync()
    end, 50)

    table.insert(results, {
      name = string.format("set+clear cycle  wins=%d", num_wins),
      stats = stats,
    })
  end

  h.teardown()
  return results
end

return M
