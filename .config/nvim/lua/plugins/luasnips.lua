-- lua/plugins/luasnip.lua
return {
  "L3MON4D3/LuaSnip",
  config = function()
    require("luasnip.loaders.from_vscode").load({
      paths = { vim.fn.stdpath("config") .. "/snippets" },
    })
  end,
}
