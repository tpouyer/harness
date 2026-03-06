Identify changes that could break consumers, deployments, or backwards compatibility.

## API Breaking Change Detection

AAP APIs are defined by OpenAPI 3.0.3 specifications. To detect breaking changes:

Step 1: Get baseline specs from the aap-openapi-specs repo:
  - Repo: ansible-automation-platform/aap-openapi-specs
  - Specs at repo root: gateway.json, eda.json, galaxy.json, galaxy-pulp.json, controller.json
  - Use aap_dev_download_specs to fetch current specs from a running AAP instance

Step 2: Get current specs from the running AAP instance with your code changes:
  - aap_dev_ensure_running (deploy with your code changes)
  - aap_dev_download_specs (fetch live specs from the running instance)

Step 3: Diff the baseline specs against the live specs. Check for:
  - Removed endpoints (breaking)
  - Removed or renamed fields in response schemas (breaking)
  - Changed field types (breaking)
  - New required request parameters (breaking)
  - Changed authentication requirements (breaking)
  - Changed HTTP status codes (breaking)
  - Changed error response formats (potentially breaking)
  - New optional fields in responses (safe, additive)
  - New optional request parameters (safe, additive)

### OpenAPI Spec Endpoints (AAP 2.6)

| Component | Endpoint | Notes |
|-----------|----------|-------|
| Gateway | /api/gateway/v1/docs/schema/?format=json | Main entry point, ~1.1MB |
| EDA | /api/eda/v1/openapi.json | Event-driven automation, ~422KB |
| Hub (Galaxy) | /api/galaxy/v3/galaxy.json | Curated user-facing spec, ~47KB |
| Hub (Pulp) | /api/galaxy/v3/galaxy-pulp.json | Full Pulp spec, ~3.2MB |
| Controller | External: developers.redhat.com | Not served by AAP instance |

### API Discovery

Start with the API root to discover available services:
  curl -u admin:password http://localhost:PORT/api/

## Database / Schema Changes
- New migrations: are they reversible?
- Column removals or type changes on existing tables
- Index changes that could affect query performance
- Data migrations that modify existing records

## Configuration Changes
- New required environment variables or config keys
- Changed defaults that alter existing behavior
- Removed config options that consumers may depend on

## Interface Changes
- Modified public function/class signatures
- Changed event/message formats
- Modified CLI arguments or flags

## Cross-Team Notification

For each breaking change that affects consumers owned by other teams:
- Check AGENTS.md "Team Ownership" for each affected team
- Use jira_create_issue to notify each affected team
- Summary: "[Harness/compat] Breaking change in <component> affects <consumer>"
- Include: what changed, what breaks, migration path
- Link: "is caused by" back to this task

## Expected Output

Compatibility report in beads issue notes:
- api_diff (summary of OpenAPI spec changes: added/removed/modified endpoints)
- breaking_changes[] (type, location, description, severity, migration_path)
- deprecations[] (what, replacement, timeline)
- additive_changes[] (safe additions, for awareness)
- cross_team_issues[] (jira_key, team, description)
- migration_required: true/false

## Tools
- aap_dev_ensure_running (deploy AAP with code changes)
- aap_dev_download_specs (fetch live OpenAPI specs from running instance)
- jira_create_issue (for cross-team notifications)
- jira_add_comment
