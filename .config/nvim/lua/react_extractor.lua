local M = {}

-- ────────────────────────────── Filter sets ──────────────────────────────────

local HTML_ELEMENTS = {
  a=1,abbr=1,address=1,area=1,article=1,aside=1,audio=1,b=1,base=1,bdi=1,
  bdo=1,blockquote=1,body=1,br=1,button=1,canvas=1,caption=1,cite=1,code=1,
  col=1,colgroup=1,datalist=1,dd=1,del=1,details=1,dfn=1,dialog=1,div=1,
  dl=1,dt=1,em=1,embed=1,fieldset=1,figcaption=1,figure=1,footer=1,form=1,
  h1=1,h2=1,h3=1,h4=1,h5=1,h6=1,head=1,header=1,hgroup=1,hr=1,html=1,
  i=1,iframe=1,img=1,input=1,ins=1,kbd=1,label=1,legend=1,li=1,link=1,
  main=1,map=1,mark=1,menu=1,meta=1,meter=1,nav=1,noscript=1,object=1,
  ol=1,optgroup=1,option=1,output=1,p=1,picture=1,pre=1,progress=1,q=1,
  rp=1,rt=1,ruby=1,s=1,samp=1,script=1,section=1,select=1,slot=1,small=1,
  source=1,span=1,strong=1,sub=1,summary=1,sup=1,table=1,tbody=1,td=1,
  template=1,textarea=1,tfoot=1,th=1,thead=1,time=1,tr=1,track=1,u=1,
  ul=1,video=1,wbr=1,
  -- SVG
  circle=1,clipPath=1,defs=1,ellipse=1,feBlend=1,feColorMatrix=1,filter=1,
  g=1,image=1,line=1,linearGradient=1,marker=1,mask=1,path=1,pattern=1,
  polygon=1,polyline=1,radialGradient=1,rect=1,stop=1,svg=1,symbol=1,
  use=1,
}

local GLOBALS = {
  React=1,Component=1,PureComponent=1,Fragment=1,StrictMode=1,
  useState=1,useEffect=1,useCallback=1,useMemo=1,useRef=1,useContext=1,
  useReducer=1,useLayoutEffect=1,useImperativeHandle=1,useDebugValue=1,
  useId=1,useDeferredValue=1,useTransition=1,useSyncExternalStore=1,
  createContext=1,forwardRef=1,memo=1,createRef=1,cloneElement=1,
  createElement=1,isValidElement=1,Children=1,Suspense=1,lazy=1,
  -- JS globals
  console=1,window=1,document=1,navigator=1,location=1,history=1,
  Math=1,Date=1,JSON=1,Object=1,Array=1,String=1,Number=1,Boolean=1,
  Promise=1,Error=1,Map=1,Set=1,WeakMap=1,WeakSet=1,Symbol=1,BigInt=1,
  RegExp=1,Int8Array=1,Uint8Array=1,
  parseInt=1,parseFloat=1,isNaN=1,isFinite=1,
  encodeURIComponent=1,decodeURIComponent=1,encodeURI=1,decodeURI=1,
  setTimeout=1,setInterval=1,clearTimeout=1,clearInterval=1,
  requestAnimationFrame=1,cancelAnimationFrame=1,
  undefined=1,null=1,NaN=1,Infinity=1,
  process=1,module=1,exports=1,require=1,__dirname=1,__filename=1,
  globalThis=1,self=1,
}

local KEYWORDS = {
  ["break"]=1,["case"]=1,["catch"]=1,["class"]=1,["const"]=1,
  ["continue"]=1,["debugger"]=1,["default"]=1,["delete"]=1,["do"]=1,
  ["else"]=1,["export"]=1,["extends"]=1,["finally"]=1,["for"]=1,
  ["function"]=1,["if"]=1,["import"]=1,["in"]=1,["instanceof"]=1,
  ["let"]=1,["new"]=1,["of"]=1,["return"]=1,["static"]=1,
  ["super"]=1,["switch"]=1,["this"]=1,["throw"]=1,["try"]=1,
  ["typeof"]=1,["var"]=1,["void"]=1,["while"]=1,["with"]=1,["yield"]=1,
  ["abstract"]=1,["as"]=1,["async"]=1,["await"]=1,["declare"]=1,
  ["enum"]=1,["from"]=1,["global"]=1,["implements"]=1,["infer"]=1,
  ["interface"]=1,["is"]=1,["keyof"]=1,["namespace"]=1,["never"]=1,
  ["override"]=1,["package"]=1,["private"]=1,["protected"]=1,["public"]=1,
  ["readonly"]=1,["satisfies"]=1,["type"]=1,["unique"]=1,["asserts"]=1,
  ["any"]=1,["boolean"]=1,["number"]=1,["object"]=1,["string"]=1,
  ["symbol"]=1,["unknown"]=1,["bigint"]=1,
  ["true"]=1,["false"]=1,
  ["key"]=1,
}

-- ────────────────────────────── Utilities ────────────────────────────────────

local function strip_strings(text)
  local s = text
  s = s:gsub("`[^`]*`", "``")
  s = s:gsub('"[^"\n]*"', '""')
  s = s:gsub("'[^'\n]*'", "''")
  s = s:gsub("//[^\n]*", "")
  return s
end

-- Find `id` as a whole word in `line`, return start col (1-based) or nil.
local function find_id_in_line(line, id)
  local s = 1
  while s <= #line do
    local p = line:find(id, s, true)
    if not p then return nil end
    local before = p > 1 and line:sub(p - 1, p - 1) or " "
    local after  = line:sub(p + #id, p + #id)
    if not before:match("[a-zA-Z0-9_$]") and not after:match("[a-zA-Z0-9_$]") then
      return p
    end
    s = p + 1
  end
  return nil
end

-- ────────────────────────────── Type inference ───────────────────────────────

local function parse_hover_type(text)
  -- TypeScript hover: markdown ```typescript\n(modifier) name: TypeAnnotation\n```
  local inner = text:match("```[%w]*\n(.-)```") or text
  for _, line in ipairs(vim.split(inner, "\n")) do
    local trimmed = vim.trim(line)
    if #trimmed > 0 then
      -- "(parameter) name: Type" | "const name: Type" | "let name: Type" | "var name: Type"
      local typ = trimmed:match(":%s*(.+)$")
      if typ then
        typ = vim.trim(typ):gsub("`$", ""):gsub("%s*$", "")
        -- Skip if it looks like a TS type keyword used as a label, not a real type
        if #typ > 0 and not typ:match("^%s*$") then
          return typ
        end
      end
    end
  end
  return nil
end

local function get_lsp_type(bufnr, lnum, col)
  local params = {
    textDocument = { uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(bufnr)) },
    position     = { line = lnum - 1, character = col - 1 },
  }
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    local ok, result = pcall(client.request_sync, client, "textDocument/hover", params, 1500, bufnr)
    if ok and result and result.result and result.result.contents then
      local c = result.result.contents
      local text
      if type(c) == "string" then
        text = c
      elseif type(c) == "table" then
        text = c.value or (c[1] and c[1].value)
      end
      if text then
        return parse_hover_type(text)
      end
    end
  end
  return nil
end

local function infer_type_heuristic(name)
  if name == "children"    then return "React.ReactNode" end
  if name == "className"   then return "string" end
  if name == "style"       then return "React.CSSProperties" end
  if name == "ref"         then return "React.Ref<unknown>" end
  if name:match("^on[A-Z]") or name:match("^handle[A-Z]") then
    return "(...args: unknown[]) => void"
  end
  if name == "disabled" or name == "loading" or name == "checked"
    or name == "selected" or name == "required" or name == "readOnly"
    or name == "hidden"   or name == "open"    or name == "visible"
    or name:match("^is[A-Z]") or name:match("^has[A-Z]")
    or name:match("^can[A-Z]") or name:match("^show[A-Z]") then
    return "boolean"
  end
  if name:match("[Cc]ount$") or name:match("[Ii]ndex$") or name:match("[Ss]ize$")
    or name:match("[Ww]idth$") or name:match("[Hh]eight$") or name:match("Num$") then
    return "number"
  end
  if name:match("[Ll]abel$") or name:match("[Tt]itle$") or name:match("[Nn]ame$")
    or name:match("[Tt]ext$") or name:match("[Uu]rl$") or name:match("[Hh]ref$")
    or name:match("[Ss]rc$") or name:match("[Pp]laceholder$") or name:match("[Vv]alue$") then
    return "string"
  end
  if name:match("[Ll]ist$") or name:match("[Ii]tems$") or name:match("[Oo]ptions$")
    or name:match("[Ee]ntries$") or name:match("[Rr]ows$") then
    return "unknown[]"
  end
  return "unknown"
end

-- Try LSP first; fall back to name heuristic.
local function resolve_type(bufnr, s_line, e_line, lines, id)
  for i, line in ipairs(lines) do
    local col = find_id_in_line(line, id)
    if col then
      local lsp_type = get_lsp_type(bufnr, s_line + i - 1, col)
      if lsp_type then return lsp_type end
      break
    end
  end
  return infer_type_heuristic(id)
end

-- ────────────────────────────── Identifier detection ─────────────────────────

local function get_declarations(lines)
  local decl = {}
  for _, line in ipairs(lines) do
    for _, kw in ipairs({ "const", "let", "var" }) do
      -- simple: const/let/var id
      local id = line:match("%f[%w_$]" .. kw .. "%f[%W_$]%s+([a-zA-Z_$][a-zA-Z0-9_$]*)")
      if id and not KEYWORDS[id] then decl[id] = true end
      -- object destructure: const { a, b: c } =
      local obj = line:match("%f[%w_$]" .. kw .. "%f[%W_$]%s*{([^}]+)}")
      if obj then
        for d in obj:gmatch("([a-zA-Z_$][a-zA-Z0-9_$]*)") do
          if not KEYWORDS[d] then decl[d] = true end
        end
      end
      -- array destructure: const [a, b] =
      local arr = line:match("%f[%w_$]" .. kw .. "%f[%W_$]%s*%[([^%]]+)%]")
      if arr then
        for d in arr:gmatch("([a-zA-Z_$][a-zA-Z0-9_$]*)") do
          if not KEYWORDS[d] then decl[d] = true end
        end
      end
    end
    -- arrow function params: (a, b, { c }) =>
    for params_str in line:gmatch("%(([^)]*)%)%s*=>") do
      for d in params_str:gmatch("([a-zA-Z_$][a-zA-Z0-9_$]*)") do
        if not KEYWORDS[d] then decl[d] = true end
      end
    end
    -- single arrow param: x =>
    local sp = line:match("([a-zA-Z_$][a-zA-Z0-9_$]*)%s*=>")
    if sp and not KEYWORDS[sp] then decl[sp] = true end
  end
  return decl
end

local function get_used(lines)
  local definitely = {}
  local maybe      = {}
  local obj_keys   = {}

  local text = strip_strings(table.concat(lines, "\n"))

  -- Definitely external ─────────────────────────────────────────────────────

  -- ={id   JSX prop value
  for id in text:gmatch("=%s*{%s*([a-zA-Z_$][a-zA-Z0-9_$]*)") do
    definitely[id] = true
  end
  -- ={id.  object-member access as prop value
  for id in text:gmatch("=%s*{%s*([a-zA-Z_$][a-zA-Z0-9_$]*)%.") do
    definitely[id] = true
  end
  -- {id}   standalone JSX expression child
  for id in text:gmatch("{%s*([a-zA-Z_$][a-zA-Z0-9_$]*)%s*}") do
    definitely[id] = true
  end
  -- {id(   function call in JSX
  for id in text:gmatch("{%s*([a-zA-Z_$][a-zA-Z0-9_$]*)%(") do
    definitely[id] = true
  end
  -- logical / ternary: && id  || id  ? id
  for id in text:gmatch("[&|?]%s*([a-zA-Z_$][a-zA-Z0-9_$]*)") do
    definitely[id] = true
  end
  -- negation: !id
  for id in text:gmatch("![%s]*([a-zA-Z_$][a-zA-Z0-9_$]*)") do
    definitely[id] = true
  end
  -- spread: ...id
  for id in text:gmatch("%.%.%.([a-zA-Z_$][a-zA-Z0-9_$]*)") do
    definitely[id] = true
  end
  -- JSX component names: <Capitalized
  for id in text:gmatch("<([A-Z][a-zA-Z0-9_$]*)") do
    definitely[id] = true
  end
  -- identifier accessed as object root: {id. or (id. or ,id. or space+id.
  for id in text:gmatch("[{(,%s]([a-zA-Z_$][a-zA-Z0-9_$]*)%.") do
    maybe[id] = true  -- could still be declared locally
  end

  -- Maybe external (ambiguous — could be object literal key) ─────────────────
  for id in text:gmatch("{%s*([a-zA-Z_$][a-zA-Z0-9_$]*)") do
    maybe[id] = true
  end

  -- Object-literal keys ─────────────────────────────────────────────────────
  for id in text:gmatch("[{,]%s*([a-zA-Z_$][a-zA-Z0-9_$]*)%s*:") do
    obj_keys[id] = true
  end

  -- Merge: definitely ∪ (maybe − obj_keys) ──────────────────────────────────
  local used = {}
  for id in pairs(definitely) do used[id] = true end
  for id in pairs(maybe) do
    if not obj_keys[id] then used[id] = true end
  end
  return used
end

local function compute_props(bufnr, s_line, e_line, lines)
  local decl = get_declarations(lines)
  local used = get_used(lines)

  local props = {}
  for id in pairs(used) do
    if not decl[id]
      and not HTML_ELEMENTS[id]
      and not GLOBALS[id]
      and not KEYWORDS[id]
      and not id:match("^%d")
      and #id >= 2
    then
      local typ = resolve_type(bufnr, s_line, e_line, lines, id)
      props[#props + 1] = { name = id, type = typ }
    end
  end
  table.sort(props, function(a, b) return a.name < b.name end)
  return props
end

-- ────────────────────────────── Code generation ──────────────────────────────

local function min_indent(lines)
  local min = math.huge
  for _, l in ipairs(lines) do
    if l:match("%S") then
      local n = #(l:match("^(%s*)") or "")
      if n < min then min = n end
    end
  end
  return min == math.huge and 0 or min
end

local function build_component(name, props, body, default_export)
  local out = {}

  if #props > 0 then
    out[#out + 1] = "interface " .. name .. "Props {"
    for _, p in ipairs(props) do
      out[#out + 1] = "  " .. p.name .. ": " .. p.type .. ";"
    end
    out[#out + 1] = "}"
    out[#out + 1] = ""
  end

  local param
  if #props == 0 then
    param = ""
  elseif #props == 1 then
    param = "{ " .. props[1].name .. " }: " .. name .. "Props"
  else
    local names = {}
    for _, p in ipairs(props) do names[#names + 1] = p.name end
    param = "{\n  " .. table.concat(names, ",\n  ") .. "\n}: " .. name .. "Props"
  end

  local prefix = default_export and "export function " or "function "
  out[#out + 1] = prefix .. name .. "(" .. param .. ") {"
  out[#out + 1] = "  return ("

  local base = min_indent(body)
  for _, l in ipairs(body) do
    local stripped = #l > base and l:sub(base + 1) or ""
    out[#out + 1] = "    " .. stripped
  end

  out[#out + 1] = "  );"
  out[#out + 1] = "}"

  return out
end

local function build_usage(name, props, indent)
  if #props == 0 then
    return { indent .. "<" .. name .. " />" }
  end

  local parts = {}
  for _, p in ipairs(props) do
    parts[#parts + 1] = p.name .. "={" .. p.name .. "}"
  end

  local inline = indent .. "<" .. name .. " " .. table.concat(parts, " ") .. " />"
  if #inline <= 100 then return { inline } end

  local result = { indent .. "<" .. name }
  for _, part in ipairs(parts) do
    result[#result + 1] = indent .. "  " .. part
  end
  result[#result + 1] = indent .. "/>"
  return result
end

-- ────────────────────────────── Buffer navigation ────────────────────────────

local function is_component_declaration(line)
  return line:match("^%s*export%s+default%s+async%s+function%s+[A-Z]") ~= nil
    or line:match("^%s*export%s+default%s+function%s+[A-Z]") ~= nil
    or line:match("^%s*export%s+async%s+function%s+[A-Z]") ~= nil
    or line:match("^%s*export%s+function%s+[A-Z]") ~= nil
    or line:match("^%s*async%s+function%s+[A-Z]") ~= nil
    or line:match("^%s*function%s+[A-Z]") ~= nil
    or line:match("^%s*export%s+const%s+[A-Z][a-zA-Z0-9_]*%s*=") ~= nil
    or line:match("^%s*const%s+[A-Z][a-zA-Z0-9_]*%s*=") ~= nil
end

-- Returns the 1-based line number of the closing brace/end of the component
-- that encloses `s_line`.
local function find_enclosing_component_end(bufnr, s_line)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local all   = vim.api.nvim_buf_get_lines(bufnr, 0, total, false)

  -- Search backwards for component start
  local comp_start = 1
  for i = s_line, 1, -1 do
    if is_component_declaration(all[i]) then
      comp_start = i
      break
    end
  end

  -- Track brace depth from comp_start to find matching }
  local depth      = 0
  local found_open = false
  for i = comp_start, total do
    local clean = strip_strings(all[i])
    for ch in clean:gmatch(".") do
      if ch == "{" then
        depth      = depth + 1
        found_open = true
      elseif ch == "}" and found_open then
        depth = depth - 1
        if depth == 0 then return i end
      end
    end
  end
  return total
end

local function find_last_import_line(bufnr)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, total, false)
  local last = 0
  for i, l in ipairs(lines) do
    if l:match("^import%s") or l:match("^from%s") then last = i end
  end
  return last
end

-- ────────────────────────────── Core extraction ──────────────────────────────

-- opts.new_file = false  → same-file, below parent component
-- opts.new_file = true   → write ComponentName.tsx, add import
local function do_extract(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local s_pos = vim.fn.getpos("'<")
  local e_pos = vim.fn.getpos("'>")
  local s_line, e_line = s_pos[2], e_pos[2]

  if s_line == 0 or e_line == 0 then
    vim.notify("[react-extractor] No visual selection — select TSX in Visual mode first", vim.log.levels.WARN)
    return
  end

  local body = vim.api.nvim_buf_get_lines(bufnr, s_line - 1, e_line, false)
  if #body == 0 then
    vim.notify("[react-extractor] Empty selection", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "New component name: " }, function(raw)
    if not raw or raw:match("^%s*$") then return end

    local name = vim.trim(raw):gsub("^%l", string.upper)

    -- Notify that we might take a moment (LSP calls can be slow)
    vim.notify("[react-extractor] Resolving prop types…", vim.log.levels.INFO)

    local props  = compute_props(bufnr, s_line, e_line, body)
    local indent = body[1]:match("^(%s*)") or ""
    local usage  = build_usage(name, props, indent)

    if opts.new_file then
      -- ── New-file extraction ────────────────────────────────────────────────
      local buf_path  = vim.api.nvim_buf_get_name(bufnr)
      local dir       = buf_path:match("^(.*)/[^/]*$") or "."
      local new_path  = dir .. "/" .. name .. ".tsx"

      local comp_lines = build_component(name, props, body, true)

      -- Prepend React import
      local file_content = vim.list_extend(
        { "import React from 'react';", "" },
        comp_lines
      )

      local write_ok = vim.fn.writefile(file_content, new_path)
      if write_ok ~= 0 then
        vim.notify("[react-extractor] Failed to write " .. new_path, vim.log.levels.ERROR)
        return
      end

      -- Replace selection first
      vim.api.nvim_buf_set_lines(bufnr, s_line - 1, e_line, false, usage)

      -- Add import statement after last import in original file
      local rel       = "./" .. name
      local imp_line  = 'import { ' .. name .. " } from '" .. rel .. "';"
      local last_imp  = find_last_import_line(bufnr)
      local ins_at    = last_imp > 0 and last_imp or 0
      vim.api.nvim_buf_set_lines(bufnr, ins_at, ins_at, false, { imp_line })

      vim.notify(
        ("[react-extractor] Created %s with %d prop%s"):format(
          new_path, #props, #props == 1 and "" or "s"
        ),
        vim.log.levels.INFO
      )
    else
      -- ── Same-file extraction ───────────────────────────────────────────────
      -- Find enclosing component end BEFORE mutating the buffer
      local enc_end = find_enclosing_component_end(bufnr, s_line)

      -- 1. Replace selection with usage
      vim.api.nvim_buf_set_lines(bufnr, s_line - 1, e_line, false, usage)

      -- 2. Adjust enc_end for the change in line count
      local delta   = #usage - (e_line - s_line + 1)
      local ins_at  = enc_end + delta  -- still 1-based

      -- 3. Insert blank line + component after enclosing component
      local comp_lines = build_component(name, props, body, false)
      local to_insert  = vim.list_extend({ "" }, comp_lines)
      vim.api.nvim_buf_set_lines(bufnr, ins_at, ins_at, false, to_insert)

      -- Move cursor to the new component definition (skip the blank line)
      pcall(vim.api.nvim_win_set_cursor, 0, { ins_at + 1, 0 })

      vim.notify(
        ("[react-extractor] Extracted <%s> with %d prop%s"):format(
          name, #props, #props == 1 and "" or "s"
        ),
        vim.log.levels.INFO
      )
    end
  end)
end

-- ────────────────────────────── Public API ───────────────────────────────────

function M.extract()      do_extract({ new_file = false }) end
function M.extract_file() do_extract({ new_file = true  }) end

function M.setup(opts)
  opts = opts or {}
  local keys = opts.keys or {}

  vim.api.nvim_create_user_command("ReactExtract", function()
    M.extract()
  end, { desc = "Extract React component (same file)" })

  vim.api.nvim_create_user_command("ReactExtractFile", function()
    M.extract_file()
  end, { desc = "Extract React component (new file)" })

  local k_same = keys.extract      or "<leader>ce"
  local k_file = keys.extract_file or "<leader>cef"

  -- Using :<C-u> ensures visual mode is exited before the command runs,
  -- which commits the '< and '> marks.
  vim.keymap.set("v", k_same, ":<C-u>ReactExtract<CR>",     { desc = "Extract React component (same file)", noremap = true, silent = true })
  vim.keymap.set("v", k_file, ":<C-u>ReactExtractFile<CR>", { desc = "Extract React component (new file)",  noremap = true, silent = true })
end

return M
