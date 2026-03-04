local h = require("bench.bench_helpers")
local matcher = require("pinwords.matcher")

local M = {}

function M.run()
  local results = {}
  local slot_counts = { 1, 5, 9 }
  local win_counts = { 1, 5, 10, 20 }

  for _, num_slots in ipairs(slot_counts) do
    for _, num_wins in ipairs(win_counts) do
      h.teardown()
      require("pinwords").setup({ slots = num_slots })
      h.fill_slots(num_slots)
      local wins = h.create_windows(num_wins)

      local stats = h.measure(function()
        for _, win in ipairs(wins) do
          matcher.reapply_all_for_window(win)
        end
      end, 50)

      table.insert(results, {
        name = string.format("reapply_all  slots=%d wins=%d", num_slots, num_wins),
        stats = stats,
      })
    end
  end

  h.teardown()
  return results
end

return M
