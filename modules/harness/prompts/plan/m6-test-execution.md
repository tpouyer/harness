Run ALL tests (existing AND newly created) and verify they pass.

## Process

Step 1: Run unit tests locally using the project's test command.
Step 2: Deploy AAP with the code changes:
  - aap_dev_configure_sources with the feature branch
  - aap_dev_ensure_running
Step 3: Seed any required test data (aap_dev_seed_data).
Step 4: Run functional tests (aap_dev_test for each relevant component).
Step 5: Run any newly created functional tests from M2.

## Failure Handling

- If ANY test fails, flag this story as blocked
- Use aap_dev_logs to capture failure context
- Do NOT close this story with failing tests
- Report failures to the epic with specific details

## Expected Output

Test execution report in beads issue notes:
- total_tests, passed, failed, skipped
- unit_results[] (file, tests_run, passed, failed)
- functional_results[] (component, tests_run, passed, failed)
- failed_tests[] (name, error, file, line)
- flaky_tests[] (tests that passed on retry)
- environment (AAP version, instance_id)

## Tools
- aap_dev_configure_sources, aap_dev_ensure_running
- aap_dev_seed_data, aap_dev_test
- aap_dev_logs (for failure diagnosis)
