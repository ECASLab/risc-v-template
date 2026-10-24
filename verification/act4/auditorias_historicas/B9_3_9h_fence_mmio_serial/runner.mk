# Usar junto al Makefile del nucleo, que define RTL_FILES/IMEM_SYNC_MODEL/IVERILOG_FLAGS.
.RECIPEPREFIX := >
.PHONY: b9h-fence-mmio-build
b9h-fence-mmio-build:
> @mkdir -p "$(dir $(B9H_VVP))"
> $(IVERILOG) $(IVERILOG_FLAGS) -DCASE_ID=$(B9H_CASE_ID) -s tb_b9h_fence_mmio -o "$(B9H_VVP)" \
>   $(RTL_FILES) $(IMEM_SYNC_MODEL) "$(B9H_TB)"
