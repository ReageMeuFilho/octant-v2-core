.PHONY: build
build:
	forge build

.PHONY: unit
unit:
	forge test --no-match-path "*Integration*.sol"

.PHONY: integration
integration:
	forge test --fork-url $$INFURA_URL --match-path "*Integration*.sol"

.PHONY: test
test: unit integration
