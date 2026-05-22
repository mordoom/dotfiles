return {
  name = "react-extractor",
  dir = vim.fn.stdpath("config"),
  ft = { "tsx", "jsx", "typescriptreact", "javascriptreact" },
  config = function()
    require("react_extractor").setup({
      keys = {
        extract      = "<leader>ce",   -- same file, component below parent
        extract_file = "<leader>cef",  -- new ComponentName.tsx + import
      },
    })
  end,
}
