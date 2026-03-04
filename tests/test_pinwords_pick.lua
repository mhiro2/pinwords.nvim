local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

---@param module_name string
---@param value any
---@param fn fun()
local function with_loaded_module(module_name, value, fn)
  local previous = package.loaded[module_name]
  package.loaded[module_name] = value

  local ok, err = pcall(fn)
  package.loaded[module_name] = previous

  if not ok then
    error(err)
  end
end

T["pick() falls back to vim.ui.select when no picker enabled"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  require("pinwords").set(1)

  local select_called = false
  local orig_select = vim.ui.select
  vim.ui.select = function(_items, _opts, _on_choice)
    select_called = true
  end

  require("pinwords").pick()

  vim.ui.select = orig_select
  MiniTest.expect.equality(select_called, true)
end

T["pick() notifies when no pinned words"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  helpers.with_notify_override(function(notified)
    require("pinwords").pick()

    MiniTest.expect.equality(#notified > 0, true)
    MiniTest.expect.equality(notified[1].msg:find("no pinned words") ~= nil, true)
  end)
end

T["pick() vim.ui.select unpins on selection"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1)

  local orig_select = vim.ui.select
  vim.ui.select = function(items, _opts, on_choice)
    on_choice(items[1])
  end

  pinwords.pick()

  vim.ui.select = orig_select

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1], nil)
end

T["pick() vim.ui.select items are sorted by slot"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(1)

  local select_items = nil
  local orig_select = vim.ui.select
  vim.ui.select = function(items, _opts, _on_choice)
    select_items = items
  end

  pinwords.pick()

  vim.ui.select = orig_select

  MiniTest.expect.equality(#select_items, 2)
  MiniTest.expect.equality(select_items[1].slot, 1)
  MiniTest.expect.equality(select_items[2].slot, 3)
end

T["pick() vim.ui.select no-op on cancel"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1)

  local orig_select = vim.ui.select
  vim.ui.select = function(_items, _opts, on_choice)
    on_choice(nil)
  end

  pinwords.pick()

  vim.ui.select = orig_select

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "foo")
end

T["pick() falls back when snacks module is non-table"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.setup({ snacks = { enabled = true } })
  pinwords.set(1)

  local select_called = false
  local orig_select = vim.ui.select
  vim.ui.select = function(_items, _opts, _on_choice)
    select_called = true
  end

  with_loaded_module("pinwords.snacks", true, function()
    local ok = pcall(pinwords.pick)
    MiniTest.expect.equality(ok, true)
  end)

  vim.ui.select = orig_select

  MiniTest.expect.equality(select_called, true)
end

return T
