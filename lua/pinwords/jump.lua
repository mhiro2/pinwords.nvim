local state = require("pinwords.state")

local M = {}

---@param slot? integer
---@return string[]
local function get_search_patterns(slot)
  local slots = state.get_slots()

  if slot then
    local entry = slots[slot]
    if type(entry) == "table" and type(entry.pattern) == "string" and entry.pattern ~= "" then
      return { entry.pattern }
    end
    return {}
  end

  local slot_numbers = vim.tbl_keys(slots)
  table.sort(slot_numbers)

  local patterns = {}
  for _, slot_number in ipairs(slot_numbers) do
    local entry = slots[slot_number]
    if type(entry) == "table" and type(entry.pattern) == "string" and entry.pattern ~= "" then
      table.insert(patterns, entry.pattern)
    end
  end

  return patterns
end

---@param pos table
---@return boolean
local function is_valid_pos(pos)
  return type(pos) == "table" and type(pos[1]) == "number" and type(pos[2]) == "number" and pos[1] > 0 and pos[2] > 0
end

---@param pattern string
---@param flags string
---@return integer[]|nil
local function search_pos(pattern, flags)
  local ok, pos = pcall(vim.fn.searchpos, pattern, flags)
  if not ok or not is_valid_pos(pos) then
    return nil
  end
  return { pos[1], pos[2] }
end

---@param pos integer[]
---@param best integer[]|nil
---@param direction "forward"|"backward"
---@return integer[]|nil
local function pick_better_pos(pos, best, direction)
  if not best then
    return pos
  end

  if direction == "forward" then
    if pos[1] < best[1] or (pos[1] == best[1] and pos[2] < best[2]) then
      return pos
    end
    return best
  end

  if pos[1] > best[1] or (pos[1] == best[1] and pos[2] > best[2]) then
    return pos
  end
  return best
end

---@param direction "forward"|"backward"
---@param patterns string[]
---@return integer[]|nil
local function find_next_pos(direction, patterns)
  local no_wrap_flags = direction == "forward" and "nW" or "nbW"
  local wrap_flags = direction == "forward" and "nw" or "nbw"

  local no_wrap_best
  local wrap_best
  for _, pattern in ipairs(patterns) do
    local no_wrap_pos = search_pos(pattern, no_wrap_flags)
    if no_wrap_pos then
      no_wrap_best = pick_better_pos(no_wrap_pos, no_wrap_best, direction)
    else
      local wrap_pos = search_pos(pattern, wrap_flags)
      if wrap_pos then
        wrap_best = pick_better_pos(wrap_pos, wrap_best, direction)
      end
    end
  end

  if no_wrap_best then
    return no_wrap_best
  end
  return wrap_best
end

---@param direction "forward"|"backward"
---@param patterns string[]
---@param count integer
---@return boolean
local function do_search(direction, patterns, count)
  local found = false

  for _ = 1, count do
    local pos = find_next_pos(direction, patterns)
    if not pos then
      break
    end
    vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] - 1 })
    found = true
  end

  return found
end

---@param slot? integer
---@return boolean success
function M.next(slot)
  local patterns = get_search_patterns(slot)
  if #patterns == 0 then
    vim.notify("pinwords: no pinned words to jump to", vim.log.levels.INFO)
    return false
  end

  local count = vim.v.count1

  -- Set mark for jumplist before moving
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("m'", true, false, true), "nx", false)

  local found = do_search("forward", patterns, count)
  if not found then
    vim.notify("pinwords: no more matches", vim.log.levels.INFO)
    return false
  end

  return true
end

---@param slot? integer
---@return boolean success
function M.prev(slot)
  local patterns = get_search_patterns(slot)
  if #patterns == 0 then
    vim.notify("pinwords: no pinned words to jump to", vim.log.levels.INFO)
    return false
  end

  local count = vim.v.count1

  -- Set mark for jumplist before moving
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("m'", true, false, true), "nx", false)

  local found = do_search("backward", patterns, count)
  if not found then
    vim.notify("pinwords: no more matches", vim.log.levels.INFO)
    return false
  end

  return true
end

return M
