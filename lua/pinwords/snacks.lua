---@brief [[
--- pinwords.nvim integration for snacks.nvim picker
--- Provides a picker for browsing and managing pinned words
---@brief ]]

local has_snacks, snacks = pcall(require, "snacks")
if not has_snacks or not snacks.picker then
  return false
end

local picker_common = require("pinwords.picker")

---@class PinwordsSnacksItem
---@field idx integer
---@field id string
---@field score integer
---@field slot integer
---@field raw string
---@field pattern string
---@field hl_group string

---@alias PinwordsSnacksDisplayChunk [string, string]
---@alias PinwordsSnacksDisplay PinwordsSnacksDisplayChunk[]

---@class PinwordsSnacksPicker
---@field current fun(self: PinwordsSnacksPicker): PinwordsSnacksItem|nil
---@field selected fun(self: PinwordsSnacksPicker): PinwordsSnacksItem[]
---@field close fun(self: PinwordsSnacksPicker)

---@class PinwordsSnacksPickerOpts
---@field source string
---@field title string
---@field items PinwordsSnacksItem[]
---@field format fun(item: PinwordsSnacksItem): PinwordsSnacksDisplay
---@field confirm fun(picker: PinwordsSnacksPicker, item: PinwordsSnacksItem|nil)
---@field actions table<string, fun(picker: PinwordsSnacksPicker)>
---@field win table

---Format entry for display in picker
---@param item PinwordsSnacksItem
---@return PinwordsSnacksDisplay
local function format_entry(item)
  return {
    { item.slot .. ":", "SnacksPickerSpecial" },
    { " " .. item.raw, item.hl_group },
  }
end

---Action: Unpin single entry (for <C-d>)
---@param snacks_picker PinwordsSnacksPicker
local function action_unpin_single(snacks_picker)
  local item = snacks_picker:current()
  if item then
    snacks_picker:close()
    picker_common.unpin_slot(item.slot)
  end
end

---Action: Clear all pinned words (for <C-x>)
---@param snacks_picker PinwordsSnacksPicker
local function action_clear_all(snacks_picker)
  snacks_picker:close()
  picker_common.clear_all()
end

---Open snacks picker for pinned words
---@param opts? table<string, any>
local function pinwords_picker(opts)
  opts = opts or {}

  ---@type PinwordsSnacksItem[]
  local items = {}
  for _, item in ipairs(picker_common.list_items()) do
    items[#items + 1] = {
      idx = item.slot,
      id = tostring(item.slot),
      score = item.slot,
      slot = item.slot,
      raw = item.raw,
      pattern = item.pattern,
      hl_group = item.hl_group,
    }
  end

  if #items == 0 then
    picker_common.notify_empty(vim.log.levels.INFO)
    return
  end

  ---@type PinwordsSnacksPickerOpts
  local picker_opts = {
    source = "pinwords",
    title = "Pinned Words",
    items = items,
    format = format_entry,

    -- Default confirm action: unpin (with multi-select support)
    confirm = function(snacks_picker, item)
      local selected = snacks_picker:selected()
      snacks_picker:close()

      local slots = {}
      for _, selected_item in ipairs(selected) do
        slots[#slots + 1] = selected_item.slot
      end

      if #slots > 0 then
        picker_common.unpin_slots(slots)
      elseif item then
        picker_common.unpin_slot(item.slot)
      end
    end,

    -- Custom actions
    actions = {
      unpin_single = action_unpin_single,
      clear_all = action_clear_all,
    },

    -- Custom key mappings
    win = {
      input = {
        keys = {
          -- selene: allow(mixed_table)
          ["<C-d>"] = { "unpin_single", mode = { "n", "i" } },
          -- selene: allow(mixed_table)
          ["<C-x>"] = { "clear_all", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["<C-d>"] = "unpin_single",
          ["<C-x>"] = "clear_all",
        },
      },
    },
  }

  -- Allow caller to override any picker options (including keymaps)
  if type(opts) == "table" then
    picker_opts = vim.tbl_deep_extend("force", picker_opts, opts)
  end

  -- Open snacks picker
  snacks.picker.pick(picker_opts)
end

local M = {}
M.picker = pinwords_picker
return M
