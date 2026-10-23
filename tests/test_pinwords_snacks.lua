local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

---@param stub table
---@param fn fun()
local function with_snacks_stub(stub, fn)
  helpers.with_loaded_module("snacks", stub, function()
    helpers.with_loaded_module("pinwords.snacks", nil, fn)
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

---@return PinwordsSnacksPickerOpts
local function open_with_stub()
  local captured_opts
  with_snacks_stub({
    picker = {
      pick = function(opts)
        captured_opts = opts
      end,
    },
  }, function()
    require("pinwords.snacks").picker()
  end)
  return captured_opts
end

T["snacks picker builds sorted items"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(1)

  local captured_opts = open_with_stub()

  MiniTest.expect.equality(captured_opts.title, "Pinned Words")
  MiniTest.expect.equality(captured_opts.items[1].slot, 1)
  MiniTest.expect.equality(captured_opts.items[2].slot, 3)
  MiniTest.expect.equality(captured_opts.items[1].text, "1: foo")
  MiniTest.expect.equality(captured_opts.items[2].text, "3: baz")
end

T["snacks items are searchable with the real matcher"] = function()
  local snacks_path = vim.env.SNACKS_PATH or (vim.fn.getcwd() .. "/deps/snacks.nvim")
  if not vim.uv.fs_stat(snacks_path .. "/lua/snacks/picker/core/matcher.lua") then
    error("snacks.nvim is required at " .. snacks_path .. "; run `make deps`")
  end

  helpers.setup_buffer({ "foo bar baz" })
  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
  local items = open_with_stub().items

  local saved_runtimepath = vim.o.runtimepath
  local preloaded = {}
  for name in pairs(package.loaded) do
    preloaded[name] = true
  end

  vim.opt.runtimepath:append(snacks_path)
  local ok, err = pcall(function()
    local matcher = require("snacks.picker.core.matcher").new({})
    ---@param pattern string
    ---@return integer[]
    local function scores(pattern)
      matcher:init(pattern)
      return { matcher:match(items[1]), matcher:match(items[2]) }
    end

    -- Typing a word or a slot number narrows the list to that pin.
    local by_word = scores("foo")
    MiniTest.expect.equality({ by_word[1] > 0, by_word[2] }, { true, 0 })
    local by_slot = scores("3")
    MiniTest.expect.equality({ by_slot[1], by_slot[2] > 0 }, { 0, true })
  end)
  -- Undo only what this case loaded: Snacks' async module owns a libuv check
  -- handle that would otherwise outlive the unloaded module.
  local async = not preloaded["snacks.picker.util.async"] and package.loaded["snacks.picker.util.async"]
  if type(async) == "table" and async._executor and not async._executor:is_closing() then
    async._executor:close()
  end
  for name in pairs(package.loaded) do
    if not preloaded[name] and (name == "snacks" or vim.startswith(name, "snacks.")) then
      package.loaded[name] = nil
    end
  end
  vim.o.runtimepath = saved_runtimepath
  if not ok then
    error(err)
  end
end

T["snacks confirm unpins only the selected entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)

  local captured_opts = open_with_stub()

  helpers.with_notify_override(function(notified)
    local picker = fake_picker(captured_opts.items, {
      selected = { captured_opts.items[1], captured_opts.items[3] },
    })

    captured_opts.confirm(picker, captured_opts.items[1])

    MiniTest.expect.equality(picker.closed, true)
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned 2 slot(s)")
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1], nil)
  MiniTest.expect.equality(slots[3], nil)
  MiniTest.expect.equality(slots[2].raw, "bar")
  MiniTest.expect.equality(helpers.find_match("PinWord2").pattern, "\\V\\c\\<bar\\>")
end

T["snacks action unpins only the current entry"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  pinwords.set(2)

  local captured_opts = open_with_stub()

  helpers.with_notify_override(function(notified)
    local picker = fake_picker(captured_opts.items, { current = captured_opts.items[2] })
    captured_opts.actions.unpin_single(picker)

    MiniTest.expect.equality(picker.closed, true)
    MiniTest.expect.equality(notified[1].msg, "pinwords: unpinned slot 2")
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[2], nil)
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(helpers.find_match("PinWord1").pattern, "\\V\\c\\<foo\\>")
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
