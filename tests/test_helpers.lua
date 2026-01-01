local M = {}

---@return nil
function M.close_extra_windows()
  local wins = vim.api.nvim_list_wins()
  for i = #wins, 2, -1 do
    vim.api.nvim_win_close(wins[i], true)
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
        require("pinwords").setup({})

        -- Reset window-local cword state.
        -- It can leak across cases because it's stored in window vars and a
        -- module-local table inside `pinwords`.
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

---@return integer
function M.match_count()
  return #vim.fn.getmatches()
end

---@param name string
function M.clear_hl(name)
  vim.cmd("hi clear " .. name)
end

---@param func function Function to run with suppressed notifications
---@return any, ... The results from calling func
function M.with_notify_override(func)
  local orig_notify = vim.notify
  local notified = {}

  vim.notify = function(msg, level, opts)
    table.insert(notified, { msg = msg, level = level, opts = opts })
  end

  local ok, result = pcall(func, notified)

  -- Always restore vim.notify, even if func throws an error
  vim.notify = orig_notify

  if not ok then
    error(result) -- re-throw the error after restoration
  end

  return result
end

return M
