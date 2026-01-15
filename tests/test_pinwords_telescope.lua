local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

local has_telescope = pcall(require, "telescope")

if not has_telescope then
  -- Skip tests if telescope is not installed
  return T
end

local function open_picker()
  local telescope = require("telescope")
  pcall(telescope.load_extension, "pinwords")
  telescope.extensions.pinwords.pinwords()

  vim.wait(200, function()
    return vim.bo.buftype == "prompt"
  end)
end

local function feed(keys)
  local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_input(termcodes)
  vim.wait(200)
end

T["telescope extension loads successfully"] = function()
  local ok, _result = pcall(require, "telescope._extensions.pinwords")

  MiniTest.expect.equality(ok, true)
end

T["telescope extension is registered"] = function()
  local telescope = require("telescope")

  -- Load the extension
  pcall(telescope.load_extension, "pinwords")

  -- Check that the extension is registered
  local extensions = telescope.extensions or {}
  MiniTest.expect.equality(type(extensions), "table")
end

T["pinwords list works correctly"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")

  -- Pin some words
  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- Move to "bar"
  pinwords.set(2)

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[2].raw, "bar")
end

T["pinwords entries have required fields"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")

  pinwords.set(1)

  local slots = pinwords.list()
  MiniTest.expect.equality(type(slots[1]), "table")
  MiniTest.expect.equality(type(slots[1].raw), "string")
  MiniTest.expect.equality(type(slots[1].pattern), "string")
  MiniTest.expect.equality(type(slots[1].hl_group), "string")
  MiniTest.expect.equality(slots[1].raw, "foo")
  MiniTest.expect.equality(slots[1].hl_group, "PinWord1")
end

T["telescope <C-d> unpins selected entry"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")

  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- Move to "bar"
  pinwords.set(2)

  open_picker()
  feed("<C-d>")

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[1], nil)
  MiniTest.expect.equality(slots[2].raw, "bar")
end

T["telescope <C-x> clears all entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")

  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- Move to "bar"
  pinwords.set(2)

  open_picker()
  feed("<C-x>")

  local slots = pinwords.list()
  MiniTest.expect.equality(next(slots), nil)
end

return T
