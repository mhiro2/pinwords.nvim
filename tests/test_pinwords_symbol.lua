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

T["set without source option uses cword as before"] = function()
  helpers.setup_buffer({ "foo bar baz" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  require("pinwords").set(1)

  local slots = require("pinwords").list()
  MiniTest.expect.equality(slots[1].raw, "foo")
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

T["real TS: extracts function name in Lua"] = function()
  local parser = vim.treesitter.get_parser(0, "lua")
  if not parser then
    MiniTest.skip("lua treesitter parser not available")
    return
  end

  helpers.setup_buffer({ "local function calculate_total(x, y)", "  return x + y", "end" })
  vim.bo.filetype = "lua"

  -- Force parse to ensure tree is available
  parser = vim.treesitter.get_parser(0, "lua")
  parser:parse()

  -- Cursor on function name
  vim.api.nvim_win_set_cursor(0, { 1, 16 })
  local symbol = require("pinwords.symbol")
  local result = symbol.get_symbol_at_cursor()
  MiniTest.expect.equality(result, "calculate_total")
end

T["real TS: extracts identifier from keyword position in Lua"] = function()
  local parser = vim.treesitter.get_parser(0, "lua")
  if not parser then
    MiniTest.skip("lua treesitter parser not available")
    return
  end

  helpers.setup_buffer({ "local function myFunc()", "end" })
  vim.bo.filetype = "lua"

  parser = vim.treesitter.get_parser(0, "lua")
  parser:parse()

  -- Cursor on "function" keyword
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  local symbol = require("pinwords.symbol")
  local result = symbol.get_symbol_at_cursor()

  -- Should find "myFunc" (the identifier child of function_definition),
  -- not the "function" keyword itself.
  MiniTest.expect.equality(result, "myFunc")
end

return T
