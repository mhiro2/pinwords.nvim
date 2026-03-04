local h = require("bench.bench_helpers")
local matcher = require("pinwords.matcher")

local M = {}

function M.run()
  local results = {}

  -- apply_slot_globally with varying window counts
  for _, num_wins in ipairs({ 1, 5, 10, 20 }) do
    h.teardown()
    require("pinwords").setup({})
    h.create_windows(num_wins)
    local entry = { raw = "test", pattern = "\\V\\c\\<test\\>", hl_group = "PinWord1" }

    local stats = h.measure(function()
      matcher.apply_slot_globally(1, entry)
    end, 100)

    table.insert(results, {
      name = string.format("apply_slot_globally  wins=%d", num_wins),
      stats = stats,
    })
  end

  -- apply_slot_for_window with varying existing match counts
  for _, num_existing in ipairs({ 0, 5, 9 }) do
    h.teardown()
    require("pinwords").setup({ slots = 9 })
    h.fill_slots(num_existing)
    local win = vim.api.nvim_get_current_win()
    matcher.reapply_all_for_window(win)

    local slot = num_existing + 1
    local entry = {
      raw = "extra",
      pattern = "\\V\\c\\<extra\\>",
      hl_group = "PinWord" .. slot,
    }

    local stats = h.measure(function()
      matcher.apply_slot_for_window(win, slot, entry)
    end, 200)

    table.insert(results, {
      name = string.format("apply_slot_for_window  existing=%d", num_existing),
      stats = stats,
    })
  end

  h.teardown()
  return results
end

return M
