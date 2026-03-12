---@brief [[
--- pinwords.nvim integration for fzf-lua
--- Provides a picker for browsing and managing pinned words
---@brief ]]

local has_fzf_lua, fzf_lua = pcall(require, "fzf-lua")
if not has_fzf_lua then
  return false
end

local picker = require("pinwords.picker")

---@param selected string
---@param slot_map table<string, integer>
---@return integer|nil
local function parse_slot(selected, slot_map)
  if slot_map[selected] then
    return slot_map[selected]
  end
  return nil
end

---Open fzf-lua picker for pinned words
---@param opts? table
local function pinwords_picker(opts)
  opts = opts or {}

  local picker_items = picker.list_items()

  if #picker_items == 0 then
    picker.notify_empty(vim.log.levels.WARN)
    return
  end

  local items = {}
  local slot_map = {}
  for _, item in ipairs(picker_items) do
    local display = picker.format_item(item)
    table.insert(items, display)
    slot_map[display] = item.slot
  end

  fzf_lua.fzf_exec(
    items,
    vim.tbl_deep_extend("force", {
      prompt = "Pinned Words> ",
      actions = {
        ["default"] = function(selected)
          if not selected or #selected == 0 then
            return
          end
          local slots = {}
          for _, sel in ipairs(selected) do
            local slot = parse_slot(sel, slot_map)
            if slot then
              slots[#slots + 1] = slot
            end
          end
          picker.unpin_slots(slots)
        end,
        ["ctrl-d"] = function(selected)
          if not selected or #selected == 0 then
            return
          end
          local slot = parse_slot(selected[1], slot_map)
          picker.unpin_slot(slot)
        end,
        ["ctrl-x"] = function()
          picker.clear_all()
        end,
      },
    }, opts)
  )
end

local M = {}
M.picker = pinwords_picker
return M
