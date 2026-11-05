# Run bats unit tests. Specify TEST_FILE to run a specific test file.
#   make test
#   make test TEST_FILE=test/entrypoint_main.bats
test:
	./test/bin/start.sh $(TEST_FILE)

# Run all bats unit tests.
test-suite:
	./test/bin/start.sh

# Build the image from pdc/Dockerfile and run a real PDC/BDC on docker to verify it works.
smoke-test:
	./test/smoke/run.sh

.PHONY: test test-suite smoke-test
