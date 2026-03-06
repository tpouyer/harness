Compare the intent identified from the code changes against the intent identified from the Jira issue hierarchy.

## Process

Step 1: Extract intent from the Jira hierarchy using jira_fetch_context.
- What is the Outcome/Initiative trying to achieve?
- What is the Epic's goal?
- What do the acceptance criteria require?
- What do linked handbook/design docs specify?

Step 2: Extract intent from the actual code changes.
- What does the code accomplish?
- What behaviors are implemented?
- What system components are affected?

Step 3: Compare and score alignment (0-100).
- Identify: matched intents, missing work (Jira-only), scope creep (code-only)
- Flag divergent work that doesn't trace back to any requirement

## Scoring

- 90-100: Fully aligned, all ACs addressed
- 70-89: Mostly aligned, minor gaps
- 50-69: Partial alignment, significant gaps
- 0-49: Divergent, major misalignment

## Expected Output

Alignment report in beads issue notes:
- overall_alignment: aligned|partial|divergent
- score: 0-100
- summary
- matches[] (jira_requirement, code_implementation, strength)
- jira_only[] (requirement, severity)
- code_only[] (implementation, assessment: necessary|opportunistic|off-track)
- concerns[]
- recommendations[]

## Tools
- jira_fetch_context (for full hierarchy context)
