local h = require("bench.bench_helpers")
local matcher = require("pinwords.matcher")

local M = {}

function M.run()
  local results = {}

  for _, num_slots in ipairs({ 1, 5, 9 }) do
    for _, num_wins in ipairs({ 1, 5, 10 }) do
      local stats = h.measure(function()
        h.teardown()
        require("pinwords").setup({ slots = num_slots })
        h.fill_slots(num_slots)
        local wins = h.create_windows(num_wins)
        for _, win in ipairs(wins) do
          matcher.reapply_all_for_window(win)
        end
        matcher.clear_all_globally()
      end, 30)

      table.insert(results, {
        name = string.format("clear_all_globally  slots=%d wins=%d", num_slots, num_wins),
        stats = stats,
      })
    end
  end

  h.teardown()
  return results
end

return M
