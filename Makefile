TEST_DIR     := ./cadence/tests
COVER_CODE   := contracts
COVER_OUT    := coverage.lcov
TEST_FILES   := $(shell find $(TEST_DIR) -name "*_test.cdc")

.PHONY: test
test:
	@echo "Running Cadence tests..."
	flow test --cover --covercode="$(COVER_CODE)" --coverprofile="$(COVER_OUT)" $(TEST_FILES)

.PHONY: ci
ci: test