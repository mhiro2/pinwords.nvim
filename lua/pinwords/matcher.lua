local state = require("pinwords.state")

local M = {}

---@param msg string
local function warn(msg)
  vim.notify("pinwords: " .. msg, vim.log.levels.WARN)
end

---@param buf integer
---@return integer[]
local function wins_showing_buf(buf)
  local ok, wins = pcall(vim.fn.win_findbuf, buf)
  if ok and type(wins) == "table" then
    return wins
  end

  local res = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      table.insert(res, win)
    end
  end
  return res
end

---@param win integer
---@param fn fun(): any
---@return any
local function with_win(win, fn)
  return vim.api.nvim_win_call(win, fn)
end

---@param win integer
---@param id integer|nil
local function delete_match_id(win, id)
  if not id then
    return
  end
  with_win(win, function()
    pcall(vim.fn.matchdelete, id)
  end)
end

---@param win integer
---@param slot integer
---@param entry PinwordsSlot
---@return nil
function M.apply_slot_for_window(win, slot, entry)
  local win_state = state.get_win_state(win)
  local existing = win_state.match_ids[slot]
  if existing then
    delete_match_id(win, existing)
  end

  local ok, id = pcall(with_win, win, function()
    return vim.fn.matchadd(entry.hl_group, entry.pattern)
  end)
  if not ok then
    warn(("failed to add match for slot %s: %s"):format(slot, tostring(id)))
    id = nil
  end
  if type(id) ~= "number" then
    id = nil
  end

  win_state.match_ids[slot] = id
  state.set_win_state(win, win_state)
end

---@param buf integer
---@param slot integer
---@param entry PinwordsSlot
---@return nil
function M.apply_slot_for_buffer(buf, slot, entry)
  for _, win in ipairs(wins_showing_buf(buf)) do
    M.apply_slot_for_window(win, slot, entry)
  end
end

---@param win integer
local function clear_all_for_window(win)
  local win_state = state.get_win_state(win)
  for _, id in pairs(win_state.match_ids) do
    delete_match_id(win, id)
  end
  win_state.match_ids = {}
  state.set_win_state(win, win_state)
end

---@param win integer
---@param slot integer
local function clear_slot_for_window(win, slot)
  local win_state = state.get_win_state(win)
  local id = win_state.match_ids[slot]
  if id then
    delete_match_id(win, id)
    win_state.match_ids[slot] = nil
    state.set_win_state(win, win_state)
  end
end

---@param win integer
---@return nil
function M.reapply_all_for_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  clear_all_for_window(win)

  local slots = state.get_slots()
  for slot, entry in pairs(slots) do
    M.apply_slot_for_window(win, slot, entry)
  end
end

---@param buf integer
---@param slot integer
---@return nil
function M.clear_slot_for_buffer(buf, slot)
  for _, win in ipairs(wins_showing_buf(buf)) do
    clear_slot_for_window(win, slot)
  end
end

---@param buf integer
---@return nil
function M.clear_all_for_buffer(buf)
  for _, win in ipairs(wins_showing_buf(buf)) do
    clear_all_for_window(win)
  end
end

---@param slot integer
---@param entry PinwordsSlot
---@return nil
function M.apply_slot_globally(slot, entry)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      for _, win in ipairs(wins_showing_buf(buf)) do
        M.apply_slot_for_window(win, slot, entry)
      end
    end
  end
end

---@param slot integer
---@return nil
function M.clear_slot_globally(slot)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      clear_slot_for_window(win, slot)
    end
  end
end

---@return nil
function M.clear_all_globally()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      clear_all_for_window(win)
    end
  end
end

---@param win integer
---@param existing_id integer|nil
---@param pattern string
---@return integer|nil
function M.apply_cword_for_window(win, existing_id, pattern)
  delete_match_id(win, existing_id)

  local ok, id = pcall(with_win, win, function()
    return vim.fn.matchadd("PinWordCword", pattern)
  end)
  if not ok then
    warn(("failed to add cword match: %s"):format(tostring(id)))
    return nil
  end
  if type(id) ~= "number" then
    return nil
  end
  return id
end

---@param win integer
---@param id integer|nil
---@return nil
function M.delete_match_id_for_window(win, id)
  delete_match_id(win, id)
end

---@param win integer
---@return nil
function M.clear_cword_for_window(win)
  local win_state = state.get_win_state(win)
  local cword_state = win_state.cword
  if not cword_state or not cword_state.match_id then
    return
  end

  delete_match_id(win, cword_state.match_id)
  cword_state.match_id = nil
  cword_state.pattern = nil
  win_state.cword = cword_state
  state.set_win_state(win, win_state)
end

return M
