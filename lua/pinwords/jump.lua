local state = require("pinwords.state")

local M = {}

---@class PinwordsJumpGroup
---@field case_sensitive boolean
---@field bodies string[]

---Collect the pinned slots to jump through, grouped by case sensitivity.
---Vim applies `\c`/`\C` to the whole pattern, so slots that differ in case
---sensitivity cannot share one alternation; everything else is merged so the
---buffer is scanned at most once per group instead of once per slot.
---@param slot? integer
---@return PinwordsJumpGroup[]
local function get_search_groups(slot)
  local slots = state.get_slots()

  local slot_numbers
  if slot then
    slot_numbers = { slot }
  else
    slot_numbers = vim.tbl_keys(slots)
    table.sort(slot_numbers)
  end

  ---@type table<boolean, string[]>
  local bodies_by_case = {}
  for _, slot_number in ipairs(slot_numbers) do
    local entry = slots[slot_number]
    if type(entry) == "table" and type(entry.pattern) == "string" and entry.pattern ~= "" then
      local case_sensitive = entry.case_sensitive == true
      local bodies = bodies_by_case[case_sensitive]
      if not bodies then
        bodies = {}
        bodies_by_case[case_sensitive] = bodies
      end
      -- Strip the `\V\c` / `\V\C` prefix so bodies can be joined under one prefix.
      bodies[#bodies + 1] = (entry.pattern:gsub("^\\V\\[cC]", ""))
    end
  end

  local groups = {}
  for _, case_sensitive in ipairs({ true, false }) do
    local bodies = bodies_by_case[case_sensitive]
    if bodies then
      groups[#groups + 1] = { case_sensitive = case_sensitive, bodies = bodies }
    end
  end
  return groups
end

---@param group PinwordsJumpGroup
---@return string
local function group_pattern(group)
  local prefix = group.case_sensitive and "\\V\\C" or "\\V\\c"
  if #group.bodies == 1 then
    return prefix .. group.bodies[1]
  end
  return prefix .. "\\(" .. table.concat(group.bodies, "\\|") .. "\\)"
end

---@param slot? integer
---@return string[]
local function get_search_patterns(slot)
  return vim.tbl_map(group_pattern, get_search_groups(slot))
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
---@param flags string
---@return integer[]|nil
local function find_best_pos(direction, patterns, flags)
  local best
  for _, pattern in ipairs(patterns) do
    local pos = search_pos(pattern, flags)
    if pos then
      best = pick_better_pos(pos, best, direction)
    end
  end
  return best
end

---Find the nearest match without wrapping first; the wrapped search only runs
---when nothing lies ahead (or behind), so a wrap scan is never paid for while a
---closer non-wrapped match exists.
---@param direction "forward"|"backward"
---@param patterns string[]
---@return integer[]|nil
local function find_next_pos(direction, patterns)
  local no_wrap_flags = direction == "forward" and "nW" or "nbW"
  local wrap_flags = direction == "forward" and "nw" or "nbw"

  local pos = find_best_pos(direction, patterns, no_wrap_flags)
  if pos then
    return pos
  end
  return find_best_pos(direction, patterns, wrap_flags)
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

---@param direction "forward"|"backward"
---@param slot? integer
---@return boolean success
local function jump(direction, slot)
  local patterns = get_search_patterns(slot)
  if #patterns == 0 then
    vim.notify("pinwords: no pinned words to jump to", vim.log.levels.INFO)
    return false
  end

  local count = vim.v.count1

  -- Set mark for jumplist before moving
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("m'", true, false, true), "nx", false)

  local found = do_search(direction, patterns, count)
  if not found then
    vim.notify("pinwords: no more matches", vim.log.levels.INFO)
    return false
  end

  return true
end

---@param slot? integer
---@return boolean success
function M.next(slot)
  return jump("forward", slot)
end

---@param slot? integer
---@return boolean success
function M.prev(slot)
  return jump("backward", slot)
end

return M
