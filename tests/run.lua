local MiniTest = require("mini.test")

local M = {}

---@return string[]
local function collect_files()
  local files = vim.fn.globpath("tests", "test_*.lua", false, true)
  -- Exclude test_helpers.lua as it's not a test file
  local filtered = {}
  for _, file in ipairs(files) do
    if not file:match("test_helpers%.lua$") then
      table.insert(filtered, file)
    end
  end
  return filtered
end

---@return nil
function M.run()
  local cases = MiniTest.collect({
    find_files = collect_files,
  })

  MiniTest.execute(cases, {
    reporter = MiniTest.gen_reporter.stdout(),
  })
end

return M
