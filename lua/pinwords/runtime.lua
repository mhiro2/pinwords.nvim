local cword = require("pinwords.runtime.cword")
local flash = require("pinwords.flash")
local highlight = require("pinwords.highlight")
local matcher = require("pinwords.matcher")

local M = {}

---@class PinwordsRuntimeConfig
---@field augroup_name string
---@field slots integer
---@field colors? PinwordsColorsConfig
---@field build_pattern fun(raw: string): string
---@field cword_debounce_ms integer

---@type PinwordsRuntimeConfig
local config = {
  augroup_name = "PinWords",
  slots = 8,
  colors = nil,
  build_pattern = function(raw)
    return raw
  end,
  cword_debounce_ms = 50,
}

---@type table<integer, boolean>
local pending_reapply_wins = {}

---@param args table|nil
---@return integer
local function resolve_autocmd_win(args)
  local win = type(args) == "table" and args.win or nil
  if type(win) ~= "number" or win == 0 then
    win = vim.api.nvim_get_current_win()
  end
  return win
end

---@param win integer
---@return nil
local function reapply_window(win)
  matcher.reapply_all_for_window(win)
  cword.reapply_for_window(win)
end

---@return nil
local function reapply_all_windows()
  cword.cleanup_stale_windows()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    reapply_window(win)
  end
end

---@param opts? Partial<PinwordsRuntimeConfig>
---@return nil
function M.setup(opts)
  if type(opts) == "table" then
    if type(opts.augroup_name) == "string" and opts.augroup_name ~= "" then
      config.augroup_name = opts.augroup_name
    end
    if type(opts.slots) == "number" then
      config.slots = opts.slots
    end
    config.colors = opts.colors
    if type(opts.build_pattern) == "function" then
      config.build_pattern = opts.build_pattern
    end
    if type(opts.cword_debounce_ms) == "number" and opts.cword_debounce_ms >= 0 then
      config.cword_debounce_ms = math.floor(opts.cword_debounce_ms)
    end
  end

  pending_reapply_wins = {}
  cword.configure({
    build_pattern = config.build_pattern,
    debounce_ms = config.cword_debounce_ms,
  })
  reapply_all_windows()

  local group = vim.api.nvim_create_augroup(config.augroup_name, { clear = true })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(args)
      local win = resolve_autocmd_win(args)
      if pending_reapply_wins[win] then
        return
      end
      pending_reapply_wins[win] = true
      vim.schedule(function()
        pending_reapply_wins[win] = nil
      end)

      reapply_window(win)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function()
      cword.handle_cursor_moved(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      highlight.apply(config.slots, config.colors)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        cword.handle_win_closed(win)
        flash.clear_for_window(win)
      end
    end,
  })
end

---@return nil
function M.toggle_cword()
  cword.toggle(vim.api.nvim_get_current_win())
end

---@return nil
function M.flush_cword()
  cword.flush_current()
end

---@return nil
function M.teardown()
  cword.teardown()
  pcall(vim.api.nvim_del_augroup_by_name, config.augroup_name)
  pending_reapply_wins = {}
end

return M
