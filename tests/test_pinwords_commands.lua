local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["PinWord with slot argument pins word under cursor"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  vim.cmd("PinWord 1")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
end

T["PinWord without slot uses auto allocation"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  vim.cmd("PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")
end

T["PinWord with visual range pins selected text"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  -- Set visual marks
  helpers.set_visual_marks(1, 5, 1, 7)

  vim.cmd("'<,'>PinWord 1")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "bar")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
end

T["PinWord with line range does not use stale visual marks"] = function()
  helpers.setup_buffer({ "foo bar", "baz qux" })

  -- Set stale visual marks on line 2 ("baz")
  helpers.set_visual_marks(2, 1, 2, 3)

  -- Use a line-range call (not '<,'>); it should pin <cword>, not stale selection.
  vim.cmd("1,1PinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<foo\\>")
end

T["UnpinWord without slot clears word under cursor"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  require("pinwords").set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  vim.cmd("UnpinWord")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1], nil)
end

T["UnpinWord with slot clears specific slot"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  require("pinwords").set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- Move to "bar"
  require("pinwords").set(2)

  vim.cmd("UnpinWord 1")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1], nil)
  MiniTest.expect.equality(slots[2].raw, "bar")
end

T["UnpinAllWords clears all slots"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  require("pinwords").set(1)
  require("pinwords").set(2)
  require("pinwords").set(3)

  vim.cmd("UnpinAllWords")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(next(slots), nil)
  MiniTest.expect.equality(helpers.match_count(), 0)
end

T["PinWordList shows all pinned words"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  require("pinwords").set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  require("pinwords").set(2)

  helpers.with_notify_override(function(notified)
    vim.cmd("PinWordList")

    MiniTest.expect.equality(#notified > 0, true)
    -- Check that the notification contains slot information
    local msg = notified[1].msg
    MiniTest.expect.equality(type(msg), "string")
    MiniTest.expect.equality(msg:find("1:") ~= nil, true)
    MiniTest.expect.equality(msg:find("2:") ~= nil, true)
  end)
end

T["PinWordList shows message when no words pinned"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    vim.cmd("PinWordList")

    MiniTest.expect.equality(#notified > 0, true)
    local msg = notified[1].msg
    MiniTest.expect.equality(msg:find("no pinned words") ~= nil, true)
  end)
end

T["PinWordCwordToggle toggles cword feature"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local win = vim.api.nvim_get_current_win()
  local win_state = require("pinwords.state").get_win_state(win)

  -- Initially disabled
  MiniTest.expect.equality(win_state.cword.enabled, false)

  vim.cmd("PinWordCwordToggle")

  -- Should be enabled
  win_state = require("pinwords.state").get_win_state(win)
  MiniTest.expect.equality(win_state.cword.enabled, true)

  vim.cmd("PinWordCwordToggle")

  -- Should be disabled again
  win_state = require("pinwords.state").get_win_state(win)
  MiniTest.expect.equality(win_state.cword.enabled, false)
end

T["PinWord with invalid slot shows error"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    vim.cmd("PinWord 0")
    vim.cmd("PinWord 100")

    MiniTest.expect.equality(#notified > 0, true)
  end)

  local slots = require("pinwords").list()
  MiniTest.expect.equality(next(slots), nil)
end

T["UnpinWord with invalid slot shows error"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  require("pinwords").set(1)

  helpers.with_notify_override(function(notified)
    vim.cmd("UnpinWord 0")
    vim.cmd("UnpinWord 100")

    MiniTest.expect.equality(#notified > 0, true)
  end)

  -- Slot 1 should still exist
  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")
end

return T
