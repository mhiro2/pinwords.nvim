local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

local has_telescope = pcall(require, "telescope")

if not has_telescope then
  -- `make test` installs Telescope, so a missing module is a broken setup that
  -- must fail instead of silently dropping every case below.
  T["telescope.nvim is available"] = function()
    error("telescope.nvim could not be loaded; run `make deps`")
  end
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

T["telescope extension registers the pinwords picker"] = function()
  local telescope = require("telescope")

  local ok, err = pcall(telescope.load_extension, "pinwords")
  MiniTest.expect.equality(ok, true, err)
  MiniTest.expect.equality(type(telescope.extensions.pinwords.pinwords), "function")
end

T["telescope entries expose the slot and are searchable"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  vim.api.nvim_win_set_cursor(0, { 1, 8 })
  pinwords.set(3)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  pinwords.set(1)

  open_picker()

  local action_state = require("telescope.actions.state")
  local picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
  -- Entries as produced by the extension's entry maker inside the real finder.
  local entries = { unpack(picker.finder.results) }
  table.sort(entries, function(a, b)
    return a.value.slot < b.value.slot
  end)
  -- The displayer needs the open picker's layout.
  local display, highlights = entries[2].display(entries[2])
  -- Score with the sorter the extension configured for this picker.
  local sorter = picker.sorter
  require("telescope.actions").close(vim.api.nvim_get_current_buf())

  MiniTest.expect.equality(#entries, 2)
  MiniTest.expect.equality({ entries[1].value.slot, entries[1].value.raw }, { 1, "foo" })
  MiniTest.expect.equality({ entries[2].value.slot, entries[2].value.raw }, { 3, "baz" })
  MiniTest.expect.equality(entries[1].ordinal, "1 foo")
  MiniTest.expect.equality(entries[2].ordinal, "3 baz")

  MiniTest.expect.equality(vim.trim(display), "3:  baz")
  MiniTest.expect.equality(highlights[2][2], "PinWord3")

  -- The picker's sorter keeps the pin whose ordinal matches the prompt.
  MiniTest.expect.equality(sorter:scoring_function("baz", entries[2].ordinal) >= 0, true)
  MiniTest.expect.equality(sorter:scoring_function("baz", entries[1].ordinal), -1)
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
