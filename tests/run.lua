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

---Print the revision of each test dependency so a run can be reproduced.
---@return nil
local function report_dependencies()
  local cwd = vim.fn.getcwd()
  local deps = {
    { "mini.nvim", vim.env.MINI_PATH or (cwd .. "/deps/mini.nvim") },
    { "plenary.nvim", vim.env.PLUG_PATH or (cwd .. "/deps/plenary.nvim") },
    { "telescope.nvim", vim.env.TELESCOPE_PATH or (cwd .. "/deps/telescope.nvim") },
    { "snacks.nvim", vim.env.SNACKS_PATH or (cwd .. "/deps/snacks.nvim") },
  }

  local lines = { "nvim " .. tostring(vim.version()) }
  for _, dep in ipairs(deps) do
    local result = vim.system({ "git", "-C", dep[2], "rev-parse", "--short", "HEAD" }, { text = true }):wait()
    local revision = result.code == 0 and vim.trim(result.stdout) or "missing"
    lines[#lines + 1] = dep[1] .. " " .. revision
  end
  print("Dependencies: " .. table.concat(lines, ", ") .. "\n")
end

---@return nil
function M.run()
  report_dependencies()

  local cases = MiniTest.collect({
    find_files = collect_files,
  })

  MiniTest.execute(cases, {
    reporter = MiniTest.gen_reporter.stdout(),
  })
end

return M
