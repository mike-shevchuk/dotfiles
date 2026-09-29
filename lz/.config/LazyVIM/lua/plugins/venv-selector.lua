-- Вибір Python venv для pyright/ruff. Головна причина: у rescue-serverless
-- venv лежить глибоко (backend/src/lambdas/api/fast/.venv) і без явного вибору
-- pyright червонить усі імпорти (boto3/fastapi/pydantic) як "not found".
-- :VenvSelect → пікер знайдених venv-ів; вибір оновлює python-шлях у LSP на льоту.
-- regexp-гілка: шукає .venv у cwd/предках + pyenv/poetry/hatch; кешує вибір per-cwd.
return {
  "linux-cultist/venv-selector.nvim",
  branch = "regexp",
  dependencies = {
    "neovim/nvim-lspconfig",
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  ft = "python",
  -- cmd-тригери: виклик із палітри працює в будь-якому буфері, не лише .py
  -- VenvSelectCached існує лише при cached_venv_automatic_activation=false;
  -- дефолт (true) і так активує кешований venv сам → команда не потрібна.
  cmd = { "VenvSelect" },
  keys = {
    { "<leader>vs", "<cmd>VenvSelect<cr>", desc = "Python: select venv", mode = "n" },
  },
  opts = {
    settings = {
      options = {
        -- показувати активний venv у повідомленні
        notify_user_on_venv_activation = true,
      },
    },
  },
}
