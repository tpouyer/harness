Analyze code changes for unnecessary complexity and dependency risk.

## Complexity Analysis

- Identify functions/methods whose cyclomatic complexity increased
- Flag deeply nested logic (>3 levels)
- Flag functions that grew beyond reasonable size
- Identify premature abstractions (wrapper/helper for single use)
- Identify over-engineering (configurability/extensibility not needed now)
- Compare before/after: did the change make things simpler or more complex?
- Could the same outcome be achieved with less code?

## Dependency Analysis

- List ALL new dependencies added (packages, libraries, modules)
- For each new dependency: is it justified? Could stdlib do this?
- Check for known CVEs in new dependencies
- Verify license compatibility (no GPL in Apache-licensed projects, etc.)
- Flag transitive dependency bloat
- Flag pinning issues (unpinned versions, overly broad version ranges)

## Expected Output

Complexity audit report in beads issue notes:
- complexity_changes[] (function, before_score, after_score, verdict)
- new_dependencies[] (name, version, justification, license, cve_check)
- unnecessary_abstractions[] (file, description, simplification)
- overall_complexity_verdict: simpler|neutral|more_complex
