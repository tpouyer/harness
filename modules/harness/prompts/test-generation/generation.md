## Generate Tests

Now generate test cases that:

1. **Cover all acceptance criteria** from Jira
2. **Test the modified code** appropriately
3. **Follow project conventions** for test structure
4. **Include edge cases** where relevant
5. **Classify every test** as `local` (unit) or `functional` (requires aap-dev)

For each test, provide:
- `file_path` — path relative to the destination repo (local project or functional test repo)
- `test_name` — descriptive name
- `test_type` — `unit` or `functional`
- `repo` — `local` (unit tests, current project) or `functional` (functional test repo, requires aap-dev)
- `requires_aap` — `true` only when `repo` is `functional`
- `source_requirement` — which acceptance criterion this test covers
- `code` — complete, runnable test code

Respond with a JSON object:
```json
{
  "tests": [
    {
      "file_path": "tests/test_example.py",
      "test_name": "test_feature_behaves_correctly",
      "test_type": "unit",
      "repo": "local",
      "requires_aap": false,
      "source_requirement": "AC-1: Feature should do X when given Y",
      "code": "def test_feature_behaves_correctly():\n    ...",
      "confidence": 0.9
    },
    {
      "file_path": "tests/functional/test_example_aap.py",
      "test_name": "test_feature_deployed_to_aap",
      "test_type": "functional",
      "repo": "functional",
      "requires_aap": true,
      "source_requirement": "AC-2: Feature should be accessible via AAP API",
      "code": "def test_feature_deployed_to_aap(aap_client):\n    ...",
      "confidence": 0.85
    }
  ],
  "summary": "Generated N tests (X unit, Y functional) covering M acceptance criteria",
  "coverage_notes": "Any gaps or concerns about test coverage"
}
```
