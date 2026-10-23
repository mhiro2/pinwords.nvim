local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

-- ============================================================================
-- Mock helpers
-- ============================================================================

---@param node_type string
---@param text string
---@param children? table[]
---@param parent? table
---@return table
local function make_mock_node(node_type, text, children, parent)
  children = children or {}
  local node = {}
  node._type = node_type
  node._text = text
  node._children = children
  node._parent = parent

  function node:type()
    return self._type
  end

  function node:named()
    return true
  end

  function node:parent()
    return self._parent
  end

  function node:iter_children()
    local i = 0
    return function()
      i = i + 1
      return self._children[i]
    end
  end

  -- Set parent reference on children
  for _, child in ipairs(children) do
    child._parent = node
  end

  return node
end

---@param overrides table
---@return table originals
local function mock_treesitter(overrides)
  local originals = {}
  for key, fn in pairs(overrides) do
    originals[key] = vim.treesitter[key]
    vim.treesitter[key] = fn
  end
  return originals
end

---@param originals table
local function restore_treesitter(originals)
  for key, fn in pairs(originals) do
    vim.treesitter[key] = fn
  end
end

-- ============================================================================
-- Unit tests: symbol.has_parser
-- ============================================================================

T["has_parser returns false when no parser available"] = function()
  helpers.setup_buffer({ "hello world" })
  local symbol = require("pinwords.symbol")
  local originals = mock_treesitter({
    get_parser = function()
      return nil
    end,
  })
  local result = symbol.has_parser(vim.api.nvim_get_current_buf())
  restore_treesitter(originals)
  MiniTest.expect.equality(result, false)
end

T["has_parser returns true when parser exists"] = function()
  helpers.setup_buffer({ "hello world" })
  local symbol = require("pinwords.symbol")
  local originals = mock_treesitter({
    get_parser = function()
      return {}
    end,
  })
  local result = symbol.has_parser(vim.api.nvim_get_current_buf())
  restore_treesitter(originals)
  MiniTest.expect.equality(result, true)
end

T["has_parser returns false when get_parser raises"] = function()
  helpers.setup_buffer({ "hello world" })
  local symbol = require("pinwords.symbol")
  local originals = mock_treesitter({
    get_parser = function()
      error("no parser for filetype")
    end,
  })
  local result = symbol.has_parser(vim.api.nvim_get_current_buf())
  restore_treesitter(originals)
  MiniTest.expect.equality(result, false)
end

-- ============================================================================
-- Unit tests: symbol.get_symbol_at_cursor
-- ============================================================================

T["get_symbol_at_cursor returns nil when no parser"] = function()
  helpers.setup_buffer({ "hello world" })
  local symbol = require("pinwords.symbol")
  local originals = mock_treesitter({
    get_parser = function()
      return nil
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, nil)
end

T["get_symbol_at_cursor returns nil when get_parser raises"] = function()
  helpers.setup_buffer({ "hello world" })
  local symbol = require("pinwords.symbol")
  local originals = mock_treesitter({
    get_parser = function()
      error("no parser for filetype")
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, nil)
end

T["get_symbol_at_cursor returns identifier text directly"] = function()
  helpers.setup_buffer({ "myFunction()" })
  local symbol = require("pinwords.symbol")
  local id_node = make_mock_node("identifier", "myFunction")
  local originals = mock_treesitter({
    get_parser = function()
      return {}
    end,
    get_node = function()
      return id_node
    end,
    get_node_text = function(node)
      return node._text
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, "myFunction")
end

T["get_symbol_at_cursor finds identifier in children"] = function()
  helpers.setup_buffer({ "function myFunc()" })
  local symbol = require("pinwords.symbol")
  local id_child = make_mock_node("identifier", "myFunc")
  local keyword_node = make_mock_node("keyword", "function", { id_child })
  -- keyword_node's parent is a function_definition with the id_child
  local func_node = make_mock_node("function_definition", "", { keyword_node, id_child })
  keyword_node._parent = func_node

  local originals = mock_treesitter({
    get_parser = function()
      return {}
    end,
    get_node = function()
      return keyword_node
    end,
    get_node_text = function(node)
      return node._text
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, "myFunc")
end

T["get_symbol_at_cursor returns nil for comment node"] = function()
  helpers.setup_buffer({ "-- this is a comment" })
  local symbol = require("pinwords.symbol")
  local comment_node = make_mock_node("comment", "-- this is a comment")
  -- No parent
  comment_node._parent = nil

  local originals = mock_treesitter({
    get_parser = function()
      return {}
    end,
    get_node = function()
      return comment_node
    end,
    get_node_text = function(node)
      return node._text
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, nil)
end

T["get_symbol_at_cursor returns nil when get_node fails"] = function()
  helpers.setup_buffer({ "hello world" })
  local symbol = require("pinwords.symbol")
  local originals = mock_treesitter({
    get_parser = function()
      return {}
    end,
    get_node = function()
      error("get_node failed")
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, nil)
end

T["get_symbol_at_cursor returns type_identifier"] = function()
  helpers.setup_buffer({ "MyClass obj" })
  local symbol = require("pinwords.symbol")
  local type_node = make_mock_node("type_identifier", "MyClass")
  local originals = mock_treesitter({
    get_parser = function()
      return {}
    end,
    get_node = function()
      return type_node
    end,
    get_node_text = function(node)
      return node._text
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, "MyClass")
end

T["get_symbol_at_cursor returns field_identifier"] = function()
  helpers.setup_buffer({ "self.field" })
  local symbol = require("pinwords.symbol")
  local field_node = make_mock_node("field_identifier", "field")
  local originals = mock_treesitter({
    get_parser = function()
      return {}
    end,
    get_node = function()
      return field_node
    end,
    get_node_text = function(node)
      return node._text
    end,
  })
  local result = symbol.get_symbol_at_cursor()
  restore_treesitter(originals)
  MiniTest.expect.equality(result, "field")
end

-- ============================================================================
-- Integration tests: set() with source="symbol"
-- ============================================================================

T["set with source=symbol falls back to cword when no parser"] = function()
  helpers.setup_buffer({ "hello world" })
  -- Ensure symbol module returns nil (no parser mock)
  local symbol_mod = require("pinwords.symbol")
  local orig_get = symbol_mod.get_symbol_at_cursor
  symbol_mod.get_symbol_at_cursor = function()
    return nil
  end

  require("pinwords").set(1, { source = "symbol" })

  symbol_mod.get_symbol_at_cursor = orig_get

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "hello")
end

T["PinWordSymbol falls back to cword when parser is missing"] = function()
  helpers.setup_buffer({ "hello world" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local originals = mock_treesitter({
    get_parser = function()
      error("no parser for filetype")
    end,
  })

  local ok = pcall(vim.cmd, "PinWordSymbol 1")

  restore_treesitter(originals)

  MiniTest.expect.equality(ok, true)
  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "hello")
end

T["set with source=symbol uses symbol when available"] = function()
  helpers.setup_buffer({ "function calculate_total()" })
  local symbol_mod = require("pinwords.symbol")
  local orig_get = symbol_mod.get_symbol_at_cursor
  symbol_mod.get_symbol_at_cursor = function()
    return "calculate_total"
  end

  require("pinwords").set(1, { source = "symbol" })

  symbol_mod.get_symbol_at_cursor = orig_get

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "calculate_total")

  local match = helpers.find_match("PinWord1")
  MiniTest.expect.equality(match ~= nil, true)
end

T["PinWordSymbol command pins via symbol source"] = function()
  helpers.setup_buffer({ "function myFunc()" })
  local symbol_mod = require("pinwords.symbol")
  local orig_get = symbol_mod.get_symbol_at_cursor
  symbol_mod.get_symbol_at_cursor = function()
    return "myFunc"
  end

  vim.cmd("PinWordSymbol")

  symbol_mod.get_symbol_at_cursor = orig_get

  local slots = require("pinwords").list()
  -- Should have pinned to some slot via auto-allocation
  local found = false
  for _, entry in pairs(slots) do
    if entry.raw == "myFunc" then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)
end

T["PinWordSymbol with slot argument pins to specific slot"] = function()
  helpers.setup_buffer({ "function myFunc()" })
  local symbol_mod = require("pinwords.symbol")
  local orig_get = symbol_mod.get_symbol_at_cursor
  symbol_mod.get_symbol_at_cursor = function()
    return "myFunc"
  end

  vim.cmd("PinWordSymbol 3")

  symbol_mod.get_symbol_at_cursor = orig_get

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[3].raw, "myFunc")
  MiniTest.expect.equality(slots[3].hl_group, "PinWord3")
end

T["PinWordSymbol toggle_same unpins existing symbol"] = function()
  helpers.setup_buffer({ "function myFunc()" })
  local symbol_mod = require("pinwords.symbol")
  local orig_get = symbol_mod.get_symbol_at_cursor
  symbol_mod.get_symbol_at_cursor = function()
    return "myFunc"
  end

  -- Pin
  vim.cmd("PinWordSymbol")
  local slots = require("pinwords").list()
  local found = false
  for _, entry in pairs(slots) do
    if entry.raw == "myFunc" then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, true)

  -- Toggle (unpin)
  vim.cmd("PinWordSymbol")
  slots = require("pinwords").list()
  found = false
  for _, entry in pairs(slots) do
    if entry.raw == "myFunc" then
      found = true
      break
    end
  end
  MiniTest.expect.equality(found, false)

  symbol_mod.get_symbol_at_cursor = orig_get
end

-- ============================================================================
-- Real Treesitter tests (skipped if lua parser not available)
-- ============================================================================

local LUA_LINES = {
  "local function myFunc(a)",
  "  foo(42, bar, 'str') -- note",
  "end",
  "function M.method() end",
}

---@return boolean
local function setup_lua_buffer()
  if not vim.treesitter.language.add("lua") then
    MiniTest.skip("lua treesitter parser not available")
    return false
  end

  -- pre_case opens a fresh buffer, so nothing has parsed it yet.
  helpers.setup_buffer(LUA_LINES)
  vim.bo.filetype = "lua"
  return true
end

T["real TS: PinWordSymbol on an unparsed buffer pins the declared name"] = function()
  if not setup_lua_buffer() then
    return
  end
  MiniTest.expect.equality(vim.treesitter.get_node({ bufnr = 0, pos = { 0, 6 } }), nil)

  -- Cursor on the "function" keyword.
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  vim.cmd("PinWordSymbol 1")

  MiniTest.expect.equality(require("pinwords").list()[1].raw, "myFunc")
end

return T
