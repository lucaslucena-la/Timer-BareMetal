# ============================================================
# Makefile — Relógio Digital RISC-V Bare Metal
# Alvo: QEMU virt (riscv64), sem sistema operacional
#
# Uso rápido:
#   make          → compila o projeto
#   make run      → compila e executa no QEMU (Ctrl+A X para sair)
#   make debug    → executa com GDB stub na porta 1234
#   make clean    → apaga arquivos gerados
# ============================================================

# ── Ferramentas ────────────────────────────────────────────────
# Ajuste o prefixo caso seu cross-compiler tenha nome diferente.
# Exemplos comuns:
#   riscv64-unknown-elf-   (toolchain genérico)
#   riscv64-linux-gnu-     (Ubuntu / Debian)
PREFIX  ?= riscv64-unknown-elf-
AS       = $(PREFIX)as
LD       = $(PREFIX)ld
OBJCOPY  = $(PREFIX)objcopy
OBJDUMP  = $(PREFIX)objdump

# ── Arquivos ───────────────────────────────────────────────────
SRC      = clock.s          # fonte assembly
OBJ      = clock.o          # objeto intermediário
ELF      = clock.elf        # binário ELF linkado
BIN      = clock.bin        # imagem binária pura (alternativa ao ELF)

# ── Flags ──────────────────────────────────────────────────────
ASFLAGS  = -march=rv64imac_zicsr  # ISA: inteiros 64-bit, mult/div, atômicos, comprimido
LDFLAGS  = -T clock.ld      # usa o linker script abaixo (gerado automaticamente)
LDFLAGS += -nostdlib        # sem biblioteca padrão (bare metal)

# ── QEMU ───────────────────────────────────────────────────────
QEMU     = qemu-system-riscv64
QFLAGS   = -machine virt            # placa virtual (mesma do QEMU virt)
QFLAGS  += -cpu rv64                # CPU genérica RISC-V 64-bit
QFLAGS  += -bios none               # sem firmware/BIOS
QFLAGS  += -nographic               # sem janela gráfica; usa terminal
QFLAGS  += -serial mon:stdio        # UART → stdin/stdout do terminal
QFLAGS  += -kernel $(ELF)           # carrega o ELF diretamente

# ── Regra padrão: compila tudo ──────────────────────────────────
.PHONY: all run debug clean disasm check-tools

all: check-tools $(ELF)

# ── Geração do linker script ───────────────────────────────────
# O QEMU virt carrega o kernel a partir do endereço 0x80000000.
# O linker script define essa origem e coloca .text, .bss em sequência.
clock.ld:
	@echo "Gerando linker script clock.ld..."
	@printf 'OUTPUT_ARCH(riscv)\nENTRY(_start)\nSECTIONS {\n  . = 0x80000000;\n  .text : { *(.text) }\n  .rodata : { *(.rodata) }\n  .bss : { *(.bss) }\n}\n' > clock.ld

# ── Montagem: .s → .o ──────────────────────────────────────────
$(OBJ): $(SRC)
	@echo "[AS]  $< → $@"
	$(AS) $(ASFLAGS) -o $@ $<

# ── Linkagem: .o → .elf ────────────────────────────────────────
$(ELF): $(OBJ) clock.ld
	@echo "[LD]  $< → $@"
	$(LD) $(LDFLAGS) -o $@ $(OBJ)
	@echo "Build OK: $(ELF)"

# ── Executa no QEMU ────────────────────────────────────────────
# Para sair do QEMU sem janela gráfica: pressione  Ctrl+A  e depois  X
run: all
	@echo "==================================================="
	@echo " Iniciando QEMU — para sair: Ctrl+A  depois  X"
	@echo " Para ajustar o relógio envie: T HH:MM:SS + Enter"
	@echo "==================================================="
	$(QEMU) $(QFLAGS)

# ── Executa com GDB stub (debug remoto) ────────────────────────
# Em outro terminal: riscv64-unknown-elf-gdb clock.elf
#   (gdb) target remote :1234
#   (gdb) layout asm
debug: all
	@echo "GDB stub ativo na porta 1234 — conecte com:"
	@echo "  $(PREFIX)gdb $(ELF)"
	@echo "  (gdb) target remote :1234"
	$(QEMU) $(QFLAGS) -s -S

# ── Disassembly (inspecionar o binário gerado) ─────────────────
disasm: $(ELF)
	$(OBJDUMP) -d -M no-aliases $(ELF)

# ── Verifica se as ferramentas estão instaladas ────────────────
check-tools:
	@command -v $(AS)   >/dev/null 2>&1 || \
		{ echo "ERRO: $(AS) não encontrado."; \
		  echo "Instale com: sudo apt install gcc-riscv64-unknown-elf"; \
		  exit 1; }
	@command -v $(QEMU) >/dev/null 2>&1 || \
		{ echo "ERRO: $(QEMU) não encontrado."; \
		  echo "Instale com: sudo apt install qemu-system-misc"; \
		  exit 1; }

# ── Limpeza ────────────────────────────────────────────────────
clean:
	@echo "Limpando arquivos gerados..."
	rm -f $(OBJ) $(ELF) $(BIN) clock.ld
	@echo "Pronto."