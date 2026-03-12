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
local function with_fzf_stub(stub, fn)
  with_loaded_module("fzf-lua", stub, function()
    with_loaded_module("pinwords.fzf_lua", nil, fn)
  end)
end

T["fzf-lua picker builds sorted items"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_items
  local captured_opts
  local fzf_stub = {
    fzf_exec = function(items, opts)
      captured_items = items
      captured_opts = opts
    end,
  }

  local pinwords = require("pinwords")
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(1)

  with_fzf_stub(fzf_stub, function()
    require("pinwords.fzf_lua").picker()
  end)

  MiniTest.expect.equality(captured_items[1], "1: foo")
  MiniTest.expect.equality(captured_items[2], "3: baz")
  MiniTest.expect.equality(captured_opts.prompt, "Pinned Words> ")
end

T["fzf-lua default action unpins selected entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_opts
  local fzf_stub = {
    fzf_exec = function(_items, opts)
      captured_opts = opts
    end,
  }

  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)

  with_fzf_stub(fzf_stub, function()
    require("pinwords.fzf_lua").picker()
  end)

  helpers.with_notify_override(function(notified)
    captured_opts.actions["default"]({ "1: foo", "2: bar" })

    local slots = pinwords.list()
    MiniTest.expect.equality(slots[1], nil)
    MiniTest.expect.equality(slots[2], nil)
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned 2 slot(s)")
  end)
end

T["fzf-lua ctrl-d unpins one entry"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_opts
  local fzf_stub = {
    fzf_exec = function(_items, opts)
      captured_opts = opts
    end,
  }

  local pinwords = require("pinwords")
  pinwords.set(1)

  with_fzf_stub(fzf_stub, function()
    require("pinwords.fzf_lua").picker()
  end)

  helpers.with_notify_override(function(notified)
    captured_opts.actions["ctrl-d"]({ "1: foo" })

    MiniTest.expect.equality(pinwords.list()[1], nil)
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned slot 1")
  end)
end

T["fzf-lua ctrl-x clears all entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local captured_opts
  local fzf_stub = {
    fzf_exec = function(_items, opts)
      captured_opts = opts
    end,
  }

  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)

  with_fzf_stub(fzf_stub, function()
    require("pinwords.fzf_lua").picker()
  end)

  helpers.with_notify_override(function(notified)
    captured_opts.actions["ctrl-x"]()

    MiniTest.expect.equality(next(pinwords.list()), nil)
    MiniTest.expect.equality(notified[1].msg, "pinwords: cleared all pins")
  end)
end

T["fzf-lua picker handles empty state"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local called = false
  local fzf_stub = {
    fzf_exec = function()
      called = true
    end,
  }

  with_fzf_stub(fzf_stub, function()
    helpers.with_notify_override(function(notified)
      require("pinwords.fzf_lua").picker()

      MiniTest.expect.equality(called, false)
      MiniTest.expect.equality(notified[1].msg, "pinwords: no pinned words")
    end)
  end)
end

return T
