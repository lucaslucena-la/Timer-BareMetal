# =============================================================
# Relógio Digital — RISC-V Bare Metal (QEMU virt)
# Timer via CLINT | UART via PLIC | Sem SO
# =============================================================

# ── Endereços base ────────────────────────────────────────────
.equ UART_BASE,    0x10000000
.equ PLIC_BASE,    0x0C000000
.equ MTIME,        0x0200BFF8  # contador livre do CLINT
.equ MTIMECMP,     0x02004000  # dispara interrupção quando MTIME >= MTIMECMP

# ── Offsets UART (NS16550) ────────────────────────────────────
.equ UART_RHR, 0   # leitura de byte recebido
.equ UART_THR, 0   # escrita de byte a transmitir
.equ UART_IER, 1   # habilita interrupções da UART
.equ UART_LSR, 5   # bit 5 = THRE (TX livre para enviar)
.equ UART_IRQ, 10  # IRQ da UART no PLIC

# ── Registradores PLIC ────────────────────────────────────────
.equ PLIC_PRIORITY,  (PLIC_BASE + 0x000000)
.equ PLIC_ENABLE,    (PLIC_BASE + 0x002000)
.equ PLIC_THRESHOLD, (PLIC_BASE + 0x200000)
.equ PLIC_CLAIM,     (PLIC_BASE + 0x200004)

# ── Timer: 10 MHz → 10_000_000 ciclos = 1 segundo ────────────
.equ INTERVAL, 10000000

# =============================================================
# .bss — dados não inicializados
# =============================================================
.section .bss

.space 4096
stack_top:              # pilha de 4 KB (cresce para baixo)

horas:    .word 0
minutos:  .word 0
segundos: .word 0

uart_buffer: .space 32  # acumula comando "T HH:MM:SS"
uart_index:  .word 0    # próxima posição livre no buffer

# =============================================================
# .text — código
# =============================================================
.section .text
.global _start

# -------------------------------------------------------------
# _start: inicialização e loop principal
# -------------------------------------------------------------
_start:
    la   sp, stack_top              # inicializa pilha

    la   t0, trap_handler
    csrw mtvec, t0                  # registra handler de interrupções

    jal  timer_set                  # agenda primeira interrupção de timer

    # habilita interrupções de timer (bit 7) e externas (bit 11)
    li   t0, (1<<7)|(1<<11)
    csrs mie, t0

    # UART: habilita interrupção de recepção
    li   t0, UART_BASE
    li   t1, 1
    sb   t1, UART_IER(t0)

    # PLIC: prioridade 1 para UART_IRQ
    li   t0, PLIC_PRIORITY
    li   t1, UART_IRQ
    slli t1, t1, 2                  # offset = IRQ * 4 bytes
    add  t0, t0, t1
    li   t1, 1
    sw   t1, 0(t0)

    # PLIC: habilita bit do UART_IRQ no registrador de enable
    li   t0, PLIC_ENABLE
    li   t1, (1<<UART_IRQ)
    sw   t1, 0(t0)

    # PLIC: threshold 0 → aceita qualquer prioridade >= 1
    li   t0, PLIC_THRESHOLD
    sw   zero, 0(t0)

    # habilita interrupções globais (mstatus.MIE = bit 3)
    li   t0, (1<<3)
    csrs mstatus, t0

main_loop:
    wfi                             # dorme até próxima interrupção
    j    main_loop

# -------------------------------------------------------------
# timer_set: agenda próximo disparo em MTIME + INTERVAL
# -------------------------------------------------------------
timer_set:
    li   t0, MTIME
    ld   t1, 0(t0)                  # t1 = tempo atual
    li   t2, INTERVAL
    add  t1, t1, t2                 # t1 = tempo atual + 1 s
    li   t0, MTIMECMP
    sd   t1, 0(t0)                  # escreve próximo disparo
    jr   ra

# -------------------------------------------------------------
# trap_handler: identifica a causa e despacha para o handler
# Salva apenas t0/t1 — os handlers salvam o que precisam
# -------------------------------------------------------------
.align 2
trap_handler:
    addi sp, sp, -16
    sd   t0, 0(sp)
    sd   t1, 8(sp)

    csrr t0, mcause
    li   t1, 0x8000000000000007     # Machine Timer Interrupt
    beq  t0, t1, call_timer
    li   t1, 0x800000000000000B     # Machine External Interrupt
    beq  t0, t1, call_external
    j    exit_trap

call_timer:
    jal  timer_interrupt
    j    exit_trap

call_external:
    jal  external_interrupt

exit_trap:
    ld   t0, 0(sp)
    ld   t1, 8(sp)
    addi sp, sp, 16
    mret

# -------------------------------------------------------------
# uart_putchar: envia byte em a0 pela UART (polling no TX)
# -------------------------------------------------------------
uart_putchar:
uart_putchar_wait:
    li   t0, UART_BASE
    lb   t1, UART_LSR(t0)           # lê Line Status Register
    andi t1, t1, 0x20               # isola THRE (bit 5)
    beqz t1, uart_putchar_wait      # TX ocupado: espera
    sb   a0, UART_THR(t0)           # TX livre: envia
    jr   ra

# -------------------------------------------------------------
# print_two_digits: imprime número 0–59 como dois dígitos ASCII
# a0 = número de entrada
# -------------------------------------------------------------
print_two_digits:
    addi sp, sp, -16
    sd   ra, 0(sp)
    sd   s4, 8(sp)

    mv   s4, a0                     # preserva valor original

    li   t1, 10
    div  t0, s4, t1                 # dezena = valor / 10
    addi a0, t0, '0'
    jal  uart_putchar

    li   t1, 10
    rem  t0, s4, t1                 # unidade = valor % 10
    addi a0, t0, '0'
    jal  uart_putchar

    ld   ra, 0(sp)
    ld   s4, 8(sp)
    addi sp, sp, 16
    jr   ra

# -------------------------------------------------------------
# timer_interrupt: incrementa o relógio e imprime HH:MM:SS
# Callee-saved usados: s0=horas, s1=minutos, s2=segundos, s4
# -------------------------------------------------------------
timer_interrupt:
    addi sp, sp, -40
    sd   ra,  0(sp)
    sd   s0,  8(sp)
    sd   s1, 16(sp)
    sd   s2, 24(sp)
    sd   s4, 32(sp)

    # carrega valores atuais
    la   t0, horas
    lw s0, 0(t0)
    la   t0, minutos
    lw s1, 0(t0)
    la   t0, segundos
    lw s2, 0(t0)

    # incrementa com cascata: segundos → minutos → horas
    addi s2, s2, 1
    li   t0, 60
    blt  s2, t0, tick_save
    li   s2, 0
    addi s1, s1, 1
    blt  s1, t0, tick_save
    li   s1, 0
    addi s0, s0, 1
    li   t0, 24
    blt  s0, t0, tick_save
    li   s0, 0                      # rollover 23:59:59 → 00:00:00

tick_save:
    la   t0, horas
    sw s0, 0(t0)
    la   t0, minutos
    sw s1, 0(t0)
    la   t0, segundos
    sw s2, 0(t0)

    jal  timer_set                  # reagenda próximo disparo

    # imprime "HH:MM:SS\r\n"
    mv   a0, s0
    jal print_two_digits
    li   a0, ':'
    jal uart_putchar
    mv   a0, s1
    jal print_two_digits
    li   a0, ':'
    jal uart_putchar
    mv   a0, s2
    jal print_two_digits
    li   a0, '\r'
    jal uart_putchar
    li   a0, '\n'
    jal uart_putchar

    ld   ra,  0(sp)
    ld   s0,  8(sp)
    ld   s1, 16(sp)
    ld   s2, 24(sp)
    ld   s4, 32(sp)
    addi sp, sp, 40
    jr   ra

# -------------------------------------------------------------
# external_interrupt: recebe char da UART e processa "T HH:MM:SS"
# Callee-saved: s0=IRQ id, s1=&uart_index, s2=índice, s3=&buffer
# -------------------------------------------------------------
external_interrupt:
    addi sp, sp, -40
    sd   ra,  0(sp)
    sd   s0,  8(sp)
    sd   s1, 16(sp)
    sd   s2, 24(sp)
    sd   s3, 32(sp)

    # PLIC Claim: obtém IRQ pendente e trava o PLIC para ele
    li   t0, PLIC_CLAIM
    lw   s0, 0(t0)
    li   t1, UART_IRQ
    bne  s0, t1, ext_done           # não é UART: ignora

    # lê o byte recebido
    li   t0, UART_BASE
    lb   t1, UART_RHR(t0)

    la   s1, uart_index
    lw   s2, 0(s1)
    la   s3, uart_buffer

    # '\n' ou '\r' → interpreta comando acumulado
    li   t0, '\n'
    beq t1, t0, ext_parse
    li   t0, '\r'
    beq t1, t0, ext_parse

    # acumula char no buffer (máx 31 chars)
    li   t0, 31
    bge  s2, t0, ext_done
    add  t0, s3, s2
    sb   t1, 0(t0)
    addi s2, s2, 1
    sw   s2, 0(s1)
    j    ext_done

ext_parse:
    # formato: "T HH:MM:SS" — mínimo 10 chars, começa com 'T'
    li   t0, 10
    blt s2, t0, ext_reset
    lb   t0, 0(s3)
    li t1, 'T'
    bne t0, t1, ext_reset

    # extrai HH (posições 2-3)
    lb   t0, 2(s3)
    addi t0, t0, -'0'
    li t2, 10
    mul t0, t0, t2
    lb   t1, 3(s3)
    addi t1, t1, -'0'
    add t0, t0, t1
    li   t1, 24
    bge t0, t1, ext_reset
    mv   t2, t0                     # t2 = horas válidas

    # extrai MM (posições 5-6)
    lb   t0, 5(s3)
    addi t0, t0, -'0'
    li a1, 10
    mul t0, t0, a1
    lb   a0, 6(s3)
    addi a0, a0, -'0'
    add t0, t0, a0
    li   a0, 60
    bge t0, a0, ext_reset
    mv   a1, t0                     # a1 = minutos válidos

    # extrai SS (posições 8-9)
    lb   t0, 8(s3)
    addi t0, t0, -'0'
    li a2, 10
    mul t0, t0, a2
    lb   a2, 9(s3)
    addi a2, a2, -'0'
    add t0, t0, a2
    li   a2, 60
    bge t0, a2, ext_reset

    # atualiza relógio
    la   a2, horas
    sw t2, 0(a2)
    la   a2, minutos
    sw a1, 0(a2)
    la   a2, segundos
    sw t0, 0(a2)

ext_reset:
    sw   zero, 0(s1)                # zera índice do buffer

ext_done:
    # PLIC Complete: libera o PLIC para nova interrupção desse IRQ
    li   t0, PLIC_CLAIM
    sw   s0, 0(t0)

    ld   ra,  0(sp)
    ld   s0,  8(sp)
    ld   s1, 16(sp)
    ld   s2, 24(sp)
    ld   s3, 32(sp)
    addi sp, sp, 40
    jr   ra