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

---@param stub table
---@param fn fun()
local function with_snacks_stub(stub, fn)
  with_loaded_module("snacks", stub, function()
    with_loaded_module("pinwords.snacks", nil, fn)
  end)
end

---@param items PinwordsSnacksItem[]
---@param opts? { current?: PinwordsSnacksItem|nil, selected?: PinwordsSnacksItem[] }
---@return PinwordsSnacksPicker & { closed: boolean }
local function fake_picker(items, opts)
  local picker = {
    closed = false,
    _current = opts and opts.current or items[1],
    _selected = opts and opts.selected or {},
  }

  function picker:current()
    return self._current
  end

  function picker:selected()
    return self._selected
  end

  function picker:close()
    self.closed = true
  end

  return picker
end

T["snacks picker builds sorted items"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_opts
  local snacks_stub = {
    picker = {
      pick = function(opts)
        captured_opts = opts
      end,
    },
  }

  local pinwords = require("pinwords")
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(1)

  with_snacks_stub(snacks_stub, function()
    local snacks_integration = require("pinwords.snacks")
    snacks_integration.picker()
  end)

  MiniTest.expect.equality(captured_opts.items[1].slot, 1)
  MiniTest.expect.equality(captured_opts.items[2].slot, 3)
  MiniTest.expect.equality(captured_opts.title, "Pinned Words")
end

T["snacks confirm unpins selected entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_opts
  local snacks_stub = {
    picker = {
      pick = function(opts)
        captured_opts = opts
      end,
    },
  }

  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)

  with_snacks_stub(snacks_stub, function()
    require("pinwords.snacks").picker()
  end)

  helpers.with_notify_override(function(notified)
    local picker = fake_picker(captured_opts.items, {
      selected = { captured_opts.items[1], captured_opts.items[2] },
    })

    captured_opts.confirm(picker, captured_opts.items[1])

    MiniTest.expect.equality(picker.closed, true)
    MiniTest.expect.equality(pinwords.list()[1], nil)
    MiniTest.expect.equality(pinwords.list()[2], nil)
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned 2 slot(s)")
  end)
end

T["snacks action unpins current entry"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_opts
  local snacks_stub = {
    picker = {
      pick = function(opts)
        captured_opts = opts
      end,
    },
  }

  local pinwords = require("pinwords")
  pinwords.set(1)

  with_snacks_stub(snacks_stub, function()
    require("pinwords.snacks").picker()
  end)

  helpers.with_notify_override(function(notified)
    local picker = fake_picker(captured_opts.items)
    captured_opts.actions.unpin_single(picker)

    MiniTest.expect.equality(picker.closed, true)
    MiniTest.expect.equality(pinwords.list()[1], nil)
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned slot 1")
  end)
end

T["snacks action clears all entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_opts
  local snacks_stub = {
    picker = {
      pick = function(opts)
        captured_opts = opts
      end,
    },
  }

  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)

  with_snacks_stub(snacks_stub, function()
    require("pinwords.snacks").picker()
  end)

  helpers.with_notify_override(function(notified)
    local picker = fake_picker(captured_opts.items)
    captured_opts.actions.clear_all(picker)

    MiniTest.expect.equality(picker.closed, true)
    MiniTest.expect.equality(next(pinwords.list()), nil)
    MiniTest.expect.equality(notified[1].msg, "pinwords: cleared all pins")
  end)
end

T["snacks picker handles empty state"] = function()
  helpers.setup_buffer({ "foo bar" })

  local called = false
  local snacks_stub = {
    picker = {
      pick = function()
        called = true
      end,
    },
  }

  with_snacks_stub(snacks_stub, function()
    helpers.with_notify_override(function(notified)
      require("pinwords.snacks").picker()

      MiniTest.expect.equality(called, false)
      MiniTest.expect.equality(notified[1].msg, "pinwords: no pinned words")
    end)
  end)
end

return T
