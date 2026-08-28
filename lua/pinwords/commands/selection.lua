local M = {}

---@param start_row integer
---@param start_col integer
---@param end_row integer
---@param end_col integer
---@return integer, integer, integer, integer
local function normalize_region(start_row, start_col, end_row, end_col)
  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    return end_row, end_col, start_row, start_col
  end

  return start_row, start_col, end_row, end_col
end

---@param buf integer
---@return integer[]|nil, integer[]|nil
local function get_visual_marks(buf)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_buf = start_pos[1]
  local end_buf = end_pos[1]
  if (start_buf ~= 0 and start_buf ~= buf) or (end_buf ~= 0 and end_buf ~= buf) then
    return nil, nil
  end

  return start_pos, end_pos
end

---@param opts PinwordsCommandOpts
---@return boolean
function M.matches_range(opts)
  if type(opts) ~= "table" or opts.range == nil or opts.range == 0 then
    return false
  end

  if type(opts.line1) ~= "number" or type(opts.line2) ~= "number" then
    return false
  end

  local buf = vim.api.nvim_get_current_buf()
  local start_pos, end_pos = get_visual_marks(buf)
  if not start_pos or not end_pos then
    return false
  end

  local start_row = start_pos[2]
  local start_col = start_pos[3]
  local end_row = end_pos[2]
  local end_col = end_pos[3]

  if start_row == 0 or end_row == 0 then
    return false
  end

  start_row, start_col, end_row, end_col = normalize_region(start_row, start_col, end_row, end_col)
  return start_row == opts.line1 and end_row == opts.line2
end

---@return string
function M.get()
  local buf = vim.api.nvim_get_current_buf()
  local start_pos, end_pos = get_visual_marks(buf)
  if not start_pos or not end_pos then
    return ""
  end

  if start_pos[2] == 0 or end_pos[2] == 0 then
    return ""
  end

  -- visualmode() reports the last Visual mode used in the current buffer, so
  -- charwise/linewise/blockwise selections (and 'selection=exclusive') are all
  -- resolved the same way Neovim itself resolves them.
  local mode = vim.fn.visualmode()
  if mode == "" then
    mode = "v"
  end

  local ok, lines = pcall(vim.fn.getregion, start_pos, end_pos, { type = mode })
  if not ok or type(lines) ~= "table" then
    return ""
  end

  return table.concat(lines, "\n")
end

---@param opts PinwordsCommandOpts
---@return string|nil
function M.resolve(opts)
  if not M.matches_range(opts) then
    return nil
  end

  return M.get()
end

return M
