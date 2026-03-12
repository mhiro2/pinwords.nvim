local matcher = require("pinwords.matcher")
local state = require("pinwords.state")

local M = {}

---@class PinwordsPickerItem
---@field slot integer
---@field raw string
---@field pattern string
---@field hl_group string

---@param slot integer
---@return nil
local function clear_slot(slot)
  state.clear_slot(slot)
  matcher.clear_slot_globally(slot)
end

---@return PinwordsPickerItem[]
function M.list_items()
  ---@type PinwordsPickerItem[]
  local items = {}

  for slot, entry in pairs(state.get_slots()) do
    items[#items + 1] = {
      slot = slot,
      raw = entry.raw,
      pattern = entry.pattern,
      hl_group = entry.hl_group,
    }
  end

  table.sort(items, function(a, b)
    return a.slot < b.slot
  end)

  return items
end

---@param level integer
---@return nil
function M.notify_empty(level)
  vim.notify("pinwords: no pinned words", level or vim.log.levels.INFO)
end

---@param slot integer
---@return nil
function M.notify_unpinned_slot(slot)
  vim.notify("pinwords: unpinned slot " .. slot, vim.log.levels.INFO)
end

---@param count integer
---@return nil
function M.notify_unpinned_slots(count)
  vim.notify("pinwords: unpinned " .. count .. " slot(s)", vim.log.levels.INFO)
end

---@return nil
function M.notify_cleared_all()
  vim.notify("pinwords: cleared all pins", vim.log.levels.INFO)
end

---@param slot integer|nil
---@return boolean
function M.unpin_slot(slot)
  if type(slot) ~= "number" then
    return false
  end

  clear_slot(slot)
  M.notify_unpinned_slot(slot)
  return true
end

---@param slots integer[]
---@return integer
function M.unpin_slots(slots)
  local count = 0
  local first_slot

  for _, slot in ipairs(slots) do
    if type(slot) == "number" then
      if not first_slot then
        first_slot = slot
      end
      clear_slot(slot)
      count = count + 1
    end
  end

  if count == 0 then
    return 0
  end

  if count == 1 then
    M.notify_unpinned_slot(first_slot)
  else
    M.notify_unpinned_slots(count)
  end

  return count
end

---@return nil
function M.clear_all()
  state.clear_all()
  matcher.clear_all_globally()
  M.notify_cleared_all()
end

---@param item PinwordsPickerItem
---@return string
function M.format_item(item)
  return string.format("%d: %s", item.slot, item.raw)
end

---@return nil
function M.open_select()
  local items = M.list_items()
  if #items == 0 then
    M.notify_empty(vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt = "Pinned Words (select to unpin):",
    format_item = M.format_item,
  }, function(choice)
    if choice then
      M.unpin_slot(choice.slot)
    end
  end)
end

---@param config PinwordsConfig
---@return nil
function M.open(config)
  if config.snacks.enabled then
    local ok, snacks_mod = pcall(require, "pinwords.snacks")
    if ok and type(snacks_mod) == "table" and type(snacks_mod.picker) == "function" then
      snacks_mod.picker()
      return
    end
  end

  if config.telescope.enabled then
    local ok, telescope = pcall(require, "telescope")
    if ok and telescope then
      pcall(telescope.load_extension, "pinwords")
      local ext_ok, ext = pcall(function()
        return telescope.extensions.pinwords.pinwords
      end)
      if ext_ok and ext then
        ext()
        return
      end
    end
  end

  if config.fzf_lua.enabled then
    local ok, fzf_mod = pcall(require, "pinwords.fzf_lua")
    if ok and type(fzf_mod) == "table" and type(fzf_mod.picker) == "function" then
      fzf_mod.picker()
      return
    end
  end

  M.open_select()
end

return M
