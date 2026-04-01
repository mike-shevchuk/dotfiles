# Global preferences

- I prefer using `justfile` for task automation and project commands. When setting up build/run/test workflows, use a `justfile` instead of Makefiles or npm scripts where possible.

# Todoist

- Fetch tasks via: `curl -s "https://api.todoist.com/api/v1/tasks" -H "Authorization: Bearer $TODOIST_TOKEN"`
- Token is in `~/dotfiles/.env` as `TODOIST_TOKEN`
- No MCP for Todoist — always use curl

# Zettelkasten / Notes

- MOC and notes go to `~/zettelkasten/claude_code/` (Obsidian style: YAML frontmatter, `[[wikilinks]]`, `#hashtags`)
- Project-specific notes: `~/zettelkasten/claude_code/rescue-serverless/` with subdirs (alerts/, architecture/, models/, signals/)
- Do NOT write to `~/zettelkasten/b2b/rescue/` (legacy manual notes)

# Private extensions

If `~/zetelekasten/claude_code/CLAUDE.md` exists, read and follow the instructions there as well. It contains private project context and knowledge.
