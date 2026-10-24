# Invocar junto con el Makefile original para conservar RTL_FILES e IVERILOG_FLAGS.
.RECIPEPREFIX := >
.PHONY: b9f-core-imem-build
b9f-core-imem-build:
> @mkdir -p "$(dir $(B9F_VVP))"
> $(IVERILOG) $(IVERILOG_FLAGS) -DTEST_ID=$(B9F_CASE_ID) -s tb_core_imem_integracion -o "$(B9F_VVP)" \
>   $(RTL_FILES) $(IMEM_SYNC_MODEL) "$(B9F_TB)"
