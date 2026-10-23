local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["pick() notifies when no pinned words"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    require("pinwords").pick()

    MiniTest.expect.equality(#notified > 0, true)
    MiniTest.expect.equality(notified[1].msg:find("no pinned words") ~= nil, true)
  end)
end

T["pick() vim.ui.select unpins only the chosen entry"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)

  helpers.with_select_override(function(items, _opts, on_choice)
    on_choice(items[1])
  end, pinwords.pick)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1], nil)
  MiniTest.expect.equality(slots[2].raw, "bar")
  MiniTest.expect.equality(helpers.find_match("PinWord1"), nil)
  MiniTest.expect.equality(helpers.find_match("PinWord2").pattern, "\\V\\c\\<bar\\>")
end

T["pick() falls back to vim.ui.select with items sorted by slot"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(1)

  local select_items, select_opts
  helpers.with_select_override(function(items, opts)
    select_items = items
    select_opts = opts
  end, pinwords.pick)

  MiniTest.expect.equality(#select_items, 2)
  MiniTest.expect.equality(select_items[1].slot, 1)
  MiniTest.expect.equality(select_items[2].slot, 3)
  MiniTest.expect.equality(select_opts.format_item(select_items[2]), "3: baz")
end

T["pick() vim.ui.select no-op on cancel"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1)

  helpers.with_select_override(function(_items, _opts, on_choice)
    on_choice(nil)
  end, pinwords.pick)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "foo")
end

T["pick() falls back when snacks module is non-table"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.setup({ snacks = { enabled = true } })
  pinwords.set(1)

  local select_called = false
  helpers.with_select_override(function()
    select_called = true
  end, function()
    helpers.with_loaded_module("pinwords.snacks", true, function()
      local ok = pcall(pinwords.pick)
      MiniTest.expect.equality(ok, true)
    end)
  end)

  MiniTest.expect.equality(select_called, true)
end

T["pick() falls back when fzf_lua module is non-table"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.setup({ fzf_lua = { enabled = true } })
  pinwords.set(1)

  local select_called = false
  helpers.with_select_override(function()
    select_called = true
  end, function()
    helpers.with_loaded_module("pinwords.fzf_lua", true, function()
      local ok = pcall(pinwords.pick)
      MiniTest.expect.equality(ok, true)
    end)
  end)

  MiniTest.expect.equality(select_called, true)
end

T["pick() falls back when telescope extension is unavailable"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.setup({
    telescope = { enabled = true },
    snacks = { enabled = false },
    fzf_lua = { enabled = false },
  })
  pinwords.set(1)

  local select_called = false
  helpers.with_select_override(function()
    select_called = true
  end, function()
    helpers.with_loaded_module("telescope", {
      load_extension = function() end,
      extensions = {},
    }, function()
      local ok = pcall(pinwords.pick)
      MiniTest.expect.equality(ok, true)
    end)
  end)

  MiniTest.expect.equality(select_called, true)
end

return T
