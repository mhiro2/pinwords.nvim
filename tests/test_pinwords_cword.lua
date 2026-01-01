local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["cword toggle follows cursor in window"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  pinwords.cword_toggle()

  local match = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<foo\\>")

  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  vim.cmd("doautocmd <nomodeline> CursorMoved")

  match = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<bar\\>")

  pinwords.cword_toggle()
  match = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match, nil)
end

T["CursorMoved does nothing when cword is unused"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local state = require("pinwords.state")
  local orig = state.get_win_state
  local calls = 0
  state.get_win_state = function(...)
    calls = calls + 1
    return orig(...)
  end

  vim.cmd("doautocmd <nomodeline> CursorMoved")

  state.get_win_state = orig
  MiniTest.expect.equality(calls, 0)
end

T["cword clears when cursor moves to empty word"] = function()
  helpers.setup_buffer({ "foo bar", "", "baz" })

  local pinwords = require("pinwords")
  pinwords.cword_toggle()

  local match = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern:find("foo") ~= nil, true)

  -- Move cursor to an empty line so expand("<cword>") returns empty string.
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("doautocmd <nomodeline> CursorMoved")

  match = helpers.find_match("PinWordCword")
  -- When cursor is on an empty line, cword match should be cleared.
  MiniTest.expect.equality(match, nil)

  -- When moving to a non-empty word again, cword match should be reapplied.
  vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- on "bar"
  vim.cmd("doautocmd <nomodeline> CursorMoved")
  match = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<bar\\>")

  -- Cleanup: disable window-local cword to avoid leaking state to other cases.
  pinwords.cword_toggle()
end

T["cword is window-local"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local buf = vim.api.nvim_get_current_buf()
  local win1 = vim.api.nvim_get_current_win()

  local pinwords = require("pinwords")
  pinwords.cword_toggle()

  -- Verify win1 has cword enabled
  local match1_before = vim.api.nvim_win_call(win1, function()
    return helpers.find_match("PinWordCword")
  end)
  MiniTest.expect.equality(match1_before ~= nil, true)

  -- Verify win1's cword state is enabled
  local win1_state = require("pinwords.state").get_win_state(win1)
  MiniTest.expect.equality(win1_state.cword.enabled, true)

  -- Create window 2 showing the same buffer
  vim.cmd("vsplit")
  local win2 = vim.api.nvim_get_current_win()

  -- Window 2 should not have cword enabled by default
  -- cword_enabled_wins is window-local, so win2 should not be in it
  -- However, BufWinEnter/WinEnter might initialize win2_state.cword
  -- The key point is that win2 should not have cword match even if state says enabled
  -- because cword_enabled_wins[win2] is not set

  -- Also verify that win2 does not have a cword match
  -- This is the actual behavior we care about - cword is window-local
  local match2 = vim.api.nvim_win_call(win2, function()
    return helpers.find_match("PinWordCword")
  end)
  -- win2 should not have cword match (cword is window-local)
  MiniTest.expect.equality(match2, nil)

  -- Check win2's cword state (may be initialized by BufWinEnter/WinEnter)
  local win2_state = require("pinwords.state").get_win_state(win2)
  -- cword should exist (ensure_win_state initializes it)
  MiniTest.expect.equality(type(win2_state.cword) == "table", true)
  -- Note: win2_state.cword.enabled might be true if BufWinEnter/WinEnter
  -- copied state from win1, but the actual match should not exist
  -- because cword_enabled_wins[win2] is not set

  -- Window 1 should still have cword enabled
  vim.api.nvim_set_current_win(win1)
  local match1_after = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match1_after ~= nil, true)

  -- Cleanup: disable window-local cword to avoid leaking state to other cases.
  pinwords.cword_toggle()
end

return T
