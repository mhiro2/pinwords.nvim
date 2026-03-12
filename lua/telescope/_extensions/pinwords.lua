---@brief [[
--- pinwords.nvim extension for telescope.nvim
--- Provides a picker for browsing and managing pinned words
---@brief ]]

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  return nil
end

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local entry_display = require("telescope.pickers.entry_display")
local picker_common = require("pinwords.picker")

---@class PinwordsTelescopeItem
---@field slot integer
---@field raw string
---@field pattern string
---@field hl_group string

---@class PinwordsTelescopeEntry
---@field value PinwordsTelescopeItem
---@field display fun(): string
---@field ordinal string

---@class PinwordsTelescopePicker
---@field get_multi_selection fun(self: PinwordsTelescopePicker): PinwordsTelescopeEntry[]

---@class PinwordsTelescopeOpts
---@field prompt_title? string
---@field previewer? any
---@field sorter? function
---@field attach_mappings? fun(prompt_bufnr: integer, map: function): boolean

---@param _opts PinwordsTelescopeOpts
---@return fun(entry: PinwordsTelescopeItem): PinwordsTelescopeEntry
local function make_entry(_opts)
  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 3 },
      { width = 50 },
    },
  })

  return function(entry)
    local display_items = {
      { entry.slot .. ":", "TelescopePromptPrefix" },
      { entry.raw, entry.hl_group },
    }

    return {
      value = entry,
      display = function()
        return displayer(display_items)
      end,
      ordinal = entry.slot .. " " .. entry.raw,
    }
  end
end

---@param prompt_bufnr integer
---@param map fun(mode: string, lhs: string, rhs: function)
local function attach_mappings(prompt_bufnr, map)
  ---@param entries PinwordsTelescopeEntry[]
  local function unpin_entries(entries)
    local slots = {}
    for _, entry in ipairs(entries) do
      if entry.value then
        slots[#slots + 1] = entry.value.slot
      end
    end
    picker_common.unpin_slots(slots)
  end

  actions.select_default:replace(function()
    ---@type PinwordsTelescopePicker
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    local multi_selection = current_picker:get_multi_selection()
    local selection = action_state.get_selected_entry()

    actions.close(prompt_bufnr)

    if #multi_selection > 0 then
      unpin_entries(multi_selection)
    elseif selection and selection.value then
      picker_common.unpin_slot(selection.value.slot)
    end
  end)

  map("i", "<C-d>", function()
    local selection = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    if selection and selection.value then
      picker_common.unpin_slot(selection.value.slot)
    end
  end)

  map("i", "<C-x>", function()
    actions.close(prompt_bufnr)
    picker_common.clear_all()
  end)

  return true
end

---@param opts? PinwordsTelescopeOpts
local function pinwords_picker(opts)
  opts = opts or {}

  ---@type PinwordsTelescopeItem[]
  local results = picker_common.list_items()

  if #results == 0 then
    picker_common.notify_empty(vim.log.levels.WARN)
    return
  end

  pickers
    .new(opts, {
      prompt_title = "Pinned Words",
      finder = finders.new_table({
        results = results,
        entry_maker = make_entry(opts),
      }),
      sorter = conf.generic_sorter(opts),
      previewer = nil,
      attach_mappings = attach_mappings,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    pinwords = pinwords_picker,
  },
})
