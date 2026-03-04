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
local pinwords = require("pinwords")

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
      { width = 2 },
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
    for _, entry in ipairs(entries) do
      if entry.value then
        pinwords.clear(entry.value.slot)
      end
    end
  end

  actions.select_default:replace(function()
    ---@type PinwordsTelescopePicker
    local picker = action_state.get_current_picker(prompt_bufnr)
    local multi_selection = picker:get_multi_selection()
    local selection = action_state.get_selected_entry()

    actions.close(prompt_bufnr)

    if #multi_selection > 0 then
      unpin_entries(multi_selection)
      vim.notify("pinwords: unpinned " .. #multi_selection .. " slot(s)", vim.log.levels.INFO)
    elseif selection and selection.value then
      pinwords.clear(selection.value.slot)
      vim.notify("pinwords: unpinned slot " .. selection.value.slot, vim.log.levels.INFO)
    end
  end)

  map("i", "<C-d>", function()
    local selection = action_state.get_selected_entry()
    actions.close(prompt_bufnr)
    if selection and selection.value then
      pinwords.clear(selection.value.slot)
    end
  end)

  map("i", "<C-x>", function()
    actions.close(prompt_bufnr)
    pinwords.clear_all()
    vim.notify("pinwords: cleared all pins", vim.log.levels.INFO)
  end)

  return true
end

---@param opts? PinwordsTelescopeOpts
local function pinwords_picker(opts)
  opts = opts or {}

  local slots = pinwords.list()

  ---@type PinwordsTelescopeItem[]
  local results = {}
  for slot, entry in pairs(slots) do
    table.insert(results, {
      slot = slot,
      raw = entry.raw,
      pattern = entry.pattern,
      hl_group = entry.hl_group,
    })
  end

  table.sort(results, function(a, b)
    return a.slot < b.slot
  end)

  if #results == 0 then
    vim.notify("pinwords: no pinned words", vim.log.levels.WARN)
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
