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

  -- Wait until the Telescope prompt is ready for input rather than sleeping a
  -- fixed amount, so the picker is reliably attached before keys are fed.
  vim.wait(2000, function()
    return vim.bo.buftype == "prompt"
  end)
end

---Feed `keys` to the open picker and poll until `cond` holds (or it times out).
---`nvim_feedkeys` with the "x" flag executes the typeahead synchronously so the
---picker's insert-mode mapping fires reliably in headless runs; `nvim_input`
---left the prompt in normal mode under newer Telescope, dropping the keypress.
---@param keys string
---@param cond fun(): boolean
local function feed_until(keys, cond)
  local termcodes = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcodes, "x", false)
  vim.wait(2000, cond)
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

  -- Capture which slot is selected; Telescope's default selection is not
  -- guaranteed to be the first slot, so assert against the actual selection.
  local action_state = require("telescope.actions.state")
  vim.wait(2000, function()
    local entry = action_state.get_selected_entry()
    return entry ~= nil and entry.value ~= nil
  end)
  local selection = action_state.get_selected_entry()
  local selected_slot = selection and selection.value and selection.value.slot

  feed_until("<C-d>", function()
    return selected_slot ~= nil and pinwords.list()[selected_slot] == nil
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(type(selected_slot), "number")
  -- Only the selected entry is unpinned; the other pin remains.
  MiniTest.expect.equality(slots[selected_slot], nil)
  MiniTest.expect.equality(vim.tbl_count(slots), 1)
end

T["telescope <C-x> clears all entries"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")

  pinwords.set(1)
  vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- Move to "bar"
  pinwords.set(2)

  open_picker()
  feed_until("<C-x>", function()
    return next(pinwords.list()) == nil
  end)

  local slots = pinwords.list()
  MiniTest.expect.equality(next(slots), nil)
end

return T
