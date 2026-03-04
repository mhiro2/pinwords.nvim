local h = require("bench.bench_helpers")
local matcher = require("pinwords.matcher")

local M = {}

function M.run()
  local results = {}

  h.teardown()
  require("pinwords").setup({})
  h.setup_buffer_with_content()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local match_id = nil
  local stats = h.measure(function()
    match_id = matcher.apply_cword_for_window(win, match_id, "\\V\\c\\<benchword1\\>")
  end, 200)

  table.insert(results, {
    name = "apply_cword_for_window",
    stats = stats,
  })

  h.teardown()
  return results
end

return M
