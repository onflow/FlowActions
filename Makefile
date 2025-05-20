.PHONY: test
test:
	flow test --cover --covercode="contracts" --coverprofile="coverage.lcov" ./cadence/tests/*_test.cdc

.PHONY: ci
ci: test