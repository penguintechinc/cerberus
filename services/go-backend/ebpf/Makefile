# Cerberus XDP - eBPF Makefile

CLANG ?= clang
LLC ?= llc
LLVM_STRIP ?= llvm-strip
BPFTOOL ?= bpftool

# Kernel headers
KERNEL_HEADERS ?= /usr/include

# Output directory
OUTPUT := ../bpf

# Source files
SOURCES := packet_steering.c

# Object files
OBJECTS := $(patsubst %.c,$(OUTPUT)/%.o,$(SOURCES))

# Clang flags for eBPF
CLANG_FLAGS := -O2 -g -Wall -Werror \
	-target bpf \
	-D__TARGET_ARCH_x86 \
	-I$(KERNEL_HEADERS) \
	-I/usr/include/bpf

.PHONY: all clean

all: $(OUTPUT) $(OBJECTS)

$(OUTPUT):
	mkdir -p $(OUTPUT)

$(OUTPUT)/%.o: %.c
	$(CLANG) $(CLANG_FLAGS) -c $< -o $@
	$(LLVM_STRIP) -g $@ 2>/dev/null || true

clean:
	rm -rf $(OUTPUT)

# Generate Go bindings using bpf2go (optional)
generate:
	go generate ./...

.PHONY: vmlinux
vmlinux:
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h
