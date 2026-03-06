local M = {}

---@class PinwordsCommandOpts
---@field args string
---@field fargs? string[]
---@field bang? boolean
---@field line1? integer
---@field line2? integer
---@field range? integer
---@field count? integer
---@field mods? string

---@param args string
---@param max_slots integer
---@param required boolean
---@return integer|nil
local function parse_slot(args, max_slots, required)
  local slot = tonumber(args)
  if not slot then
    if args ~= "" then
      vim.notify("pinwords: slot must be a number", vim.log.levels.WARN)
      return nil
    end
    if required then
      vim.notify("pinwords: slot is required", vim.log.levels.WARN)
    end
    return nil
  end

  if slot % 1 ~= 0 or slot < 1 or slot > max_slots then
    vim.notify("pinwords: slot must be an integer between 1 and " .. max_slots, vim.log.levels.WARN)
    return nil
  end

  return slot
end

---@param opts PinwordsCommandOpts
---@return boolean
local function visual_marks_match_range(opts)
  if type(opts) ~= "table" or opts.range == nil or opts.range == 0 then
    return false
  end

  local buf = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- getpos() returns: {bufnum, lnum, col, off}
  local start_buf = start_pos[1]
  local end_buf = end_pos[1]
  if (start_buf ~= 0 and start_buf ~= buf) or (end_buf ~= 0 and end_buf ~= buf) then
    return false
  end

  local start_row = start_pos[2]
  local start_col = start_pos[3]
  local end_row = end_pos[2]
  local end_col = end_pos[3]

  if start_row == 0 or end_row == 0 then
    return false
  end

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  if type(opts.line1) ~= "number" or type(opts.line2) ~= "number" then
    return false
  end

  return start_row == opts.line1 and end_row == opts.line2
end

---@return string
local function get_visual_selection()
  local buf = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_row = start_pos[2]
  local start_col = start_pos[3]
  local end_row = end_pos[2]
  local end_col = end_pos[3]

  if start_row == 0 or end_row == 0 then
    return ""
  end

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_row - 1, end_row, false)
  if #lines == 0 then
    return ""
  end

  if start_col == 0 or end_col == 0 then
    return table.concat(lines, "\n")
  end

  ---@param line string
  ---@param col integer
  ---@return integer
  local function char_end_byte_col(line, col)
    local line_len = #line
    if line_len == 0 then
      return 0
    end

    local col0 = math.min(math.max(col - 1, 0), line_len - 1)
    local ok, char_idx
    if vim.fn.has("nvim-0.11") == 1 then
      ok, char_idx = pcall(vim.str_utfindex, line, "utf-32", col0)
    else
      ok, char_idx = pcall(vim.str_utfindex, line, col0)
    end
    if not ok then
      return line_len
    end
    local ok2, byte_idx
    if vim.fn.has("nvim-0.11") == 1 then
      ok2, byte_idx = pcall(vim.str_byteindex, line, "utf-32", char_idx + 1)
    else
      ok2, byte_idx = pcall(vim.str_byteindex, line, char_idx + 1)
    end
    if not ok2 then
      return line_len
    end
    return math.min(byte_idx, line_len)
  end

  local first_line_len = #lines[1]
  local start_byte_col = math.min(math.max(start_col - 1, 0), first_line_len)
  local end_byte_col = char_end_byte_col(lines[#lines], end_col)
  local selected = vim.api.nvim_buf_get_text(buf, start_row - 1, start_byte_col, end_row - 1, end_byte_col, {})
  return table.concat(selected, "\n")
end

---@param max_slots integer
function M.setup(max_slots)
  vim.api.nvim_create_user_command("PinWord", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end

    -- Treat range as visual selection only when '< and '> marks match the range.
    -- This avoids accidentally pinning stale visual marks for line-range calls like :1,3PinWord.
    if visual_marks_match_range(opts) then
      local raw = get_visual_selection()
      if raw == "" then
        vim.notify("pinwords: visual selection is empty", vim.log.levels.WARN)
        return
      end

      require("pinwords").set(slot, { raw = raw, whole_word = false })
      return
    end

    require("pinwords").set(slot)
  end, {
    nargs = "?",
    range = true,
    force = true,
    desc = "Pin word (auto allocation). With visual range, pin selection.",
  })

  vim.api.nvim_create_user_command("PinWordSymbol", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").set(slot, { source = "symbol" })
  end, {
    nargs = "?",
    force = true,
    desc = "Pin symbol at cursor using Treesitter (falls back to cword).",
  })

  vim.api.nvim_create_user_command("UnpinWord", function(opts)
    ---@cast opts PinwordsCommandOpts
    if opts.args == "" then
      require("pinwords").unpin()
      return
    end

    local slot = parse_slot(opts.args, max_slots, true)
    if not slot then
      return
    end
    require("pinwords").clear(slot)
  end, { nargs = "?", force = true, desc = "Unpin word under cursor, or clear slot." })

  vim.api.nvim_create_user_command("UnpinAllWords", function()
    require("pinwords").clear_all()
  end, { nargs = 0, force = true, desc = "Clear all pinned words." })

  vim.api.nvim_create_user_command("PinWordList", function()
    require("pinwords").pick()
  end, { nargs = 0, force = true, desc = "List global pinned words in interactive picker." })

  vim.api.nvim_create_user_command("PinWordCwordToggle", function()
    require("pinwords").cword_toggle()
  end, { nargs = 0, force = true, desc = "Toggle cursor word highlight (window-local)." })

  vim.api.nvim_create_user_command("PinWordNext", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").jump_next(slot)
  end, { nargs = "?", force = true, desc = "Jump to next pinned word occurrence." })

  vim.api.nvim_create_user_command("PinWordPrev", function(opts)
    ---@cast opts PinwordsCommandOpts
    local slot
    if opts.args ~= "" then
      slot = parse_slot(opts.args, max_slots, true)
      if not slot then
        return
      end
    end
    require("pinwords").jump_prev(slot)
  end, { nargs = "?", force = true, desc = "Jump to previous pinned word occurrence." })
end

return M
