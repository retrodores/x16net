ASM ?= 64tass
PYTHON ?= python3
PROG8C ?= prog8c
BUILD := build
.PHONY: all test check bindings examples clean package
all: $(BUILD)/x16net.bin bindings
$(BUILD)/x16net.bin: src/x16net.asm
	mkdir -p $(BUILD)
	$(ASM) -q -a -B -C -Wall -Werror -Wno-error=long-branch --nostart -o $@ --labels=$(BUILD)/x16net.labels $<
bindings:
	$(PYTHON) tools/generate_bindings.py --check
test: all
	$(PYTHON) t/test_binary.py
check: test examples
examples: all
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 examples/connect.p8
	$(PROG8C) -target cx16 -out $(BUILD) -srcdirs prog8 examples/abi_smoke.p8
package: check
	mkdir -p $(BUILD)/x16net-0.1.0
	cp $(BUILD)/x16net.bin $(BUILD)/x16net-0.1.0/
	cp -r prog8 include docs examples README.md LICENSE $(BUILD)/x16net-0.1.0/
	cd $(BUILD) && tar -czf x16net-0.1.0.tar.gz x16net-0.1.0
clean:
	rm -rf $(BUILD)
