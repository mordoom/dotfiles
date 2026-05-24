-- Standalone test suite for react_extractor.lua
-- Run with:  lua5.4 test_react_extractor.lua

-- ── Minimal vim mock (no Neovim needed) ──────────────────────────────────────

vim = {
  split = function(str, sep)
    local result = {}
    local s = 1
    while s <= #str + 1 do
      local found = str:find(sep, s, true)
      if found then
        table.insert(result, str:sub(s, found - 1))
        s = found + #sep
      else
        table.insert(result, str:sub(s))
        break
      end
    end
    return result
  end,
  trim = function(s) return s:match("^%s*(.-)%s*$") end,
  list_extend = function(list, other)
    for _, v in ipairs(other) do table.insert(list, v) end
    return list
  end,
  deepcopy = function(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = vim.deepcopy(v) end
    return c
  end,
  log      = { levels = { INFO = 2, WARN = 3, ERROR = 4 } },
  notify   = function() end,
  uri_from_fname = function(f) return "file://" .. f end,
  api = {
    nvim_buf_get_lines      = function() return {} end,
    nvim_buf_set_lines      = function() end,
    nvim_buf_line_count     = function() return 0 end,
    nvim_buf_get_name       = function() return "/fake/App.tsx" end,
    nvim_win_set_cursor     = function() end,
    nvim_create_user_command = function() end,
    nvim_get_current_buf    = function() return 1 end,
  },
  lsp  = { get_clients = function() return {} end },
  fn   = {
    stdpath  = function() return "/fake/config" end,
    getpos   = function() return { 0, 1, 1, 0 } end,
    writefile = function() return 0 end,
    cursor   = function() end,
  },
  keymap = { set = function() end },
  ui     = { input = function() end },
}

-- ── Load the module ───────────────────────────────────────────────────────────

local ok, M = pcall(dofile, ".config/nvim/lua/react_extractor.lua")
if not ok then
  io.stderr:write("LOAD ERROR: " .. tostring(M) .. "\n")
  os.exit(1)
end
local t = M._t

-- ── Tiny test harness ─────────────────────────────────────────────────────────

local pass, fail = 0, 0

local function eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table"  then return a == b end
  for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
  for k, v in pairs(b) do if not eq(v, a[k]) then return false end end
  return true
end

local function check(label, got, want)
  if eq(got, want) then
    pass = pass + 1
    print("  PASS  " .. label)
  else
    fail = fail + 1
    print("  FAIL  " .. label)
    print("    got:  " .. vim.trim(tostring(got)))
    print("    want: " .. vim.trim(tostring(want)))
  end
end

local function check_has(label, tbl, key)
  if tbl[key] then
    pass = pass + 1
    print("  PASS  " .. label)
  else
    fail = fail + 1
    print("  FAIL  " .. label .. " (missing key: " .. key .. ")")
  end
end

local function check_not(label, tbl, key)
  if not tbl[key] then
    pass = pass + 1
    print("  PASS  " .. label)
  else
    fail = fail + 1
    print("  FAIL  " .. label .. " (unexpected key: " .. key .. ")")
  end
end

local function section(name)
  print("\n── " .. name .. " ──")
end

-- ── Tests ─────────────────────────────────────────────────────────────────────

section("get_declarations")
do
  local d = t.get_declarations({
    "  const title = 'hello'",
    "  let count = 0",
    "  var old = true",
  })
  check_has("const declaration",  d, "title")
  check_has("let declaration",    d, "count")
  check_has("var declaration",    d, "old")

  local d2 = t.get_declarations({ "  const { name, age } = props" })
  check_has("object destructure name", d2, "name")
  check_has("object destructure age",  d2, "age")

  local d3 = t.get_declarations({ "  const [first, second] = list" })
  check_has("array destructure first",  d3, "first")
  check_has("array destructure second", d3, "second")

  local d4 = t.get_declarations({ "  items.map((item, idx) => item.id)" })
  check_has("arrow multi-param item", d4, "item")
  check_has("arrow multi-param idx",  d4, "idx")

  local d5 = t.get_declarations({ "  data.forEach(row => row.id)" })
  check_has("single arrow param", d5, "row")
end

section("get_used – definitely external")
do
  local u = t.get_used({ "  <Button onClick={handleClick} />" })
  check_has("JSX prop value", u, "handleClick")

  local u2 = t.get_used({ "  {isVisible && <span>{message}</span>}" })
  check_has("logical && lhs",  u2, "isVisible")
  check_has("JSX child ident", u2, "message")

  local u3 = t.get_used({ "  <Card title={title} />" })
  check_has("JSX component name Card", u3, "Card")
  check_has("JSX prop value title",    u3, "title")

  local u4 = t.get_used({ "  className={styles.container}" })
  check_has("object member root styles", u4, "styles")

  local u5 = t.get_used({ "  {...spreadProps}" })
  check_has("spread identifier", u5, "spreadProps")
end

section("get_used – object literal keys excluded")
do
  local u = t.get_used({ "  style={{ color: 'red', fontWeight: 'bold' }}" })
  check_not("object key color excluded",      u, "color")
  check_not("object key fontWeight excluded", u, "fontWeight")

  -- value passed as object prop IS still picked up via ={id pattern
  local u2 = t.get_used({ "  value={myValue}" })
  check_has("explicit prop value myValue kept", u2, "myValue")
end

section("get_used – globals and HTML filtered (via compute_props path)")
do
  -- get_used itself doesn't filter; just confirm globals appear in raw output
  -- and would be removed by compute_props. Check a few don't sneak through as
  -- false positives from the pattern side.
  local u = t.get_used({ "  {useState(0)}" })
  -- useState is captured as a function call {id(  pattern
  check_has("useState in raw used (filtered later by GLOBALS)", u, "useState")
end

section("infer_type_heuristic")
do
  check("children",     t.infer_type_heuristic("children"),   "React.ReactNode")
  check("className",    t.infer_type_heuristic("className"),  "string")
  check("style",        t.infer_type_heuristic("style"),      "React.CSSProperties")
  check("onClick",      t.infer_type_heuristic("onClick"),    "(...args: unknown[]) => void")
  check("handleSubmit", t.infer_type_heuristic("handleSubmit"), "(...args: unknown[]) => void")
  check("isOpen",       t.infer_type_heuristic("isOpen"),     "boolean")
  check("hasError",     t.infer_type_heuristic("hasError"),   "boolean")
  check("disabled",     t.infer_type_heuristic("disabled"),   "boolean")
  check("itemCount",    t.infer_type_heuristic("itemCount"),  "number")
  check("pageIndex",    t.infer_type_heuristic("pageIndex"),  "number")
  check("labelText",    t.infer_type_heuristic("labelText"),  "string")
  check("itemList",     t.infer_type_heuristic("itemList"),   "unknown[]")
  check("unknown",      t.infer_type_heuristic("fooBar"),     "unknown")
end

section("parse_hover_type")
do
  check("plain type",
    t.parse_hover_type("```typescript\n(parameter) foo: string\n```"),
    "string")
  check("function type",
    t.parse_hover_type("```typescript\nconst handleClick: () => void\n```"),
    "() => void")
  check("complex type",
    t.parse_hover_type("```typescript\nlet items: Item[]\n```"),
    "Item[]")
  check("union type",
    t.parse_hover_type("```typescript\nconst value: string | null\n```"),
    "string | null")
  check("no code fence",
    t.parse_hover_type("(parameter) bar: number"),
    "number")
end

section("min_indent")
do
  check("two-space indent",
    t.min_indent({ "  <div>", "    <span />", "  </div>" }), 2)
  check("no indent",
    t.min_indent({ "<div>", "  <span />", "</div>" }), 0)
  check("skips blank lines",
    t.min_indent({ "", "    <p />", "" }), 4)
end

section("build_usage")
do
  local u = t.build_usage("Card", {}, "  ")
  check("no props self-closing", u, { "  <Card />" })

  local props = { { name = "title", type = "string" }, { name = "onClick", type = "() => void" } }
  local u2 = t.build_usage("Card", props, "  ")
  check("short enough single line", u2, { '  <Card title={title} onClick={onClick} />' })
end

section("build_component – no props")
do
  local body = { "      <div>hello</div>" }
  local lines = t.build_component("Hello", {}, body, false)
  check("function signature no props", lines[1], "function Hello() {")
  check("return open",                 lines[2], "  return (")
  check("body re-indented",            lines[3], "    <div>hello</div>")
  check("return close",                lines[4], "  );")
  check("closing brace",               lines[5], "}")
end

section("build_component – with props")
do
  local props = { { name = "label", type = "string" } }
  local body  = { "  <span>{label}</span>" }
  local lines = t.build_component("Tag", props, body, false)
  check("interface header",    lines[1], "interface TagProps {")
  check("prop entry",          lines[2], "  label: string;")
  check("interface close",     lines[3], "}")
  check("blank line",          lines[4], "")
  check("function with param", lines[5], "function Tag({ label }: TagProps) {")
end

section("build_component – named export for new file")
do
  local lines = t.build_component("Modal", {}, { "<div />" }, true)
  check("export function prefix", lines[1], "export function Modal() {")
end

section("is_component_declaration")
do
  check("function Foo",          t.is_component_declaration("function Foo() {"),          true)
  check("export function Foo",   t.is_component_declaration("export function Foo() {"),   true)
  check("export default function Foo", t.is_component_declaration("export default function Foo() {"), true)
  check("const Foo =",           t.is_component_declaration("const Foo = () => {"),       true)
  check("export const Foo =",    t.is_component_declaration("export const Foo = () => {"), true)
  check("lowercase fn ignored",  t.is_component_declaration("function helper() {"),       false)
  check("random line ignored",   t.is_component_declaration("  const x = 1"),             false)
end

-- ── Summary ───────────────────────────────────────────────────────────────────

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail > 0 and 1 or 0)
