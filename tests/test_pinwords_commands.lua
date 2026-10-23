local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["all user commands are registered"] = function()
  local commands = vim.api.nvim_get_commands({ builtin = false })
  local expected = {
    "PinWord",
    "PinWordSymbol",
    "UnpinWord",
    "UnpinAllWords",
    "PinWordList",
    "PinWordCwordToggle",
    "PinWordNext",
    "PinWordPrev",
    "PinWordGrep",
    "PinWordLiveGrep",
  }

  for _, name in ipairs(expected) do
    MiniTest.expect.equality(commands[name] ~= nil, true)
  end
end

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

  -- Leave a selection of "foo" on line 1, then move to "bar" on the same line.
  helpers.feed_keys("vll<Esc>")
  vim.api.nvim_win_set_cursor(0, { 1, 4 })

  helpers.feed_keys(":1,1PinWord<CR>")

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "bar")
  MiniTest.expect.equality(helpers.find_match("PinWord1").pattern, "\\V\\c\\<bar\\>")
end

T["UnpinWord without slot clears word under cursor"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set()
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  MiniTest.expect.equality(helpers.match_count(), 2)

  vim.cmd("UnpinWord")

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1], nil)
  MiniTest.expect.equality(slots[2].raw, "bar")
  MiniTest.expect.equality(helpers.find_match("PinWord1"), nil)
  MiniTest.expect.equality(helpers.match_count(), 1)
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

T["UnpinWord warns when current word matches multiple slots"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1, { raw = "foo", whole_word = false })
  pinwords.set(2, { raw = "foo", case_sensitive = true })

  helpers.with_notify_override(function(notified)
    vim.cmd("UnpinWord")

    MiniTest.expect.equality(#notified > 0, true)
    MiniTest.expect.equality(notified[1].msg:find("multiple pinned slots match current word", 1, true) ~= nil, true)
    MiniTest.expect.equality(notified[1].level, vim.log.levels.WARN)
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1] ~= nil, true)
  MiniTest.expect.equality(slots[2] ~= nil, true)
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

T["PinWordList opens interactive picker"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  require("pinwords").set(1)

  -- Pins are global, so a pin made in another buffer is listed as well.
  vim.cmd("enew")
  helpers.setup_buffer({ "qux" })
  require("pinwords").set(2)

  local select_items = nil
  local orig_select = vim.ui.select
  vim.ui.select = function(items, _opts, _on_choice)
    select_items = items
  end

  local ok, err = pcall(vim.cmd, "PinWordList")
  vim.ui.select = orig_select
  if not ok then
    error(err)
  end

  MiniTest.expect.equality(#select_items, 2)
  MiniTest.expect.equality({ select_items[1].slot, select_items[1].raw }, { 1, "foo" })
  MiniTest.expect.equality({ select_items[2].slot, select_items[2].raw }, { 2, "qux" })
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

T["PinWord with float slot shows error"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    vim.cmd("PinWord 1.5")
    vim.cmd("PinWord 2.7")

    MiniTest.expect.equality(#notified >= 2, true)
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

T["PinWordNext jumps to next occurrence"] = function()
  helpers.setup_buffer({ "foo bar foo baz foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  require("pinwords").set(1, { raw = "foo" })

  vim.cmd("PinWordNext")

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 8)
end

T["PinWordPrev jumps to previous occurrence"] = function()
  helpers.setup_buffer({ "foo bar foo baz foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 16 })

  require("pinwords").set(1, { raw = "foo" })

  vim.cmd("PinWordPrev")

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 8)
end

T["PinWordNext with slot jumps to specific slot"] = function()
  helpers.setup_buffer({ "foo bar baz foo bar" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  require("pinwords").set(1, { raw = "foo" })
  require("pinwords").set(2, { raw = "bar" })

  vim.cmd("PinWordNext 2")

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 4) -- "foo [b]ar"
end

T["PinWordPrev with slot jumps to specific slot"] = function()
  helpers.setup_buffer({ "foo bar baz foo bar" })
  vim.api.nvim_win_set_cursor(0, { 1, 18 })

  require("pinwords").set(1, { raw = "foo" })
  require("pinwords").set(2, { raw = "bar" })

  vim.cmd("PinWordPrev 1")

  local pos = vim.api.nvim_win_get_cursor(0)
  MiniTest.expect.equality(pos[1], 1)
  MiniTest.expect.equality(pos[2], 12) -- "foo bar baz [f]oo"
end

T["PinWordNext and PinWordPrev with invalid slot warn without moving"] = function()
  helpers.setup_buffer({ "foo bar foo baz" })
  require("pinwords").set(1, { raw = "foo" })
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  local jumps_before = #vim.fn.getjumplist()[1]

  for _, command in ipairs({ "PinWordNext", "PinWordPrev" }) do
    helpers.with_notify_override(function(notified)
      vim.cmd(command .. " 0")
      vim.cmd(command .. " 100")
      vim.cmd(command .. " x")

      MiniTest.expect.equality(notified, {
        { msg = "pinwords: slot must be an integer between 1 and 9", level = vim.log.levels.WARN },
        { msg = "pinwords: slot must be an integer between 1 and 9", level = vim.log.levels.WARN },
        { msg = "pinwords: slot must be a number", level = vim.log.levels.WARN },
      })
    end)

    MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0), { 1, 4 })
    MiniTest.expect.equality(#vim.fn.getjumplist()[1], jumps_before)
  end
end

T["PinWordGrep and PinWordLiveGrep pass the slot argument through"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  local orig = { grep = pinwords.grep, live_grep = pinwords.live_grep }
  local calls = {}
  for method in pairs(orig) do
    pinwords[method] = function(opts)
      calls[#calls + 1] = { method, opts }
    end
  end

  local ok, err = pcall(function()
    vim.cmd("PinWordGrep 2")
    vim.cmd("PinWordGrep")
    vim.cmd("PinWordLiveGrep 3")
    vim.cmd("PinWordLiveGrep")
  end)
  for method, fn in pairs(orig) do
    pinwords[method] = fn
  end
  if not ok then
    error(err)
  end

  MiniTest.expect.equality(calls, {
    { "grep", { slot = 2 } },
    { "grep", {} },
    { "live_grep", { slot = 3 } },
    { "live_grep", {} },
  })
end

T["PinWordGrep and PinWordLiveGrep with invalid slot warn without searching"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  require("pinwords").set(1, { raw = "foo" })

  local grep = require("pinwords.grep")
  local orig = { grep = grep.grep, live_grep = grep.live_grep }
  local searched = 0
  for method in pairs(orig) do
    grep[method] = function()
      searched = searched + 1
    end
  end

  local ok, err = pcall(function()
    for _, command in ipairs({ "PinWordGrep", "PinWordLiveGrep" }) do
      helpers.with_notify_override(function(notified)
        vim.cmd(command .. " 0")
        vim.cmd(command .. " 1.5")

        MiniTest.expect.equality(notified, {
          { msg = "pinwords: slot must be an integer between 1 and 9", level = vim.log.levels.WARN },
          { msg = "pinwords: slot must be an integer between 1 and 9", level = vim.log.levels.WARN },
        })
      end)
    end
  end)
  for method, fn in pairs(orig) do
    grep[method] = fn
  end
  if not ok then
    error(err)
  end

  MiniTest.expect.equality(searched, 0)
  MiniTest.expect.equality(require("pinwords").list()[1].raw, "foo")
end

return T
