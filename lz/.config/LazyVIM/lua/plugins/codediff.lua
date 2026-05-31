-- codediff.nvim — VSCode-style two-tier (line + char) side-by-side diff.
-- Triggered by `prefix V` tmux popup via ~/dotfiles/tmux/scripts/git-compare.sh codediff.
-- Repo: https://github.com/esmuellert/codediff.nvim
return {
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    -- Pre-built binary downloaded on first use; no compiler required.
  },
}
