local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["setup validates options and never errors"] = function()
  local pinwords = require("pinwords")
  local orig_notify = vim.notify
  local notified = {}
  vim.notify = function(msg, level, opts)
    table.insert(notified, { msg = msg, level = level, opts = opts })
  end

  local ok = pcall(pinwords.setup, {
    slots = "9",
    whole_word = "yes",
    case_sensitive = 1,
    auto_allocation = {
      strategy = "unknown",
      on_full = "unknown",
      toggle_same = "yes",
    },
  })

  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(#notified > 0, true)

  -- It should still work after invalid setup.
  helpers.setup_buffer({ "foo bar", "baz" })
  ok = pcall(pinwords.set, 1)
  MiniTest.expect.equality(ok, true)
end

T["setup with fewer slots prunes existing slots and matches"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(3)

  MiniTest.expect.equality(helpers.find_match("PinWord3") ~= nil, true)

  pinwords.setup({ slots = 2 })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[3], nil)
  MiniTest.expect.equality(helpers.find_match("PinWord3"), nil)
end

return T
