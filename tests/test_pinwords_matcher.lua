local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["apply_slot_for_window adds match to window"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")
  local state = require("pinwords.state")

  local entry = {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  }

  matcher.apply_slot_for_window(win, 1, entry)

  local win_state = state.get_win_state(win)
  MiniTest.expect.equality(type(win_state.match_ids[1]), "number")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<foo\\>")
end

T["apply_slot_for_window replaces existing match"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")
  local state = require("pinwords.state")

  local entry1 = {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  }
  local entry2 = {
    raw = "bar",
    pattern = "\\V\\c\\<bar\\>",
    hl_group = "PinWord1",
  }

  matcher.apply_slot_for_window(win, 1, entry1)
  local win_state1 = state.get_win_state(win)
  local first_id = win_state1.match_ids[1]
  MiniTest.expect.equality(type(first_id), "number")

  matcher.apply_slot_for_window(win, 1, entry2)
  local win_state2 = state.get_win_state(win)
  local second_id = win_state2.match_ids[1]
  MiniTest.expect.equality(type(second_id), "number")
  MiniTest.expect.equality(first_id ~= second_id, true)

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<bar\\>")
end

T["apply_slot_for_buffer adds match to all windows showing buffer"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("vsplit")

  local matcher = require("pinwords.matcher")
  local entry = {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  }

  matcher.apply_slot_for_buffer(buf, 1, entry)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local match = vim.api.nvim_win_call(win, function()
      return helpers.find_match("PinWord1")
    end)
    MiniTest.expect.equality(match ~= nil, true)
  end
end

T["clear_slot_for_buffer removes match from all windows showing buffer"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("vsplit")

  local pinwords = require("pinwords")
  pinwords.set(1)

  local matcher = require("pinwords.matcher")
  matcher.clear_slot_for_buffer(buf, 1)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local match = vim.api.nvim_win_call(win, function()
      return helpers.find_match("PinWord1")
    end)
    MiniTest.expect.equality(match, nil)
  end

  local state = require("pinwords.state")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_state = state.get_win_state(win)
    MiniTest.expect.equality(win_state.match_ids[1], nil)
  end
end

T["clear_all_for_buffer removes all matches from buffer"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  local buf = vim.api.nvim_get_current_buf()
  vim.cmd("vsplit")

  local pinwords = require("pinwords")
  pinwords.set(1)
  pinwords.set(2)
  pinwords.set(3)

  MiniTest.expect.equality(helpers.match_count() > 0, true)

  local matcher = require("pinwords.matcher")
  matcher.clear_all_for_buffer(buf)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local count = vim.api.nvim_win_call(win, function()
      return helpers.match_count()
    end)
    MiniTest.expect.equality(count, 0)
  end

  local state = require("pinwords.state")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_state = state.get_win_state(win)
    MiniTest.expect.equality(next(win_state.match_ids), nil)
  end
end

T["reapply_all_for_window clears and reapplies all slots"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo" })
  pinwords.set(2, { raw = "bar" })
  pinwords.set(3, { raw = "baz" })

  local win = vim.api.nvim_get_current_win()
  local state = require("pinwords.state")
  local win_state_before = state.get_win_state(win)
  MiniTest.expect.equality(type(win_state_before.match_ids[1]), "number")
  MiniTest.expect.equality(type(win_state_before.match_ids[2]), "number")
  MiniTest.expect.equality(type(win_state_before.match_ids[3]), "number")

  local matcher = require("pinwords.matcher")
  matcher.reapply_all_for_window(win)

  local win_state_after = state.get_win_state(win)
  MiniTest.expect.equality(type(win_state_after.match_ids[1]), "number")
  MiniTest.expect.equality(type(win_state_after.match_ids[2]), "number")
  MiniTest.expect.equality(type(win_state_after.match_ids[3]), "number")

  local match1 = helpers.find_match("PinWord1")
  local match2 = helpers.find_match("PinWord2")
  local match3 = helpers.find_match("PinWord3")
  MiniTest.expect.equality(match1 ~= nil, true)
  MiniTest.expect.equality(match2 ~= nil, true)
  MiniTest.expect.equality(match3 ~= nil, true)
end

T["reapply_all_for_window with invalid window does nothing"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")
  pinwords.set(1)

  local matcher = require("pinwords.matcher")
  local ok = pcall(matcher.reapply_all_for_window, 99999)
  MiniTest.expect.equality(ok, true)

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
end

T["apply_slot_globally applies to all valid buffers"] = function()
  helpers.setup_buffer({ "foo bar" })
  vim.cmd("vsplit")

  local matcher = require("pinwords.matcher")
  local entry = {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  }

  matcher.apply_slot_globally(1, entry)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local match = vim.api.nvim_win_call(win, function()
      return helpers.find_match("PinWord1")
    end)
    MiniTest.expect.equality(match ~= nil, true)
  end
end

T["clear_slot_globally removes slot from all windows"] = function()
  helpers.setup_buffer({ "foo bar" })
  vim.cmd("vsplit")

  local pinwords = require("pinwords")
  pinwords.set(1)

  local matcher = require("pinwords.matcher")
  matcher.clear_slot_globally(1)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local match = vim.api.nvim_win_call(win, function()
      return helpers.find_match("PinWord1")
    end)
    MiniTest.expect.equality(match, nil)
  end

  local state = require("pinwords.state")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_state = state.get_win_state(win)
    MiniTest.expect.equality(win_state.match_ids[1], nil)
  end
end

T["clear_all_globally removes all matches from all windows"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  vim.cmd("vsplit")

  local pinwords = require("pinwords")
  pinwords.set(1)
  pinwords.set(2)
  pinwords.set(3)

  MiniTest.expect.equality(helpers.match_count() > 0, true)

  local matcher = require("pinwords.matcher")
  matcher.clear_all_globally()

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local count = vim.api.nvim_win_call(win, function()
      return helpers.match_count()
    end)
    MiniTest.expect.equality(count, 0)
  end

  local state = require("pinwords.state")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local win_state = state.get_win_state(win)
    MiniTest.expect.equality(next(win_state.match_ids), nil)
  end
end

T["apply_cword_for_window adds cword match"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")

  local id = matcher.apply_cword_for_window(win, nil, "\\V\\c\\<foo\\>")

  MiniTest.expect.equality(type(id), "number")

  local match = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match ~= nil, true)
  MiniTest.expect.equality(match.pattern, "\\V\\c\\<foo\\>")
end

T["apply_cword_for_window creates new match with different id"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")

  local id1 = matcher.apply_cword_for_window(win, nil, "\\V\\c\\<foo\\>")
  MiniTest.expect.equality(type(id1), "number")

  -- Calling again with existing_id should create a new match with different id
  local id2 = matcher.apply_cword_for_window(win, id1, "\\V\\c\\<bar\\>")
  MiniTest.expect.equality(type(id2), "number")
  MiniTest.expect.equality(id1 ~= id2, true)

  local match = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match ~= nil, true)
end

T["delete_match_id_for_window calls matchdelete with correct id"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")

  local id = matcher.apply_cword_for_window(win, nil, "\\V\\c\\<foo\\>")
  MiniTest.expect.equality(type(id), "number")

  local match_before = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match_before ~= nil, true)

  -- Verify delete_match_id_for_window can be called without error
  local ok = pcall(matcher.delete_match_id_for_window, win, id)
  MiniTest.expect.equality(ok, true)
end

T["clear_cword_for_window removes cword state and match"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")
  local state = require("pinwords.state")

  local id = matcher.apply_cword_for_window(win, nil, "\\V\\c\\<foo\\>")
  local win_state = state.get_win_state(win)
  win_state.cword = {
    enabled = true,
    match_id = id,
    pattern = "\\V\\c\\<foo\\>",
  }
  state.set_win_state(win, win_state)

  local match_before = helpers.find_match("PinWordCword")
  MiniTest.expect.equality(match_before ~= nil, true)

  matcher.clear_cword_for_window(win)

  local final_state = state.get_win_state(win)
  MiniTest.expect.equality(final_state.cword.match_id, nil)
  MiniTest.expect.equality(final_state.cword.pattern, nil)
end

T["clear_cword_for_window with no cword state does nothing"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")

  local ok = pcall(matcher.clear_cword_for_window, win)
  MiniTest.expect.equality(ok, true)
end

T["apply_slot_for_window handles matchadd failure gracefully"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")
  local state = require("pinwords.state")

  local orig_matchadd = vim.fn.matchadd
  vim.fn.matchadd = function()
    error("matchadd failed")
  end

  helpers.with_notify_override(function(notified)
    local entry = {
      raw = "foo",
      pattern = "\\V\\c\\<foo\\>",
      hl_group = "PinWord1",
    }

    local ok = pcall(matcher.apply_slot_for_window, win, 1, entry)
    MiniTest.expect.equality(ok, true)
    MiniTest.expect.equality(#notified > 0, true)

    local win_state = state.get_win_state(win)
    MiniTest.expect.equality(win_state.match_ids[1], nil)
  end)

  vim.fn.matchadd = orig_matchadd
end

T["apply_slot_for_window handles non-numeric matchadd return"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })
  local win = vim.api.nvim_get_current_win()
  local matcher = require("pinwords.matcher")
  local state = require("pinwords.state")

  local orig_matchadd = vim.fn.matchadd
  vim.fn.matchadd = function()
    return "invalid"
  end

  local entry = {
    raw = "foo",
    pattern = "\\V\\c\\<foo\\>",
    hl_group = "PinWord1",
  }

  local ok = pcall(matcher.apply_slot_for_window, win, 1, entry)
  MiniTest.expect.equality(ok, true)

  local win_state = state.get_win_state(win)
  MiniTest.expect.equality(win_state.match_ids[1], nil)

  vim.fn.matchadd = orig_matchadd
end

return T
