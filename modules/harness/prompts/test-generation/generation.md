## Generate Tests

Now generate test cases that:

1. **Cover all acceptance criteria** from Jira
2. **Test the modified code** appropriately
3. **Follow project conventions** for test structure
4. **Include edge cases** where relevant

For each test, provide:
- File path (where to save the test)
- Test name (descriptive)
- Test type (unit/integration/e2e)
- Source requirement (which AC it covers)
- Complete test code

Respond with a JSON object:
```json
{
  "tests": [
    {
      "file_path": "tests/test_example.py",
      "test_name": "test_feature_behaves_correctly",
      "test_type": "unit",
      "source_requirement": "AC-1: Feature should do X",
      "code": "def test_feature_behaves_correctly():\n    ...",
      "confidence": 0.9
    }
  ],
  "summary": "Generated N tests covering M acceptance criteria",
  "coverage_notes": "Any gaps or concerns about test coverage"
}
```
