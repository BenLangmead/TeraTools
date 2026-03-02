SDSL_SUBSET_DIR := sdsl_subset
USE_LOCAL_SUBSET := $(if $(wildcard $(SDSL_SUBSET_DIR)/Makefile),1,0)

all: lib/ include/
.PHONY: all clean sdsl-source

clean:
	-rm -r sdsl-lite lib include

ifeq ($(USE_LOCAL_SUBSET),1)
sdsl-source:
	@echo "Using local sdsl subset from $(SDSL_SUBSET_DIR)/"
else
sdsl-source: sdsl-lite/

sdsl-lite/:
	git clone https://github.com/simongog/sdsl-lite
endif

lib/ include/ &: sdsl-source
ifeq ($(USE_LOCAL_SUBSET),1)
	$(MAKE) -C $(SDSL_SUBSET_DIR) install PREFIX=..
else
	cd sdsl-lite && ./install.sh ..
endif

override MAKEFLAGS=""
.NOTPARALLEL:
