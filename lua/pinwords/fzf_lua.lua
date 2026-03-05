---@brief [[
--- pinwords.nvim integration for fzf-lua
--- Provides a picker for browsing and managing pinned words
---@brief ]]

local has_fzf_lua, fzf_lua = pcall(require, "fzf-lua")
if not has_fzf_lua then
  return false
end

local pinwords = require("pinwords")

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

  local slots = pinwords.list()
  local keys = vim.tbl_keys(slots)
  table.sort(keys)

  if #keys == 0 then
    vim.notify("pinwords: no pinned words", vim.log.levels.WARN)
    return
  end

  local items = {}
  local slot_map = {}
  for _, slot in ipairs(keys) do
    local entry = slots[slot]
    local display = string.format("%d: %s", slot, entry.raw)
    table.insert(items, display)
    slot_map[display] = slot
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
          for _, sel in ipairs(selected) do
            local slot = parse_slot(sel, slot_map)
            if slot then
              pinwords.clear(slot)
            end
          end
          vim.notify("pinwords: unpinned " .. #selected .. " slot(s)", vim.log.levels.INFO)
        end,
        ["ctrl-d"] = function(selected)
          if not selected or #selected == 0 then
            return
          end
          local slot = parse_slot(selected[1], slot_map)
          if slot then
            pinwords.clear(slot)
            vim.notify("pinwords: unpinned slot " .. slot, vim.log.levels.INFO)
          end
        end,
        ["ctrl-x"] = function()
          pinwords.clear_all()
          vim.notify("pinwords: cleared all pins", vim.log.levels.INFO)
        end,
      },
    }, opts)
  )
end

local M = {}
M.picker = pinwords_picker
return M
