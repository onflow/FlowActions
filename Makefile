.PHONY: test
test:
	flow test --cover --covercode="contracts" --coverprofile="coverage.lcov" ./cadence/tests/*_test.cdc

.PHONY: lint
lint:
	@output=$$(flow cadence lint $$(find cadence -name "*.cdc" -not -path "*/tests/transactions/attempt_copy_auto_balancer_config.cdc") 2>&1); \
	echo "$$output"; \
	if echo "$$output" | grep -qE "[1-9][0-9]* problems"; then \
		echo "Lint failed: problems found"; \
  		exit 1; \
	fi

.PHONY: ci
ci: test