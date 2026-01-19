local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

local has_snacks = pcall(require, "snacks")

if not has_snacks then
  -- Skip tests if snacks is not installed
  return T
end

T["snacks integration loads successfully"] = function()
  local ok, snacks_integration = pcall(require, "pinwords.snacks")

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(type(snacks_integration.picker), "function")
end

T["pinwords list works correctly"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")

  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  pinwords.set(2)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[2].raw, "bar")
end

T["pinwords entries have required fields"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")

  pinwords.set(1)

  local slots = pinwords.list()

  MiniTest.expect.equality(type(slots[1]), "table")
  MiniTest.expect.equality(type(slots[1].raw), "string")
  MiniTest.expect.equality(type(slots[1].pattern), "string")
  MiniTest.expect.equality(type(slots[1].hl_group), "string")
  MiniTest.expect.equality(slots[1].hl_group, "PinWord1")
end

T["picker handles empty state"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")

  -- Ensure no pins
  pinwords.clear_all()

  -- Should notify and return without opening picker
  local notifications = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level)
    table.insert(notifications, { msg = msg, level = level })
  end

  require("pinwords.snacks").picker()

  vim.notify = orig_notify

  MiniTest.expect.equality(#notifications, 1)
  MiniTest.expect.equality(notifications[1].msg:find("no pinned words") ~= nil, true)
end

return T
