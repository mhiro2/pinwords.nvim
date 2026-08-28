local M = {}

---@type string[]
local default_palette = {
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
local default_cterm_palette = {
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

local default_cword_color = "#ffd166"
local default_cword_cterm = 221

---@param hex string
---@return integer, integer, integer
local function hex_to_rgb(hex)
  local r = tonumber(hex:sub(2, 3), 16) or 0
  local g = tonumber(hex:sub(4, 5), 16) or 0
  local b = tonumber(hex:sub(6, 7), 16) or 0
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

---Highlight definitions last written by this module, keyed by group name.
---Used to distinguish plugin-owned groups (safe to overwrite) from user-defined ones.
---@type table<string, table>
local applied = {}

---Returns the group's own definition (links are reported as `link`, not resolved).
---@param group string
---@return table|nil
local function get_hl(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = true })
  if not ok or type(hl) ~= "table" then
    return nil
  end
  return hl
end

---Returns true when the group is undefined or still holds the definition this
---module wrote last time; false when the user (or another plugin) defined it.
---@param group string
---@return boolean
local function is_plugin_owned(group)
  local hl = get_hl(group)
  if not hl or next(hl) == nil then
    return true
  end
  local prev = applied[group]
  return prev ~= nil and vim.deep_equal(prev, hl)
end

---@param group string
---@param opts table
---@return nil
local function set_hl(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
  applied[group] = get_hl(group)
end

---@param hex string
---@return integer|nil
local function hex_to_cterm(hex)
  -- Simple approximation: map hex to nearest xterm-256 color
  local r, g, b = hex_to_rgb(hex)
  if r == g and g == b then
    -- Grayscale
    if r < 8 then
      return 16
    end
    if r > 248 then
      return 231
    end
    return math.floor((r - 8) / 247 * 24 + 0.5) + 232
  end
  -- Color cube
  local function to_cube(v)
    if v < 48 then
      return 0
    end
    if v < 115 then
      return 1
    end
    return math.floor((v - 35) / 40)
  end
  return 16 + 36 * to_cube(r) + 6 * to_cube(g) + to_cube(b)
end

---@param value PinwordsColor
---@return PinwordsColorSpec
local function normalize_color(value)
  if type(value) == "string" then
    return { bg = value }
  end
  return value
end

---@param spec PinwordsColorSpec
---@param bg_hex string|nil
---@param alpha number
---@return PinwordsColorSpec
local function apply_blend(spec, bg_hex, alpha)
  if not bg_hex or not spec.bg then
    return spec
  end
  -- Only blend if no fg is specified (preserve original behavior)
  if spec.fg then
    return spec
  end
  local result = vim.deepcopy(spec)
  result.bg = blend_hex(spec.bg, bg_hex, alpha)
  return result
end

---@param spec PinwordsColorSpec
---@param default_cterm integer
---@return table
local function build_hl_opts(spec, default_cterm)
  local opts = {}

  if spec.bg then
    opts.bg = spec.bg
    opts.ctermbg = spec.ctermbg or hex_to_cterm(spec.bg) or default_cterm
  elseif spec.ctermbg then
    opts.ctermbg = spec.ctermbg
  end

  if spec.fg then
    opts.fg = spec.fg
    opts.ctermfg = spec.ctermfg or hex_to_cterm(spec.fg)
  elseif spec.ctermfg then
    opts.ctermfg = spec.ctermfg
  end

  if spec.bold then
    opts.bold = true
  end
  if spec.italic then
    opts.italic = true
  end
  if spec.underline then
    opts.underline = true
  end
  if spec.undercurl then
    opts.undercurl = true
  end
  if spec.underdouble then
    opts.underdouble = true
  end
  if spec.underdotted then
    opts.underdotted = true
  end
  if spec.underdashed then
    opts.underdashed = true
  end
  if spec.strikethrough then
    opts.strikethrough = true
  end

  if spec.sp then
    opts.sp = spec.sp
  end

  return opts
end

---@param slots integer
---@param colors? PinwordsColorsConfig
---@return nil
function M.apply(slots, colors)
  local bg_hex = normal_bg_hex()
  local alpha = 0.5
  colors = colors or {}

  for i = 1, slots do
    local group = "PinWord" .. i
    if is_plugin_owned(group) then
      local user_color = colors[i]
      local spec

      if user_color then
        spec = normalize_color(user_color)
      else
        spec = { bg = default_palette[i] or "#ffffff" }
      end

      spec = apply_blend(spec, bg_hex, alpha)
      local default_cterm = default_cterm_palette[i] or 15
      local opts = build_hl_opts(spec, default_cterm)
      set_hl(group, opts)
    end
  end

  local cword_group = "PinWordCword"
  if is_plugin_owned(cword_group) then
    local user_cword = colors.cword
    local spec

    if user_cword then
      spec = normalize_color(user_cword)
    else
      spec = { bg = default_cword_color }
    end

    spec = apply_blend(spec, bg_hex, alpha)
    local opts = build_hl_opts(spec, default_cword_cterm)
    set_hl(cword_group, opts)
  end

  local flash_group = "PinWordFlash"
  if is_plugin_owned(flash_group) then
    set_hl(flash_group, { link = "IncSearch" })
  end
end

return M
