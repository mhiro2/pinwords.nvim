local M = {}

--- Flush any pending async operations (state sync, cword timer)
function M.flush_async()
  require("pinwords.state").flush_sync()
  require("pinwords").flush_cword_timer()
end

---@return nil
function M.close_extra_windows()
  local wins = vim.api.nvim_list_wins()
  for i = #wins, 2, -1 do
    if vim.api.nvim_win_is_valid(wins[i]) then
      vim.api.nvim_win_close(wins[i], true)
    end
  end
end

---@return table
function M.create_test_set()
  local MiniTest = require("mini.test")
  return MiniTest.new_set({
    hooks = {
      pre_case = function()
        M.close_extra_windows()
        vim.cmd("enew!")
        -- Clear any stray matchadd entries that are not tracked in pinwords state.
        vim.fn.clearmatches()

        -- Clear global state before setup to ensure clean state per test
        require("pinwords.state").clear_all()
        require("pinwords").setup({})

        -- Reset window-local cword state.
        -- It can leak across cases because it's kept in module-local tables
        -- (the shared window store and the cword runtime) for the reused window.
        local win = vim.api.nvim_get_current_win()
        local win_state = require("pinwords.state").get_win_state(win)
        if win_state.cword and win_state.cword.enabled then
          require("pinwords").cword_toggle()
        end
      end,
    },
  })
end

---@param lines string[]
function M.setup_buffer(lines)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

---@param direction "left"|"right"|"above"|"below"
---@return integer
function M.open_split(direction)
  local buf = vim.api.nvim_get_current_buf()
  return vim.api.nvim_open_win(buf, true, { split = direction })
end

---@return integer
function M.open_vsplit()
  return M.open_split("right")
end

---@return integer
function M.open_hsplit()
  return M.open_split("below")
end

---@param group string
---@return table|nil
function M.find_match(group)
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == group then
      return match
    end
  end
  return nil
end

---@param start_row integer
---@param start_col integer
---@param end_row integer
---@param end_col integer
function M.set_visual_marks(start_row, start_col, end_row, end_col)
  vim.fn.setpos("'<", { 0, start_row, start_col, 0 })
  vim.fn.setpos("'>", { 0, end_row, end_col, 0 })
end

---@param keys string Vimscript key notation, e.g. [[ggVj\<Esc>]]
function M.feed_normal(keys)
  vim.cmd(string.format('execute "normal! %s"', keys))
end

---@return integer
function M.match_count()
  local count = 0
  for _, match in ipairs(vim.fn.getmatches()) do
    local group = match.group
    if type(group) ~= "string" or not group:match("^PinWordFlash") then
      count = count + 1
    end
  end
  return count
end

---@param name string
function M.clear_hl(name)
  vim.cmd("hi clear " .. name)
end

---@param func function
---@return any
function M.with_notify_override(func)
  local orig_notify = vim.notify
  local notified = {}

  vim.notify = function(msg, level, opts)
    table.insert(notified, { msg = msg, level = level, opts = opts })
  end

  local ok, result = pcall(func, notified)
  vim.notify = orig_notify

  if not ok then
    error(result)
  end

  return result
end

return M
