local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["set stores slot and match"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").set(1)

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<foo\\>")
end

T["clear removes slot and match"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").set(1)
  require("pinwords").clear(1)

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1], nil)

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match, nil)
end

T["unpin without slot clears word under cursor"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").set()
  MiniTest.expect.equality(helpers.match_count() > 0, true)

  vim.cmd("UnpinWord")
  MiniTest.expect.equality(helpers.match_count(), 0)
  MiniTest.expect.equality(next(require("pinwords").list()), nil)
end

T["clear_all removes all slots and matches"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  require("pinwords").set(1)
  require("pinwords").set(2)
  require("pinwords").set(3)

  MiniTest.expect.equality(helpers.match_count() > 0, true)

  require("pinwords").clear_all()
  MiniTest.expect.equality(helpers.match_count(), 0)
  MiniTest.expect.equality(next(require("pinwords").list()), nil)
end

T["list returns all active slots"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  require("pinwords").set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 8 }) -- Move to "baz"
  require("pinwords").set(3)

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[3].raw, "baz")
  MiniTest.expect.equality(slots[2], nil)
end

T["set with invalid slot does nothing"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  helpers.with_notify_override(function(notified)
    pinwords.set(0)
    pinwords.set(10)
    pinwords.set("invalid")

    MiniTest.expect.equality(#notified > 0, true)
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(next(slots), nil)
end

T["clear with invalid slot does nothing"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").set(1)

  local pinwords = require("pinwords")
  helpers.with_notify_override(function(notified)
    pinwords.clear(0)
    pinwords.clear(10)
    pinwords.clear("invalid")

    MiniTest.expect.equality(#notified > 0, true)
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "foo")
end

T["set with empty word does nothing"] = function()
  helpers.setup_buffer({ "   ", "  " })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  helpers.with_notify_override(function(notified)
    pinwords.set(1)

    MiniTest.expect.equality(#notified > 0, true)
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(next(slots), nil)
end

T["unpin function clears matching word"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  require("pinwords").unpin()

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1], nil)
end

T["toggle is alias for set without slot"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  require("pinwords").toggle()

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")
end

T["set never errors even if matchadd fails"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  local orig_matchadd = vim.fn.matchadd
  vim.fn.matchadd = function()
    error("matchadd failed")
  end

  local ok, err = pcall(function()
    helpers.with_notify_override(function(notified)
      local ok_set = pcall(pinwords.set, 1)
      MiniTest.expect.equality(ok_set, true)
      MiniTest.expect.equality(#notified > 0, true)
    end)
  end)

  vim.fn.matchadd = orig_matchadd

  if not ok then
    error(err)
  end
end

return T
