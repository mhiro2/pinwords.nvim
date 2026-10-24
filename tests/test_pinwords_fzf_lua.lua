local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

---@param stub table
---@param fn fun()
local function with_fzf_stub(stub, fn)
  helpers.with_loaded_module("fzf-lua", stub, function()
    helpers.with_loaded_module("pinwords.fzf_lua", nil, fn)
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

---@return table
local function open_with_stub()
  local captured_opts
  with_fzf_stub({
    fzf_exec = function(_items, opts)
      captured_opts = opts
    end,
  }, function()
    require("pinwords.fzf_lua").picker()
  end)
  return captured_opts
end

---@param pinwords table
local function pin_three(pinwords)
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
end

T["fzf-lua default action unpins only the selected entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pin_three(pinwords)
  local captured_opts = open_with_stub()

  helpers.with_notify_override(function(notified)
    captured_opts.actions["default"]({ "1: foo", "3: baz" })
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned 2 slot(s)")
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1], nil)
  MiniTest.expect.equality(slots[3], nil)
  MiniTest.expect.equality(slots[2].raw, "bar")
  MiniTest.expect.equality(helpers.find_match("PinWord2").pattern, "\\V\\c\\<bar\\>")
end

T["fzf-lua ctrl-d unpins only the first selected entry"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pin_three(pinwords)
  local captured_opts = open_with_stub()

  helpers.with_notify_override(function(notified)
    captured_opts.actions["ctrl-d"]({ "2: bar", "3: baz" })
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned slot 2")
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[2], nil)
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[3].raw, "baz")
  MiniTest.expect.equality(helpers.match_count(), 2)
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
      MiniTest.expect.equality(notified[1].level, vim.log.levels.INFO)
    end)
  end)
end

return T
