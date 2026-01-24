local state = require("pinwords.state")

local M = {}

---@param patterns string[]
---@return string
local function build_combined_pattern(patterns)
  -- \| で結合（Vim正規表現のOR）
  return table.concat(patterns, "\\|")
end

---@param slot? integer
---@return string|nil
local function get_search_pattern(slot)
  local slots = state.get_slots()

  if slot then
    local entry = slots[slot]
    return entry and entry.pattern or nil
  end

  -- 全スロットのパターンを収集
  local patterns = {}
  for _, entry in pairs(slots) do
    if entry.pattern then
      table.insert(patterns, entry.pattern)
    end
  end

  if #patterns == 0 then
    return nil
  end

  return build_combined_pattern(patterns)
end

---@param direction "forward"|"backward"
---@param pattern string
---@param count integer
---@return boolean found
local function do_search(direction, pattern, count)
  local flags = direction == "forward" and "W" or "bW"
  local wrap_flags = direction == "forward" and "w" or "bw"
  local found = false

  for _ = 1, count do
    -- First try without wrap
    local result = vim.fn.search(pattern, flags)
    if result == 0 then
      -- Wrap and try again
      result = vim.fn.search(pattern, wrap_flags)
      if result == 0 then
        break
      end
    end
    found = true
  end

  return found
end

---@param slot? integer
---@return boolean success
function M.next(slot)
  local pattern = get_search_pattern(slot)
  if not pattern then
    vim.notify("pinwords: no pinned words to jump to", vim.log.levels.INFO)
    return false
  end

  local count = vim.v.count1

  -- Set mark for jumplist before moving
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("m'", true, false, true), "nx", false)

  local found = do_search("forward", pattern, count)
  if not found then
    vim.notify("pinwords: no more matches", vim.log.levels.INFO)
    return false
  end

  return true
end

---@param slot? integer
---@return boolean success
function M.prev(slot)
  local pattern = get_search_pattern(slot)
  if not pattern then
    vim.notify("pinwords: no pinned words to jump to", vim.log.levels.INFO)
    return false
  end

  local count = vim.v.count1

  -- Set mark for jumplist before moving
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("m'", true, false, true), "nx", false)

  local found = do_search("backward", pattern, count)
  if not found then
    vim.notify("pinwords: no more matches", vim.log.levels.INFO)
    return false
  end

  return true
end

return M
