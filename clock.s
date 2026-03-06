# Definiçãode Constantes e Seção de Dados

# Mapeamento de memória e constantes
# Endereços do CLINT (Para o Timer) e do PLIC (Para UART)

#                 MEMORY MAP (QEMU virt)                   #
# UART base: 0x10000000                                    #
# PLIC base: 0x0C000000                                    #

.equ UART_BASE, 0x10000000 # base do UART


#            registradores UART (NS1655)                   #
.equ MTIME, 0x0200BFF8 # contador de tempo real
.equ MTIMECMP, 0x02004000 # registrador de comparação para o timer
.equ INTERVAL, 10000000 # intervalo para o timer (ajustável)


#               REGISTRADORES PLIC                         #
.equ PLIC_BASE,        0x0C000000
.equ PLIC_PRIORITY,    (PLIC_BASE + 0x0)
.equ PLIC_ENABLE,      (PLIC_BASE + 0x2000)
.equ PLIC_THRESHOLD,   (PLIC_BASE + 0x200000)
.equ PLIC_CLAIM,       (PLIC_BASE + 0x200004)

#            registradores UART (NS1655)                   #
#                                                          #
# Receive Holding Register  (RHR):  UART_BASE + 0          #
# Transmit Holding Register (THR):  UART_BASE + 0          #
# Interrupt Enable Register (IER):  UART_BASE + 1          #

.equ UART_RHR,         0       # Receive Holding Register
.equ UART_THR,         0       # Transmit Holding Register
.equ UART_IER,         1       # Interrupt Enable Register

# ID DE INTERRUPCAI UART NO QEMU virt
.equ UART_IRQ,         10


.section .bss

# Pilha para salvar o contexto durante a interrupção
.space 4096 # 4KB de espaço para a pilha
stack_top:

# Variáveis do Relógio (Serão incrementadas pela rotina Timer)

horas: .word 0
minutos: .word 0
segundos: .word 0

# buffer para comando "T HH:MM:SS" (será preenchido pela rotina da UART)
uart_buffer: .space 32
uart_index: .word 0

# Inicializadao (Setup do Hardware)

.section .text
.global _start

_start:
    # Inicialização da pilha 
    la sp, stack_top

    # Instala o Trap Handler Geral
    la t0, trap_handler

    # aponta mtvec para a nossa rotina de tratamento
    csrw mtvec, t0

    # Configura o Primeiro disparo do Times
    jal timer_ set

    # Habilita interrupções especíicas no MIE (Machine Interrupt Enable)
    # Bit 7: MTIE Machine Timer Interrupt Enable
    # Bit 11: MEIE Machine External Interrupt Enable (para UART via PLIC)
    li t0, (1 << 7) | (1 << 11) # Habilita Timer e UART
    csrs mie, t0

    # Configuração da UART e PLIC
    li t0, UART_BASE
    li t1, 1
    sb t1, UART_IER(t0)

    # Configura a prioridade da UART no PLIC
    li t0, PLIC_PRIORITY
    li t1, UART_IRQ             # t1 = 10
    slli t1, t1, 2              # t1 = 10 * 4 (cada prioridade tem 4 bytes)
    add t0, t0, t1              # t0  = PLIC_PRIORITY + (UART_IRQ * 4)
    li t1, 1                    # Prioridade 1 (pode ser ajustada)
    sw t1, 0(t0)                # Escreve a prioridade da UART

    # habilitar interrupções no PLIC
    li t0, PLIC_ENABLE
    li t1, (1 << UART_IRQ)
    sw t1, 0(t0)

    # Define limiar zero
    li t0, PLIC_THRESHOLD
    sw zero, 0(t0)

    # habilita interrupções externas na cpu 
    # registrador mie:                                    
    # bit 11 = Machine External Interrupt Enable   
    li t0, (1 << 11)
    csrs mie, t0

    # Habilita interrupções globais na cpu
    # mstatus register:                                    
    # bit 3 = MIE global enable  
    li t0, (1 << 3)
    csrs mstatus, t0
#



#                       LOOP PRINCIPAL                      #

main_loop:
    wfi           # looping infinito sem fazer nada
    j main_loop


