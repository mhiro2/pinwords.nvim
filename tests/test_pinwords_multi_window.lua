local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["set/clear affects all windows showing the buffer"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  vim.cmd("vsplit")

  require("pinwords").set(1)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local match = vim.api.nvim_win_call(win, function()
      return helpers.find_match("PinWord1")
    end)
    MiniTest.expect.equality(match ~= nil, true)
  end

  require("pinwords").clear(1)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local match = vim.api.nvim_win_call(win, function()
      return helpers.find_match("PinWord1")
    end)
    MiniTest.expect.equality(match, nil)
  end
end

T["pin word set in one window appears in other windows"] = function()
  helpers.setup_buffer({ "foo bar baz", "qux quux" })
  local buf = vim.api.nvim_get_current_buf()
  local win1 = vim.api.nvim_get_current_win()

  -- Set pin word in window 1
  require("pinwords").set(1)

  -- Create window 2 showing the same buffer
  vim.cmd("vsplit")
  local win2 = vim.api.nvim_get_current_win()

  -- Verify match exists in both windows
  local match1 = vim.api.nvim_win_call(win1, function()
    return helpers.find_match("PinWord1")
  end)
  local match2 = vim.api.nvim_win_call(win2, function()
    return helpers.find_match("PinWord1")
  end)

  MiniTest.expect.equality(match1 ~= nil, true)
  MiniTest.expect.equality(match2 ~= nil, true)
  MiniTest.expect.equality(match1.pattern, match2.pattern)

  -- Now test setting from the second window
  vim.api.nvim_set_current_win(win2)
  vim.api.nvim_win_set_cursor(win2, { 1, 4 }) -- on "bar"
  require("pinwords").set(2)

  -- Verify match exists in window 1 as well
  local match1_bar = vim.api.nvim_win_call(win1, function()
    return helpers.find_match("PinWord2")
  end)

  MiniTest.expect.equality(match1_bar ~= nil, true)
  MiniTest.expect.equality(match1_bar.pattern, "\\V\\c\\<bar\\>")
end

T["pin word shared across tabs when same buffer"] = function()
  helpers.setup_buffer({ "foo bar baz", "qux quux" })
  local buf = vim.api.nvim_get_current_buf()
  local win1 = vim.api.nvim_get_current_win()

  -- Set pin word in window 1
  require("pinwords").set(1)

  -- Create new tab and open the same buffer
  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, buf)
  local win2 = vim.api.nvim_get_current_win()

  -- Verify match exists in the new tab's window
  local match2 = vim.api.nvim_win_call(win2, function()
    return helpers.find_match("PinWord1")
  end)

  MiniTest.expect.equality(match2 ~= nil, true)

  -- Go back to original tab and verify
  vim.cmd("tabprevious")
  local match1 = vim.api.nvim_win_call(win1, function()
    return helpers.find_match("PinWord1")
  end)

  MiniTest.expect.equality(match1 ~= nil, true)
end

T["pin word reapplied when window reopened"] = function()
  helpers.setup_buffer({ "foo bar baz", "qux quux" })
  local buf = vim.api.nvim_get_current_buf()

  -- Set pin word
  require("pinwords").set(1)

  -- Split window
  vim.cmd("vsplit")
  local wins = vim.api.nvim_list_wins()
  local win2 = wins[2]

  -- Close window 2
  vim.api.nvim_win_close(win2, true)

  -- Reopen the same buffer in a window (triggers BufWinEnter)
  vim.cmd("vsplit")
  local new_wins = vim.api.nvim_list_wins()
  local new_win = new_wins[2]
  vim.api.nvim_win_set_buf(new_win, buf)

  -- Verify match exists in the new window
  local match = vim.api.nvim_win_call(new_win, function()
    return helpers.find_match("PinWord1")
  end)

  MiniTest.expect.equality(match ~= nil, true)
end

T["pin words shared globally across all buffers"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  local buf1 = vim.api.nvim_get_current_buf()

  -- Set pin word in buffer 1
  require("pinwords").set(1)

  -- Create new buffer
  vim.cmd("enew")
  helpers.setup_buffer({ "foo bar baz" })
  local buf2 = vim.api.nvim_get_current_buf()

  -- Verify buffer 2 automatically has the same pin word
  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)

  -- Verify global list shows the word
  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")

  -- Clear from buffer 2
  require("pinwords").clear(1)

  -- Switch to buffer 1 and verify it's also cleared
  vim.api.nvim_set_current_buf(buf1)
  local match1 = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match1, nil)

  local slots_after = require("pinwords").list()
  MiniTest.expect.equality(next(slots_after), nil)
end

T["pin word immediately appears in all open buffers"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  local buf1 = vim.api.nvim_get_current_buf()
  local win1 = vim.api.nvim_get_current_win()

  -- Create second buffer in a split
  vim.cmd("vsplit")
  vim.cmd("enew")
  helpers.setup_buffer({ "qux foo quux" })
  local buf2 = vim.api.nvim_get_current_buf()
  local win2 = vim.api.nvim_get_current_win()

  -- Set pin word from buffer 2
  vim.api.nvim_win_set_cursor(win2, { 1, 4 }) -- on "foo"
  require("pinwords").set(1)

  -- Immediately check buffer 1's window without switching
  local match1 = vim.api.nvim_win_call(win1, function()
    return helpers.find_match("PinWord1")
  end)

  MiniTest.expect.equality(match1 ~= nil, true)
end

T["new buffers automatically receive existing global highlights"] = function()
  helpers.setup_buffer({ "test word" })

  -- Pin a word
  require("pinwords").set(1)

  -- Create a new buffer with the same word
  vim.cmd("enew")
  helpers.setup_buffer({ "another test buffer" })

  -- The highlight should be automatically applied
  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
end

return T
