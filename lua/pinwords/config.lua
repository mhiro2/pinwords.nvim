local M = {}

local valid_strategy = {
  first_empty = true,
  cycle = true,
  lru = true,
}

local valid_on_full = {
  replace_oldest = true,
  replace_last = true,
  no_op = true,
}

---@type PinwordsConfig
local default_config = {
  slots = 9,
  whole_word = true,
  case_sensitive = false,
  auto_allocation = {
    strategy = "first_empty",
    on_full = "replace_oldest",
    toggle_same = true,
  },
  colors = nil,
  flash = {
    enabled = true,
    timeout_ms = 120,
    hl_group = "PinWordFlash",
    priority = 250,
  },
  telescope = {
    enabled = false,
  },
  snacks = {
    enabled = false,
  },
  fzf_lua = {
    enabled = false,
  },
}

---@param hex string
---@return boolean
local function is_valid_hex(hex)
  return type(hex) == "string" and hex:match("^#%x%x%x%x%x%x$") ~= nil
end

local style_attributes = {
  "bold",
  "italic",
  "underline",
  "undercurl",
  "underdouble",
  "underdotted",
  "underdashed",
  "strikethrough",
}

---@param value any
---@return boolean
local function is_cterm_color(value)
  return type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 255
end

---Returns an error message for the first invalid field of a color spec table, or nil.
---@param value table
---@return string|nil
local function color_spec_error(value)
  for _, field in ipairs({ "bg", "fg", "sp" }) do
    if value[field] ~= nil and not is_valid_hex(value[field]) then
      return field .. " must be a valid hex color"
    end
  end
  for _, attr in ipairs(style_attributes) do
    if value[attr] ~= nil and type(value[attr]) ~= "boolean" then
      return attr .. " must be a boolean"
    end
  end
  for _, field in ipairs({ "ctermbg", "ctermfg" }) do
    if value[field] ~= nil and not is_cterm_color(value[field]) then
      return field .. " must be an integer between 0 and 255"
    end
  end
  return nil
end

---@param value any
---@param slot_name string
---@param warn fun(msg: string)
---@return PinwordsColor|nil
local function validate_color(value, slot_name, warn)
  if type(value) == "string" then
    if not is_valid_hex(value) then
      warn(slot_name .. " must be a valid hex color (e.g. #ff6b6b); ignoring")
      return nil
    end
    return value
  end

  if type(value) == "table" then
    local err = color_spec_error(value)
    if err then
      warn(slot_name .. "." .. err .. "; ignoring")
      return nil
    end
    return value
  end

  warn(slot_name .. " must be a string or table; ignoring")
  return nil
end

---@param colors table
---@param warn fun(msg: string)
---@return PinwordsColorsConfig|nil
local function sanitize_colors(colors, warn)
  local validated = {}
  local has_valid = false

  for key, value in pairs(colors) do
    if key == "cword" then
      local valid = validate_color(value, "colors.cword", warn)
      if valid then
        validated.cword = valid
        has_valid = true
      end
    elseif type(key) == "number" and key >= 1 and key % 1 == 0 then
      local valid = validate_color(value, "colors[" .. key .. "]", warn)
      if valid then
        validated[key] = valid
        has_valid = true
      end
    else
      warn("colors key must be a positive integer or 'cword'; ignoring key: " .. tostring(key))
    end
  end

  return has_valid and validated or nil
end

---@param value any
---@param validator fun(v: any): boolean
---@param default any
---@param error_msg string
---@param warn fun(msg: string)
---@return any
local function validate_field(value, validator, default, error_msg, warn)
  if not validator(value) then
    warn(error_msg)
    return default
  end
  return value
end

---@param errors string[]
---@param msg string
---@return nil
local function add_error(errors, msg)
  errors[#errors + 1] = msg
end

---@param value any
---@return boolean
local function is_integer(value)
  return type(value) == "number" and value % 1 == 0
end

---@param value any
---@return boolean
local function is_positive_integer(value)
  return is_integer(value) and value >= 1
end

---@param value any
---@return boolean
local function is_non_negative_integer(value)
  return is_integer(value) and value >= 0
end

---@param errors string[]
---@param colors any
---@return nil
local function validate_colors(errors, colors)
  if colors == nil then
    return
  end

  if type(colors) ~= "table" then
    add_error(errors, "colors must be a table or nil")
    return
  end

  for key, value in pairs(colors) do
    local key_ok = key == "cword" or (type(key) == "number" and is_positive_integer(key))
    if not key_ok then
      add_error(errors, "colors keys must be positive integers or 'cword'")
    elseif type(value) == "string" then
      if not is_valid_hex(value) then
        add_error(errors, "colors entries must use #RRGGBB when string")
      end
    elseif type(value) == "table" then
      local err = color_spec_error(value)
      if err then
        add_error(errors, "colors entry " .. err)
      end
    else
      add_error(errors, "colors entries must be string or table")
    end
  end
end

---@return PinwordsConfig
function M.default_config()
  return vim.deepcopy(default_config)
end

---@param opts? PinwordsConfig
---@param warn fun(msg: string)
---@return PinwordsConfig
function M.sanitize(opts, warn)
  if opts ~= nil and type(opts) ~= "table" then
    warn("setup opts must be a table; fallback to default")
    opts = {}
  end

  local cfg = vim.tbl_deep_extend("force", default_config, opts or {})

  cfg.slots = validate_field(cfg.slots, function(v)
    return is_positive_integer(v)
  end, default_config.slots, "slots must be a positive integer; fallback to default", warn)

  cfg.whole_word = validate_field(cfg.whole_word, function(v)
    return type(v) == "boolean"
  end, default_config.whole_word, "whole_word must be boolean; fallback to default", warn)

  cfg.case_sensitive = validate_field(cfg.case_sensitive, function(v)
    return type(v) == "boolean"
  end, default_config.case_sensitive, "case_sensitive must be boolean; fallback to default", warn)

  if type(cfg.auto_allocation) ~= "table" then
    warn("auto_allocation must be a table; fallback to default")
    cfg.auto_allocation = vim.deepcopy(default_config.auto_allocation)
  else
    cfg.auto_allocation.strategy = validate_field(
      cfg.auto_allocation.strategy,
      function(v)
        return valid_strategy[v]
      end,
      default_config.auto_allocation.strategy,
      "auto_allocation.strategy must be one of: first_empty, cycle, lru; fallback to default",
      warn
    )

    cfg.auto_allocation.on_full = validate_field(
      cfg.auto_allocation.on_full,
      function(v)
        return valid_on_full[v]
      end,
      default_config.auto_allocation.on_full,
      "auto_allocation.on_full must be one of: replace_oldest, replace_last, no_op; fallback to default",
      warn
    )

    cfg.auto_allocation.toggle_same = validate_field(
      cfg.auto_allocation.toggle_same,
      function(v)
        return type(v) == "boolean"
      end,
      default_config.auto_allocation.toggle_same,
      "auto_allocation.toggle_same must be boolean; fallback to default",
      warn
    )
  end

  if type(cfg.telescope) ~= "table" then
    warn("telescope must be a table; fallback to default")
    cfg.telescope = vim.deepcopy(default_config.telescope)
  else
    cfg.telescope.enabled = validate_field(cfg.telescope.enabled, function(v)
      return type(v) == "boolean"
    end, default_config.telescope.enabled, "telescope.enabled must be boolean; fallback to default", warn)
  end

  if type(cfg.snacks) ~= "table" then
    warn("snacks must be a table; fallback to default")
    cfg.snacks = vim.deepcopy(default_config.snacks)
  else
    cfg.snacks.enabled = validate_field(cfg.snacks.enabled, function(v)
      return type(v) == "boolean"
    end, default_config.snacks.enabled, "snacks.enabled must be boolean; fallback to default", warn)
  end

  if type(cfg.fzf_lua) ~= "table" then
    warn("fzf_lua must be a table; fallback to default")
    cfg.fzf_lua = vim.deepcopy(default_config.fzf_lua)
  else
    cfg.fzf_lua.enabled = validate_field(cfg.fzf_lua.enabled, function(v)
      return type(v) == "boolean"
    end, default_config.fzf_lua.enabled, "fzf_lua.enabled must be boolean; fallback to default", warn)
  end

  if type(cfg.flash) ~= "table" then
    warn("flash must be a table; fallback to default")
    cfg.flash = vim.deepcopy(default_config.flash)
  else
    cfg.flash.enabled = validate_field(cfg.flash.enabled, function(v)
      return type(v) == "boolean"
    end, default_config.flash.enabled, "flash.enabled must be boolean; fallback to default", warn)

    cfg.flash.timeout_ms = validate_field(cfg.flash.timeout_ms, function(v)
      return is_non_negative_integer(v)
    end, default_config.flash.timeout_ms, "flash.timeout_ms must be a non-negative integer; fallback to default", warn)

    cfg.flash.hl_group = validate_field(cfg.flash.hl_group, function(v)
      return type(v) == "string" and v ~= ""
    end, default_config.flash.hl_group, "flash.hl_group must be a non-empty string; fallback to default", warn)

    cfg.flash.priority = validate_field(cfg.flash.priority, function(v)
      return is_integer(v)
    end, default_config.flash.priority, "flash.priority must be an integer; fallback to default", warn)
  end

  if cfg.colors ~= nil then
    if type(cfg.colors) ~= "table" then
      warn("colors must be a table; ignoring")
      cfg.colors = nil
    else
      cfg.colors = sanitize_colors(cfg.colors, warn)
    end
  end

  return cfg
end

---@param cfg any
---@return string[]
function M.validate(cfg)
  local errors = {}

  if type(cfg) ~= "table" then
    add_error(errors, "config must be a table")
    return errors
  end

  if not is_positive_integer(cfg.slots) then
    add_error(errors, "slots must be a positive integer")
  end

  if type(cfg.whole_word) ~= "boolean" then
    add_error(errors, "whole_word must be boolean")
  end

  if type(cfg.case_sensitive) ~= "boolean" then
    add_error(errors, "case_sensitive must be boolean")
  end

  if type(cfg.auto_allocation) ~= "table" then
    add_error(errors, "auto_allocation must be a table")
  else
    if not valid_strategy[cfg.auto_allocation.strategy] then
      add_error(errors, "auto_allocation.strategy must be one of: first_empty, cycle, lru")
    end
    if not valid_on_full[cfg.auto_allocation.on_full] then
      add_error(errors, "auto_allocation.on_full must be one of: replace_oldest, replace_last, no_op")
    end
    if type(cfg.auto_allocation.toggle_same) ~= "boolean" then
      add_error(errors, "auto_allocation.toggle_same must be boolean")
    end
  end

  for _, key in ipairs({ "telescope", "snacks", "fzf_lua" }) do
    local picker_cfg = cfg[key]
    if type(picker_cfg) ~= "table" then
      add_error(errors, key .. " must be a table")
    elseif type(picker_cfg.enabled) ~= "boolean" then
      add_error(errors, key .. ".enabled must be boolean")
    end
  end

  if type(cfg.flash) ~= "table" then
    add_error(errors, "flash must be a table")
  else
    if type(cfg.flash.enabled) ~= "boolean" then
      add_error(errors, "flash.enabled must be boolean")
    end
    if not is_non_negative_integer(cfg.flash.timeout_ms) then
      add_error(errors, "flash.timeout_ms must be a non-negative integer")
    end
    if type(cfg.flash.hl_group) ~= "string" or cfg.flash.hl_group == "" then
      add_error(errors, "flash.hl_group must be a non-empty string")
    end
    if not is_integer(cfg.flash.priority) then
      add_error(errors, "flash.priority must be an integer")
    end
  end

  validate_colors(errors, cfg.colors)

  return errors
end

return M
