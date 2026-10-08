# Jira MCP retrieval and publishing

Read this reference when the task requires Jira access. Inspect the currently exposed schemas before calling tools; server availability and accepted inputs can change. `write-jira` is disabled by default for this workflow. Its configuration does not establish that write tools are available in the current session.

## Retrieve the issue and relevant evidence

1. Extract the issue key from the supplied `/browse/<issue_key>` URL. Use the authenticated `read-jira` tools to retrieve it rather than fetching the private Jira page as public web content.
2. Select explicit fields for the task. For triage, include the description, summary, status, labels, issue type, components, affected/fix versions, and the resolved custom triage fields. Include a bounded number of relevant comments; expand the evidence read if important context is missing.
3. Search narrowly for duplicates or prior fixes using the project, distinctive symptom, command, or component. Retrieve candidate descriptions before deciding they match. Paginate when necessary and disclose search limits; a single result page cannot establish that no duplicate exists.

Example search inputs, to adapt to the actual symptom and current schema:

```json
{
  "jql": "project = VAULT AND text ~ \"recover\" ORDER BY updated DESC",
  "fields": "summary,status,resolution,fixVersions",
  "limit": 10
}
```

Use `statusCategory != Done` for active-work searches when appropriate. Include resolved issues when checking duplicates or prior fixes so an existing resolution is not hidden.

## Resolve fields and workflow metadata

- Use `jira_get_project_fields` or `jira_search_fields` to map names such as `Team R&D`, `Source`, `Customer Severity (DD)`, and `Regression R&D` to field IDs. Read those fields on the target issue; absence from a filtered response is not proof that a field is empty.
- Use `jira_get_project_issue_types` and `jira_get_create_fields` for creation requirements. Use `jira_get_field_options` for relevant custom-field values and `jira_get_project_components` for components. Resolve version values through the available version metadata; do not create a `TBD` option or version to satisfy the template.
- Match options to the target project, issue type, and field context. Creation metadata does not prove an existing issue field is editable; inspect the write tool's contract and any edit metadata it exposes.
- Follow the process-linked triage requirements in `SKILL.md` even when Jira marks those fields optional for creation. Preserve unrelated labels and fields when updating; if an array is replaced wholesale, merge the intended changes with its current contents.
- For a requested assignment, use `jira_search_assignable_users` and resolve ambiguous matches. For a Jira issue relationship, discover its type and direction with `jira_get_link_types`; an OpenChamber session link is separate from a Jira relationship.
- For triage handoff, get available transitions with `jira_get_transitions` and identify the one whose destination is `Awaiting Prioritization`. Use the identifier required by the write schema. A current status name does not establish which transitions are available.

## Publish and verify

1. Discover the available `write-jira` operation and its current input schema. Submit Markdown only if the tool documents Markdown support/conversion; submit ADF only if it accepts ADF in the documented field. Use documented wiki markup or plain text where applicable. A string parameter alone does not establish Markdown support; do not serialize ADF into it without documented support.
2. Refresh the issue's relevant fields before replacing content or merging labels. Preserve substantive evidence from the report and subsequent comments, and submit only the intended changes. Keep commands and output separate and preserve line breaks during conversion.
3. Record the write result and read back the changed fields or returned comment. Compare saved content and structure; inspect rendered content when exposed. If rendering cannot be checked, say so without misrepresenting a confirmed write as a failure. If the write outcome is uncertain, reconcile the issue/comment through reads before retrying.
4. For triage, complete and verify description/metadata changes before transitioning. Read back the final status and report partial success if the transition fails. Do not repeat a successful content update merely because the transition failed.

If writes are unavailable, return the proposed content and metadata/status changes with an accurate not-applied status. The user can enable `write-jira` in OpenCode and resume. Do not replace the MCP workflow with `acli`, ZSH commands, or ad hoc credential handling.
