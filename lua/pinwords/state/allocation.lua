local global_state = require("pinwords.state.global")

local M = {}

---@param max_slots integer
---@return integer|nil
local function find_first_empty_slot(max_slots)
  local slots = global_state.get_slots()
  for slot = 1, max_slots do
    if slots[slot] == nil then
      return slot
    end
  end
  return nil
end

---@param max_slots integer
---@return integer|nil
local function find_cycle_slot(max_slots)
  local order = global_state.get_order()
  local last_slot = type(order) == "table" and order[#order] or nil
  if not last_slot then
    return find_first_empty_slot(max_slots)
  end

  local slots = global_state.get_slots()
  for offset = 1, max_slots do
    local slot = ((last_slot + offset - 1) % max_slots) + 1
    if slots[slot] == nil then
      return slot
    end
  end
  return nil
end

---@param max_slots integer
---@return integer|nil
local function find_lru_slot(max_slots)
  local empty = find_first_empty_slot(max_slots)
  if empty then
    return empty
  end

  local order = global_state.get_order()
  if type(order) == "table" and #order > 0 then
    return order[1]
  end

  for slot in pairs(global_state.get_slots()) do
    return slot
  end
  return nil
end

---@param strategy string
---@param max_slots integer
---@return integer|nil
function M.find_available_slot(strategy, max_slots)
  if strategy == "cycle" then
    return find_cycle_slot(max_slots)
  end
  if strategy == "lru" then
    return find_lru_slot(max_slots)
  end
  return find_first_empty_slot(max_slots)
end

---@param policy string
---@return integer|nil
function M.evict_slot(policy)
  if policy == "no_op" then
    return nil
  end

  local order = global_state.get_order()
  if type(order) == "table" and #order > 0 then
    if policy == "replace_oldest" then
      return order[1]
    end
    if policy == "replace_last" then
      return order[#order]
    end
  end

  local fallback
  for slot in pairs(global_state.get_slots()) do
    if not fallback or slot < fallback then
      fallback = slot
    end
  end

  return fallback
end

return M
