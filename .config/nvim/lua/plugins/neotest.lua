return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "marilari88/neotest-vitest", -- Vitest adapter
    },
    opts = {
      adapters = {
        ["neotest-vitest"] = {
          -- Optional: specify the exact vitest command if using npm/pnpm
          -- vitestCommand = "npm run test" 
          vitestCommand = "pnpm test"
        },
      },
    },
  },
}
