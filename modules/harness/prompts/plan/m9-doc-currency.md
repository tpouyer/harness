Verify that documentation is still accurate after the code changes.

## Process

Step 1: Read AGENTS.md "Documentation" section to identify:
- Where docs live for this component (URLs, repo paths, owners)
- Which Jira project/component to file doc issues against
- The filing template and required fields

Step 2: Check each documentation source against the code changes:
- In-repo docs (README, API specs, architecture docs): fix directly if owned by this team
- External docs (user docs, runbooks, release notes): file a Jira issue against the owning team

Step 3: For each stale external doc found:
- Use jira_create_issue to file against the correct project/component (from AGENTS.md)
- Set labels: ["docs-update", "harness-generated"]
- Set summary: "[Harness/docs] <what needs updating>"
- Include: what changed in code, what doc currently says, what it should say
- Link: "is caused by" back to this task's Jira key
- Record: bd comment <this-task-id> "Filed <JIRA-KEY> against <team>"

Step 4: For in-repo docs owned by this team:
- Fix directly (update README, API spec, etc.)
- Include the fixes in the epic's PR

## Expected Output

Documentation report in beads issue notes:
- in_repo_fixes[] (file, what_changed, fixed: true)
- filed_issues[] (jira_key, target_team, summary, doc_location)
- docs_verified[] (files checked and confirmed accurate)
- no_action_needed[] (docs not affected by these changes)

## Tools
- jira_create_issue (for cross-team doc issues)
- jira_add_comment
