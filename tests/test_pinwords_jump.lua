local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["jump_next moves to next occurrence"] = function()
  helpers.setup_buffer({ "foo bar foo baz foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  -- Cursor is on first "foo", should jump to second
  local success = pinwords.jump_next()
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 8) -- "foo bar [f]oo"
end

T["jump_prev moves to previous occurrence"] = function()
  helpers.setup_buffer({ "foo bar foo baz foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 16 }) -- Last "foo"

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  local success = pinwords.jump_prev()
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 8) -- "foo bar [f]oo"
end

T["jump_next with slot jumps only to that slot"] = function()
  helpers.setup_buffer({ "foo bar baz qux foo bar" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })
  pinwords.set(2, { raw = "bar" })

  -- Jump to next occurrence of slot 2 (bar)
  local success = pinwords.jump_next(2)
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 4) -- "foo [b]ar"
end

T["jump_prev with slot jumps only to that slot"] = function()
  helpers.setup_buffer({ "foo bar baz foo bar" })
  vim.api.nvim_win_set_cursor(0, { 1, 18 }) -- At end

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })
  pinwords.set(2, { raw = "bar" })

  -- Jump to previous occurrence of slot 1 (foo)
  local success = pinwords.jump_prev(1)
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 12) -- "foo bar baz [f]oo"
end

T["jump_next wraps to beginning at end of file"] = function()
  helpers.setup_buffer({ "foo", "bar", "foo" })
  vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- Last "foo"

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  local success = pinwords.jump_next()
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1) -- Wrapped to first line
  MiniTest.expect.equality(pos[2], 0)
end

T["jump_prev wraps to end at beginning of file"] = function()
  helpers.setup_buffer({ "foo", "bar", "foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- First "foo"

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  local success = pinwords.jump_prev()
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 3) -- Wrapped to last line
  MiniTest.expect.equality(pos[2], 0)
end

T["jump_next notifies when no pinned words"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.clear_all()

  local notified = false
  local orig_notify = vim.notify
  vim.notify = function(msg, _level)
    if msg:match("no pinned words") then
      notified = true
    end
  end

  local success = pinwords.jump_next()
  vim.notify = orig_notify

  MiniTest.expect.equality(success, false)
  MiniTest.expect.equality(notified, true)
end

T["jump_prev notifies when no pinned words"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.clear_all()

  local notified = false
  local orig_notify = vim.notify
  vim.notify = function(msg, _level)
    if msg:match("no pinned words") then
      notified = true
    end
  end

  local success = pinwords.jump_prev()
  vim.notify = orig_notify

  MiniTest.expect.equality(success, false)
  MiniTest.expect.equality(notified, true)
end

T["jump_next jumps to any pinned word when multiple pins"] = function()
  helpers.setup_buffer({ "apple banana cherry apple banana cherry" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "apple" })
  pinwords.set(2, { raw = "cherry" })

  -- First jump should find banana... no wait, banana is not pinned
  -- First jump from "apple" should find "cherry"
  local success = pinwords.jump_next()
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 13) -- "[c]herry"
end

T["jump_next respects count"] = function()
  helpers.setup_buffer({ "foo bar foo baz foo qux foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  -- Simulate count by setting vim.v.count1
  -- Note: We can't directly set vim.v.count1 in tests,
  -- but we can call jump multiple times
  local success = pinwords.jump_next()
  MiniTest.expect.equality(success, true)
  success = pinwords.jump_next()
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 16) -- Third "foo"
end

T["jump sets jumplist mark"] = function()
  helpers.setup_buffer({ "foo", "bar", "foo", "baz", "foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  -- Remember initial position
  local initial_pos = vim.api.nvim_win_get_cursor(0)

  -- Jump forward
  pinwords.jump_next()
  local after_jump = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(after_jump[1], 3)

  -- Jump back using Ctrl-O (jumplist)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-o>", true, false, true), "nx", false)
  local after_back = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(after_back[1], initial_pos[1])
end

T["jump_next with invalid slot returns false"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  -- Slot 99 is invalid (default max is 9)
  local notified = false
  local orig_notify = vim.notify
  vim.notify = function(msg, _level)
    if msg:match("must be between") then
      notified = true
    end
  end

  local success = pinwords.jump_next(99)
  vim.notify = orig_notify

  MiniTest.expect.equality(success, false)
  MiniTest.expect.equality(notified, true)
end

T["jump_next with empty slot returns false"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  -- Slot 2 is empty
  local notified = false
  local orig_notify = vim.notify
  vim.notify = function(msg, _level)
    if msg:match("no pinned words") then
      notified = true
    end
  end

  local success = pinwords.jump_next(2)
  vim.notify = orig_notify

  MiniTest.expect.equality(success, false)
  MiniTest.expect.equality(notified, true)
end

T["jump works across multiple lines"] = function()
  helpers.setup_buffer({
    "function foo()",
    "  local bar = 1",
    "  return foo + bar",
    "end",
  })
  vim.api.nvim_win_set_cursor(0, { 1, 9 }) -- On "foo" in first line

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })

  local success = pinwords.jump_next()
  MiniTest.expect.equality(success, true)

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 3) -- Line 3
  MiniTest.expect.equality(pos[2], 9) -- "  return [f]oo"
end

return T
