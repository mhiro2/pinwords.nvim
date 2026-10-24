local M = {}

local AUGROUP_NAME = "PinWordsSelection"

-- Visual mode opens the ":" command line by typing '<,'> into it.
local VISUAL_RANGE = "'<,'>"

-- A command line that starts with a line range of its own.
local EXPLICIT_RANGE = "^[%s:]*[%d%.%$%%'/?;,+-]"

-- State of the ":" command line being edited: whether it was opened with the
-- Visual range, and whether its text can still turn out to be that range.
local editing = { visual = false, matching = false }

-- Whether the ":" command line being executed right now refers to the Visual
-- selection. Recorded on CmdlineLeave and dropped on the next event loop tick,
-- which only runs after the command itself has finished; nil when no command
-- line is being executed. It tells a typed `:1,1PinWord` apart from the
-- `:'<,'>PinWord` of Visual mode when both name the same lines.
---@type boolean|nil
local executing_visual

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

---@return boolean
local function cmdline_uses_visual_marks()
  if executing_visual == nil then
    -- Invoked without a command line (vim.cmd, nvim_cmd, @:); only the range
    -- itself is available.
    return true
  end
  return executing_visual
end

---@return nil
function M.setup()
  local group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    pattern = ":",
    callback = function()
      editing.visual = false
      editing.matching = true
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineChanged", {
    group = group,
    pattern = ":",
    callback = function()
      if not editing.matching then
        return
      end
      local text = vim.fn.getcmdline()
      if text == VISUAL_RANGE then
        editing.visual = true
        editing.matching = false
      elseif VISUAL_RANGE:sub(1, #text) ~= text then
        editing.matching = false
      end
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    pattern = ":",
    callback = function()
      local text = vim.fn.getcmdline()
      -- A modifier or a nested command can put the Visual range later in the
      -- line (`:silent '<,'>PinWord`, `:lua vim.cmd("'<,'>PinWord")`). A line
      -- opened from Visual mode also counts when the range was replaced by a
      -- command without its own range (`:<C-u>lua pin_selection()`), but not
      -- when another range replaced it (`:<C-u>1,1PinWord`).
      executing_visual = text:find("'<", 1, true) ~= nil or (editing.visual and text:match(EXPLICIT_RANGE) == nil)
      editing.matching = false
      vim.schedule(function()
        executing_visual = nil
      end)
    end,
  })
end

---@return nil
function M.teardown()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP_NAME)
  editing = { visual = false, matching = false }
  executing_visual = nil
end

---Returns the selected text, or nil and an error message when the selection
---cannot be pinned.
---@return string|nil, string|nil
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
  -- A block is a column of separate pieces; a single pattern cannot highlight
  -- only those pieces, so the selection is refused instead of pinning text that
  -- never matches.
  if mode == "\22" then
    return nil, "blockwise selection is not supported"
  end

  local ok, lines = pcall(vim.fn.getregion, start_pos, end_pos, { type = mode })
  if not ok or type(lines) ~= "table" then
    return ""
  end

  return table.concat(lines, "\n")
end

---Returns the selected text when the command was run on the last Visual
---selection, nil otherwise. A selection that cannot be pinned returns nil and
---an error message.
---@param opts PinwordsCommandOpts
---@return string|nil, string|nil
function M.resolve(opts)
  if not M.matches_range(opts) or not cmdline_uses_visual_marks() then
    return nil
  end

  return M.get()
end

return M
