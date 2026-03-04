local h = require("bench.bench_helpers")
local jump = require("pinwords.jump")
local matcher = require("pinwords.matcher")

local M = {}

function M.run()
  local results = {}

  for _, num_slots in ipairs({ 1, 5, 9 }) do
    h.teardown()
    require("pinwords").setup({ slots = num_slots })
    h.setup_buffer_with_content()
    h.fill_slots(num_slots)
    local win = vim.api.nvim_get_current_win()
    matcher.reapply_all_for_window(win)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local stats = h.measure(function()
      jump.next()
    end, 100)

    table.insert(results, {
      name = string.format("jump.next  slots=%d", num_slots),
      stats = stats,
    })
  end

  h.teardown()
  return results
end

return M
