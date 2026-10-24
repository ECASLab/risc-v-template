# Archivo adicional de Makefile: cargar junto al Makefile del core.
# Hereda RTL_FILES y modelos sincronicos sin modificar el proyecto.
.PHONY: act4-runner-build
act4-runner-build:
> @mkdir -p "$(dir $(ACT4_VVP))"
> $(IVERILOG) $(IVERILOG_FLAGS) -s tb_core_act4_generic -o "$(ACT4_VVP)" \
>   $(RTL_FILES) $(IMEM_SYNC_MODEL) $(DMEM_SYNC_MODEL) "$(ACT4_TB)"
