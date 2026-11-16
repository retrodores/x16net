ASM ?= 64tass
PYTHON ?= python3
PROG8C ?= prog8c
BUILD := build
VERSION := $(shell cat VERSION)
.PHONY: all test check bindings examples network-program gopher-test-program gopher-display-program integration clean package
all: $(BUILD)/x16net.bin bindings
$(BUILD)/x16net.bin: src/x16net.asm
	mkdir -p $(BUILD)
	$(ASM) -q -a -B -C -Wall -Werror -Wno-error=long-branch --nostart -o $@ --labels=$(BUILD)/x16net.labels $<
bindings:
	$(PYTHON) tools/generate_bindings.py --check
test: all
	$(PYTHON) t/test_binary.py
check: test examples network-program gopher-test-program gopher-display-program
examples: all
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 examples/connect.p8
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 examples/abi_smoke.p8
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 examples/gopher.p8
gopher-test-program: all
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 -srcdirs examples t/gopher_test.p8
gopher-display-program: all
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 -srcdirs examples t/gopher_view_test.p8
network-program: all
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 t/network_test.p8
integration: network-program
	$(PYTHON) t/run_network.py
package: check
	mkdir -p $(BUILD)/x16net-$(VERSION)
	cp $(BUILD)/x16net.bin $(BUILD)/x16net-$(VERSION)/
	cp $(BUILD)/gopher.prg $(BUILD)/x16net-$(VERSION)/x16net-gopher.prg
	cp -r prog8 include docs examples README.md LICENSE $(BUILD)/x16net-$(VERSION)/
	cd $(BUILD) && tar -czf x16net-$(VERSION).tar.gz x16net-$(VERSION)
clean:
	rm -rf $(BUILD)
