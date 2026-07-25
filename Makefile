# Copyright 2026 Daniel Tyukov
# SPDX-License-Identifier: Apache-2.0

SHELL   := /bin/bash
VENV    := .venv
PY      := $(VENV)/bin/python
PIP     := $(VENV)/bin/pip

RTL_DIR := rtl
TB_DIR  := tb
RESULTS := results
JOBS    ?= 8

RTL := \
	$(RTL_DIR)/vte_modes_pkg.sv \
	$(RTL_DIR)/vte_pkg.sv \
	$(RTL_DIR)/vte_mode_lut.sv \
	$(RTL_DIR)/vte_sync2.sv \
	$(RTL_DIR)/vte_cdc_fifo.sv \
	$(RTL_DIR)/vte_frame_sync.sv \
	$(RTL_DIR)/vte_timing_gen.sv \
	$(RTL_DIR)/vte_glyph_rom.sv \
	$(RTL_DIR)/vte_shader.sv \
	$(RTL_DIR)/vte_fetch_engine.sv \
	$(RTL_DIR)/vte_axil_regs.sv \
	$(RTL_DIR)/vga_text_engine.sv

.PHONY: all help venv lint lint-config test synth images font clean distclean

all: lint lint-config test synth ## lint both parameter sets, run every test, synthesise

help: ## list the targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

$(VENV)/bin/activate: requirements.txt
	python3 -m venv $(VENV)
	$(PIP) install --quiet --upgrade pip
	$(PIP) install --quiet -r requirements.txt
	@touch $(VENV)/bin/activate

venv: $(VENV)/bin/activate ## create the repo local Python environment

lint: ## Verilator -Wall over the RTL, no warnings allowed
	verilator --lint-only -Wall --top-module vga_text_engine $(RTL)
	@echo "verilator -Wall: clean"

# Also proves the RTL elaborates with narrow DACs and a different buffer depth.
lint-config: ## lint a second parameter set, RGB444 output and a deeper buffer
	verilator --lint-only -Wall --top-module vga_text_engine \
		-GRedW=4 -GGreenW=4 -GBlueW=4 -GFifoDepth=64 -GAxiAddrW=16 -GFetchAddrW=24 $(RTL)
	@echo "verilator -Wall with RGB444 and FifoDepth=64: clean"

test: venv ## build and run every testbench
	$(PY) scripts/run_tests.py -j $(JOBS)

synth: ## Yosys synthesis smoke test, writes docs/synth_report.txt
	@mkdir -p synth
	yosys -q -l synth/yosys.log synth/synth.ys
	$(PY) scripts/synth_report.py

images: venv ## regenerate every image in docs/img from simulation output
	$(PY) scripts/make_images.py

font: venv ## regenerate rtl/vte_glyph_rom.sv from scripts/font_data.py
	$(PY) scripts/gen_glyph_rom.py

clean: ## remove simulation and synthesis artefacts
	rm -rf $(RESULTS) synth/*.json synth/*.log synth/stat_*.txt

distclean: clean ## also remove the Python environment
	rm -rf $(VENV)
