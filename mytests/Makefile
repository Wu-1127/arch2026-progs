# Optimization steps of the four programs; not part of the graded build.
# Run from the repository root:
#
#   make -f mytests/Makefile          build build/mytests/steps.elf and print
#                                     the step tables (needs make elfs first)
#   make -f mytests/Makefile tables   the same
#
# The ELF links the submission's objects (C at -O2, and the assembly) with
# the variants in mytests/ and the harness runtime of common/.

CROSS_COMPILE ?= riscv-none-elf-
RV_CC := $(CROSS_COMPILE)gcc
RV_AS := $(CROSS_COMPILE)as
RV_LD := $(CROSS_COMPILE)ld
EMU := third_party/rv32emu/build/rv32emu
B := build/mytests

CFLAGS := -march=rv32i_zicsr -mabi=ilp32 -g -ffreestanding -fno-pic \
          -fno-stack-protector -Wall -Wextra -Werror -iquote . -Icommon \
          -Itests -O2 -DOPT_NAME='"O2"'
ASFLAGS := -march=rv32i_zicsr -mabi=ilp32 -g
LDFLAGS := -T common/linker.ld --no-warn-rwx-segments

PROGS := gcd fixed bf16 rubik
SUBMISSION := $(foreach p,$(PROGS),build/$(p)/O2/impl.o build/$(p)/impl_asm.o)
RUNTIME := $(addprefix build/common/,start.o perf.o rt.o print.o)
STEPS := $(patsubst mytests/%.S,$(B)/%.o,$(wildcard mytests/*.S))

.PHONY: tables
tables: $(B)/steps.elf
	$(EMU) $< > $(B)/steps.log; s=$$?; \
	python3 mytests/steps.py $(B)/steps.log; exit $$s

$(B)/steps.elf: $(B)/steps.o $(STEPS) $(SUBMISSION) $(RUNTIME)
	$(RV_LD) $(LDFLAGS) -o $@ $^

$(B)/steps.o: mytests/steps.c
	@mkdir -p $(@D)
	$(RV_CC) $(CFLAGS) -c $< -o $@

$(B)/%.o: mytests/%.S
	@mkdir -p $(@D)
	$(RV_AS) $(ASFLAGS) $< -o $@

$(SUBMISSION) $(RUNTIME):
	$(MAKE) elfs
