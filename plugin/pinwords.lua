---@type boolean
local already_loaded = vim.g.loaded_pinwords == 1

if already_loaded then
  return
end

vim.g.loaded_pinwords = 1
