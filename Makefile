.PHONY: build
build:
	forge build

.PHONY: unit
unit:
	forge test --no-match-path "*Integration*.sol"

.PHONY: integration
integration:
	forge test --match-path "*Integration*.sol"

.PHONY: test
test: unit integration

.PHONY: demo-converter-searcher
demo-converter-searcher: build
	poetry -C demos/glm-converter run python3 demos/glm-converter/flashbots-searcher.py
