# MCP Dev Paths

## Config
- `.mcp.json` (project MCP server registrations)
- `.claude/settings.json` (team-shared)
- `.claude/settings.local.json` (personal, gitignored)
- `~/.claude.json` (global Claude Code MCP servers)

## MCP integration code
- Wherever this project keeps its source — adjust the glob below to match.
  <!-- configure your MCP source paths, e.g. src/services/mcp/, internal/mcp/, lib/mcp/ -->
- Hooks/handlers that dispatch MCP tool calls (project-specific location).

## Docs
- `dev-docs/` (MCP plans and verification notes)

## Useful scans
- `rg -n "mcp" <source-dir> dev-docs`   <!-- replace <source-dir> with this project's code root -->
- `rg -n "mcpServers" .mcp.json .claude/settings.json .claude/settings.local.json`
