test:
	./test/bin/start.sh $(TEST_FILE)

test-suite:
	./test/bin/start.sh --suite

.PHONY: test test-suite
