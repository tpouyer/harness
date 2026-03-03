## Alignment Comparison

Now compare the Jira intent with the code intent and provide:

### 1. Overall Alignment
Rate as: `aligned`, `partial`, or `divergent`

### 2. Alignment Score
Provide a score from 0-100 where:
- 90-100: Fully aligned, all ACs addressed
- 70-89: Mostly aligned, minor gaps
- 50-69: Partial alignment, significant gaps
- 0-49: Divergent, major misalignment

### 3. Intent Matches
List each Jira requirement and whether it's addressed in code:
- Strong match: Clearly implemented
- Moderate match: Partially implemented
- Weak match: Tangentially related
- No match: Not found in code

### 4. Missing Work (Jira-only)
Requirements from Jira not yet in code:
- List each with severity (high/medium/low)

### 5. Scope Creep (Code-only)
Work in code not from Jira:
- List each with assessment of whether it's:
  - Necessary (required for implementation)
  - Opportunistic (related improvement)
  - Off-track (unrelated work)

### 6. Recommendations
Specific actions to improve alignment:
- What to add
- What to remove
- What to clarify

Respond with a JSON object following this schema:
```json
{
  "overall_alignment": "aligned|partial|divergent",
  "score": 0-100,
  "summary": "Brief summary",
  "matches": [...],
  "jira_only": [...],
  "code_only": [...],
  "concerns": [...],
  "recommendations": [...]
}
```
