local M = {}

---@type string[]
local palette = {
  "#ff6b6b",
  "#feca57",
  "#1dd1a1",
  "#54a0ff",
  "#5f27cd",
  "#48dbfb",
  "#00d2d3",
  "#ff9f43",
  "#c8d6e5",
}

---@type integer[]
local cterm_palette = {
  196,
  214,
  46,
  33,
  99,
  51,
  44,
  208,
  251,
}

local cword_color = "#ffd166"
local cword_cterm = 221

---@param hex string
---@return integer, integer, integer
local function hex_to_rgb(hex)
  local r = tonumber(hex:sub(2, 3), 16)
  local g = tonumber(hex:sub(4, 5), 16)
  local b = tonumber(hex:sub(6, 7), 16)
  return r, g, b
end

---@param r integer
---@param g integer
---@param b integer
---@return string
local function rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

---@param fg string
---@param bg string
---@param alpha number
---@return string
local function blend_hex(fg, bg, alpha)
  local fr, fg_g, fb = hex_to_rgb(fg)
  local br, bg_g, bb = hex_to_rgb(bg)
  local function blend_channel(f, b)
    return math.floor((f * alpha) + (b * (1 - alpha)) + 0.5)
  end
  return rgb_to_hex(blend_channel(fr, br), blend_channel(fg_g, bg_g), blend_channel(fb, bb))
end

---@return string|nil
local function normal_bg_hex()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if not ok or type(hl) ~= "table" then
    return nil
  end
  if type(hl.bg) ~= "number" then
    return nil
  end
  return string.format("#%06x", hl.bg)
end

---@param group string
---@return boolean
local function highlight_is_empty(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if not ok or type(hl) ~= "table" then
    return true
  end
  return next(hl) == nil
end

---@param slots integer
---@return nil
function M.apply(slots)
  local bg_hex = normal_bg_hex()
  local alpha = 0.5
  for i = 1, slots do
    local group = "PinWord" .. i
    if highlight_is_empty(group) then
      local color = palette[i] or "#ffffff"
      if bg_hex then
        color = blend_hex(color, bg_hex, alpha)
      end
      local cterm = cterm_palette[i] or 15
      vim.api.nvim_set_hl(0, group, { bg = color, ctermbg = cterm })
    end
  end

  if highlight_is_empty("PinWordCword") then
    local color = cword_color
    if bg_hex then
      color = blend_hex(color, bg_hex, alpha)
    end
    vim.api.nvim_set_hl(0, "PinWordCword", { bg = color, ctermbg = cword_cterm })
  end
end

return M
