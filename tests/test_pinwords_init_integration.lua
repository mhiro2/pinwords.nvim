local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["setup can be called multiple times"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")

  pinwords.setup({ slots = 3 })
  pinwords.set(1, { raw = "foo" })

  local slots1 = pinwords.list()
  MiniTest.expect.equality(slots1[1].raw, "foo")

  pinwords.setup({ slots = 5 })

  local slots2 = pinwords.list()
  MiniTest.expect.equality(slots2[1].raw, "foo")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
end

T["setup with reduced slots prunes existing pins"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.setup({ slots = 5 })

  pinwords.set(1, { raw = "foo" })
  pinwords.set(3, { raw = "bar" })
  pinwords.set(5, { raw = "baz" })

  local slots_before = pinwords.list()
  MiniTest.expect.equality(slots_before[1].raw, "foo")
  MiniTest.expect.equality(slots_before[3].raw, "bar")
  MiniTest.expect.equality(slots_before[5].raw, "baz")

  pinwords.setup({ slots = 3 })

  local slots_after = pinwords.list()
  MiniTest.expect.equality(slots_after[1].raw, "foo")
  MiniTest.expect.equality(slots_after[3].raw, "bar")
  MiniTest.expect.equality(slots_after[5], nil)

  local match5 = helpers.find_match("PinWord5")
  MiniTest.expect.equality(match5, nil)
end

T["setup reapplies matches to all windows"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")
  pinwords.setup({ slots = 3 })
  pinwords.set(1, { raw = "foo" })

  vim.cmd("vsplit")

  local match_before = vim.api.nvim_win_call(0, function()
    return helpers.find_match("PinWord1")
  end)
  MiniTest.expect.equality(match_before ~= nil, true)

  pinwords.setup({ slots = 3 })

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local match = vim.api.nvim_win_call(win, function()
      return helpers.find_match("PinWord1")
    end)
    MiniTest.expect.equality(match ~= nil, true)
  end
end

T["setup preserves existing global state"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")

  pinwords.setup({ slots = 3 })
  pinwords.set(1, { raw = "foo" })

  local global_before = vim.g.pinwords_global
  MiniTest.expect.equality(type(global_before), "table")
  MiniTest.expect.equality(global_before.slots[1].raw, "foo")

  pinwords.setup({ slots = 5, auto_allocation = { strategy = "cycle" } })

  local global_after = vim.g.pinwords_global
  MiniTest.expect.equality(global_after.slots[1].raw, "foo")
end

T["setup initializes from existing global state"] = function()
  helpers.setup_buffer({ "foo bar" })

  vim.g.pinwords_global = {
    slots = {
      [1] = { raw = "existing", pattern = "\\V\\c\\<existing\\>", hl_group = "PinWord1" },
    },
    order = { 1 },
    last_used = { [1] = 1 },
    tick = 1,
  }

  local pinwords = require("pinwords")
  pinwords.setup({ slots = 3 })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "existing")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
end

T["setup with invalid config falls back to defaults"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    pinwords.setup({
      slots = "invalid",
      whole_word = "yes",
      case_sensitive = 123,
      auto_allocation = "not a table",
    })

    MiniTest.expect.equality(#notified > 0, true)

    local slots = pinwords.list()
    MiniTest.expect.equality(next(slots), nil)

    pinwords.set(1)
    MiniTest.expect.equality(slots[1].raw, "foo")
  end)
end

T["setup with invalid auto_allocation falls back to defaults"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    pinwords.setup({
      auto_allocation = {
        strategy = "invalid_strategy",
        on_full = "invalid_on_full",
        toggle_same = "not a boolean",
      },
    })

    MiniTest.expect.equality(#notified > 0, true)

    local slots = pinwords.list()
    MiniTest.expect.equality(next(slots), nil)

    pinwords.set()
    MiniTest.expect.equality(slots[1].raw, "foo")
  end)
end

T["setup merges partial config with defaults"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")

  pinwords.setup({
    slots = 5,
    auto_allocation = {
      strategy = "cycle",
    },
  })

  pinwords.set(nil, { raw = "a" })
  pinwords.set(nil, { raw = "b" })
  pinwords.set(nil, { raw = "c" })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "a")
  MiniTest.expect.equality(slots[2].raw, "b")
  MiniTest.expect.equality(slots[3].raw, "c")

  pinwords.set(nil, { raw = "d" })

  local slots2 = pinwords.list()
  MiniTest.expect.equality(slots2[4].raw, "d")
end

T["setup creates autocmd group"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")
  pinwords.setup()

  local ok, groups = pcall(vim.api.nvim_get_autocmds, { group = "PinWords" })
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(#groups > 0, true)
end

T["setup registers commands"] = function()
  helpers.setup_buffer({ "foo bar" })

  local pinwords = require("pinwords")
  pinwords.setup()

  local ok, commands = pcall(vim.api.nvim_get_commands, { builtin = false })
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(commands["PinWord"] ~= nil, true)
  MiniTest.expect.equality(commands["UnpinWord"] ~= nil, true)
  MiniTest.expect.equality(commands["UnpinAllWords"] ~= nil, true)
  MiniTest.expect.equality(commands["PinWordList"] ~= nil, true)
  MiniTest.expect.equality(commands["PinWordCwordToggle"] ~= nil, true)
end

T["setup applies highlights for all slots"] = function()
  helpers.setup_buffer({ "test" })

  helpers.clear_hl("PinWord1")
  helpers.clear_hl("PinWord2")
  helpers.clear_hl("PinWord3")

  local pinwords = require("pinwords")
  pinwords.setup({ slots = 3 })

  local hl1 = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  local hl2 = vim.api.nvim_get_hl(0, { name = "PinWord2", link = false })
  local hl3 = vim.api.nvim_get_hl(0, { name = "PinWord3", link = false })

  MiniTest.expect.equality(type(hl1.bg), "number")
  MiniTest.expect.equality(type(hl2.bg), "number")
  MiniTest.expect.equality(type(hl3.bg), "number")

  MiniTest.expect.equality(hl1.bg ~= hl2.bg, true)
  MiniTest.expect.equality(hl2.bg ~= hl3.bg, true)
end

T["setup applies cword highlight"] = function()
  helpers.setup_buffer({ "test" })

  helpers.clear_hl("PinWordCword")

  local pinwords = require("pinwords")
  pinwords.setup({ slots = 1 })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWordCword", link = false })

  MiniTest.expect.equality(type(hl.bg), "number")
end

T["set with opts applies per-slot options"] = function()
  helpers.setup_buffer({ "Foo foo FOO", "bar" })

  local pinwords = require("pinwords")
  pinwords.setup({ slots = 2 })

  pinwords.set(1, { raw = "Foo", case_sensitive = true })
  pinwords.set(2, { raw = "Foo", case_sensitive = false })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].pattern:find("\\C"), 3)
  MiniTest.expect.equality(slots[2].pattern:find("\\c"), 3)

  local match1 = helpers.find_match("PinWord1")
  local match2 = helpers.find_match("PinWord2")
  MiniTest.expect.equality(match1.pattern:find("\\C"), 3)
  MiniTest.expect.equality(match2.pattern:find("\\c"), 3)
end

T["set with whole_word option"] = function()
  helpers.setup_buffer({ "foo foobar", "bar" })

  local pinwords = require("pinwords")
  pinwords.setup({ slots = 2 })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(1, { whole_word = true })

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(2, { whole_word = false })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].pattern:find("\\<"), 5)
  MiniTest.expect.equality(slots[2].pattern:find("\\<"), nil)

  local match1 = helpers.find_match("PinWord1")
  local match2 = helpers.find_match("PinWord2")
  MiniTest.expect.equality(match1.pattern:find("\\<"), 5)
  MiniTest.expect.equality(match2.pattern:find("\\<"), nil)
end

T["toggle_same toggles existing word"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  pinwords.setup({ auto_allocation = { toggle_same = true } })

  pinwords.set()
  MiniTest.expect.equality(helpers.match_count() > 0, true)

  pinwords.set()
  MiniTest.expect.equality(helpers.match_count(), 0)
  MiniTest.expect.equality(next(pinwords.list()), nil)
end

T["toggle_same=false adds duplicate to different slot"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")
  pinwords.setup({ auto_allocation = { toggle_same = false } })

  pinwords.set()
  local before = helpers.match_count()

  pinwords.set()
  local after = helpers.match_count()

  MiniTest.expect.equality(after >= before, true)
end

T["unpin finds word by pattern when direct match fails"] = function()
  helpers.setup_buffer({ "foo bar", "baz" })

  local pinwords = require("pinwords")

  pinwords.set(1, { raw = "foo", whole_word = false })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local slots_before = pinwords.list()
  MiniTest.expect.equality(slots_before[1] ~= nil, true)

  pinwords.unpin()

  local slots_after = pinwords.list()
  MiniTest.expect.equality(slots_after[1], nil)
end

T["clear_all with autocmd"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  vim.cmd("vsplit")

  local pinwords = require("pinwords")
  pinwords.setup()

  pinwords.set(1)
  pinwords.set(2)
  pinwords.set(3)

  MiniTest.expect.equality(helpers.match_count() > 0, true)

  vim.cmd("UnpinAllWords")

  MiniTest.expect.equality(helpers.match_count(), 0)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local count = vim.api.nvim_win_call(win, function()
      return helpers.match_count()
    end)
    MiniTest.expect.equality(count, 0)
  end
end

return T
