# jira-create-issue
<!-- receta: la secuencia que FUNCIONO. Guardada 2026-09-24 -->

Crear un issue en Jira por MCP (probado 2026-09-24)

1. `memory.sh search jira cloudId` — si ya está, sáltate el paso 2.
2. `mcp.sh describe atlassian.createJiraIssue` — nombres exactos de parámetros.
3. `mcp.sh call --write atlassian.createJiraIssue projectKey=ABC issueTypeName=Story summary="..." description=@ticket.md`

Gotchas:
- La descripción va como fichero (`=@`), nunca inline.
- Si rechaza el tipo: `mcp.sh call atlassian.getJiraProjectIssueTypesMetadata projectKey=ABC`.
- Máximo 5 llamadas; si falla dos veces igual, para y reporta.
