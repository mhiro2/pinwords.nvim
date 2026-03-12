local M = {}

---@param win integer
---@return PinwordsWinState
local function ensure_win_state(win)
  local ok, win_state = pcall(vim.api.nvim_win_get_var, win, "pinwords")
  local needs_update = false

  if not ok or type(win_state) ~= "table" then
    win_state = { match_ids = {}, cword = { enabled = false } }
    needs_update = true
  end

  if type(win_state.match_ids) ~= "table" then
    win_state.match_ids = {}
    needs_update = true
  end

  if type(win_state.cword) ~= "table" then
    win_state.cword = { enabled = false }
    needs_update = true
  end

  if win_state.cword.enabled == nil then
    win_state.cword.enabled = false
    needs_update = true
  end

  if needs_update then
    local ok_set = pcall(vim.api.nvim_win_set_var, win, "pinwords", win_state)
    local _ = ok_set
  end

  return win_state
end

---@param win integer
---@return PinwordsWinState
function M.get(win)
  return ensure_win_state(win)
end

---@param win integer
---@param win_state PinwordsWinState
---@return nil
function M.set(win, win_state)
  pcall(vim.api.nvim_win_set_var, win, "pinwords", win_state)
end

return M
