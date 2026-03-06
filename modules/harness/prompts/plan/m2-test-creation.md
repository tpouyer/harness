Based on the test discovery report (M1), generate new tests to fill coverage gaps.

## Objectives

1. For each coverage gap, determine if a unit test or functional test is appropriate
2. Generate test code following project conventions (see AGENTS.md, SKILLS.md)
3. Unit tests go in the local repo
4. Functional tests go in the functional test repo via aap_dev_commit_func_tests
5. Every acceptance criterion from the epic hierarchy should map to at least one test

## Guidelines

- Match the test framework and style of existing tests
- Test one behavior per test case
- Include setup, action, and assertion phases
- Include both positive and negative test cases
- Classify every test as unit (repo: local) or functional (repo: functional)

## Functional Test Verification

For tests requiring AAP:
- Use aap_dev_ensure_running to deploy AAP
- Use aap_dev_seed_data if test data is needed
- Verify tests pass before committing

## Tools
- aap_dev_ensure_running, aap_dev_seed_data, aap_dev_test
- aap_dev_commit_func_tests (for functional tests)
- jira_fetch_context (for acceptance criteria)
