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
	./demos/glm-converter/start-searcher-demo.sh
