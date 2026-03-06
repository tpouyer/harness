Review ALL code changes in this epic for security vulnerabilities.

## Checklist

Check for OWASP Top 10 and common security issues:
- Injection (SQL, command, LDAP, XSS)
- Broken authentication / authorization
- Sensitive data exposure (secrets in code, logs, error messages)
- Security misconfiguration
- Insecure deserialization
- Using components with known vulnerabilities
- Insufficient logging / monitoring
- Server-side request forgery (SSRF)
- Broken access control
- Cryptographic failures

## Cross-Team Findings

If a finding is in code owned by another team:
- Check AGENTS.md "Team Ownership" for the correct Jira project
- For critical/high: file in SECBUGS project (see SKILLS.md security process)
- For medium/low: file in the component's Jira project
- Use jira_create_issue with link_type "is caused by" back to this task
- Record in beads: bd comment <this-task-id> "Filed <KEY> against <team>"

## Expected Output

Security audit report in beads issue notes:
- findings[] (file, line, severity, category, description, remediation)
- clean_areas[] (areas reviewed with no issues)
- cross_team_issues[] (jira_key, team, finding_summary)
- overall_risk_assessment

## Tools
- jira_create_issue (for cross-team findings)
- jira_add_comment
