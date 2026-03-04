---@brief [[
--- pinwords.nvim integration for snacks.nvim picker
--- Provides a picker for browsing and managing pinned words
---@brief ]]

local has_snacks, snacks = pcall(require, "snacks")
if not has_snacks or not snacks.picker then
  return false
end

local pinwords = require("pinwords")

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
---@param picker PinwordsSnacksPicker
local function action_unpin_single(picker)
  local item = picker:current()
  if item then
    picker:close()
    pinwords.clear(item.slot)
    vim.notify("pinwords: unpinned slot " .. item.slot, vim.log.levels.INFO)
  end
end

---Action: Clear all pinned words (for <C-x>)
---@param picker PinwordsSnacksPicker
local function action_clear_all(picker)
  picker:close()
  pinwords.clear_all()
  vim.notify("pinwords: cleared all pins", vim.log.levels.INFO)
end

---Open snacks picker for pinned words
---@param opts? table<string, any>
local function pinwords_picker(opts)
  opts = opts or {}

  -- Get slots from pinwords
  local slots = pinwords.list()

  -- Build items array
  ---@type PinwordsSnacksItem[]
  local items = {}
  for slot, entry in pairs(slots) do
    table.insert(items, {
      idx = slot,
      id = tostring(slot),
      score = slot,
      slot = slot,
      raw = entry.raw,
      pattern = entry.pattern,
      hl_group = entry.hl_group,
    })
  end

  -- Sort by slot number
  table.sort(items, function(a, b)
    return a.slot < b.slot
  end)

  -- Early exit if empty
  if #items == 0 then
    vim.notify("pinwords: no pinned words", vim.log.levels.WARN)
    return
  end

  ---@type PinwordsSnacksPickerOpts
  local picker_opts = {
    source = "pinwords",
    title = "Pinned Words",
    items = items,
    format = format_entry,

    -- Default confirm action: unpin (with multi-select support)
    confirm = function(picker, item)
      local selected = picker:selected()
      picker:close()

      if #selected > 1 then
        -- Multi-select: unpin all selected
        for _, sel_item in ipairs(selected) do
          pinwords.clear(sel_item.slot)
        end
        vim.notify("pinwords: unpinned " .. #selected .. " slot(s)", vim.log.levels.INFO)
      elseif item then
        -- Single selection
        pinwords.clear(item.slot)
        vim.notify("pinwords: unpinned slot " .. item.slot, vim.log.levels.INFO)
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
