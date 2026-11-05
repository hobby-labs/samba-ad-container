test:
	./test/bin/start.sh $(TEST_FILE)

test-suite:
	./test/bin/start.sh --suite

# Build the image from pdc/Dockerfile and run a real PDC/BDC on docker to verify it works.
smoke-test:
	./test/smoke/run.sh

.PHONY: test test-suite smoke-test
