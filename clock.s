# Mapeamento de memória e constantes
# Endereços do CLINT (Para o Timer) e do PLIC (Para UART)
# CLint é um bloco de hardware 


#                 MEMORY MAP (QEMU virt)                   #
# UART base: 0x10000000                                    #
# PLIC base: 0x0C000000                                    #

.equ UART_BASE, 0x10000000 # base do UART
.equ PLIC_BASE, 0x0C000000 # base do PLIC
# ============================================================

#            registradores UART (NS1655)                   #
# MTIME: 0x0200BFF8 # contador de tempo real
# MTIMECMP: 0x02004000 # registrador de comparação para o timer
# Receive Holding Register  (RHR):  UART_BASE + 0          #
# Transmit Holding Register (THR):  UART_BASE + 0          #
# Interrupt Enable Register (IER):  UART_BASE + 1          #
# IRQ do UART: 10 (para o PLIC)                            #
# 
# REGISTRADORES E CONSTANTES DO TIMER E UART

.equ MTIME, 0x0200BFF8 # Registrador de contador de tempo real - incrementa automaticamente a cada ciclo do clock
.equ MTIMECMP, 0x02004000 # Registrador de comparação - quando MTIME >= MTIMECMP, gera interrupção de timer
.equ INTERVAL, 30000000 # Intervalo em ciclos de clock para gerar interrupção (aproximadamente 1 segundo em QEMU virt)

# REGISTRADORES DA UART (NS16550)
.equ UART_RHR, 0 # Receive Holding Register - lê dados recebidos (endereço relativo ao UART_BASE) - (endereço: UART_BASE + 0 = 0x10000000 )
.equ UART_THR, 0 # Transmit Holding Register - escreve dados para transmitir (mesmo endereço que RHR) - (endereço: UART_BASE + 0 = 0x10000000)
.equ UART_IER, 1 # Interrupt Enable Register - habilita/desabilita interrupções da UART (endereço relativo ao UART_BASE) - (endereço: UART_BASE + 1 = 0x10000001)
.equ UART_IRQ, 10 # Número da interrupção (IRQ) da UART no PLIC - usado para identificar qual dispositivo interrompeu - (endereço: PLIC_BASE + 10*4 = 0x0C00228)
# ============================================================

#               REGISTRADORES PLIC                         #
.equ PLIC_PRIORITY,    (PLIC_BASE + 0x0)       # Endereço base para configurar prioridade das interrupções - (0x0C000000)
.equ PLIC_ENABLE,      (PLIC_BASE + 0x2000)    # Registrador para habilitar/desabilitar interrupções - (0x0C002000)
.equ PLIC_THRESHOLD,   (PLIC_BASE + 0x200000)  # Registrador de limiar de prioridade mínima - (0x0C020000)
.equ PLIC_CLAIM,       (PLIC_BASE + 0x200004)  # Registrador para ler (claim) e completar (complete) interrupções - (0x0C020004)
# ============================================================

# ============================================================
# SEÇÃO .bss (Block Started by Symbol)
# Dados não inicializados - alocados em tempo de ligação
# ============================================================

.section .bss

# PILHA (Stack)
# - Usada para armazenar contexto durante interrupções
# - Cresce de cima para baixo (endereços decrescentes)
# - 4096 bytes (4KB) de espaço reservado
.space 4096
stack_top:                  # Rótulo que marca o topo da pilha

# ============================================================
# VARIÁVEIS GLOBAIS DO RELÓGIO (Clock)
# - Incrementadas pela rotina de timer_interrupt
# - Rastreiam tempo em formato HH:MM:SS (23:59:59)
# ============================================================

horas:      .word 0         # Registra horas (0-23) - 4 bytes
minutos:    .word 0         # Registra minutos (0-59) - 4 bytes
segundos:   .word 0         # Registra segundos (0-59) - 4 bytes

# ============================================================
# BUFFER UART e ÍNDICE
# - Buffer: armazena comando de entrada "T HH:MM:SS"
# - Índice: rastreia posição atual no buffer
# ============================================================

uart_buffer:  .space 32     # 32 bytes para armazenar comando
uart_index:   .word 0       # Índice de preenchimento do buffer

# ============================================================
# SEÇÃO .text (Código Executável)
# Contém as instruções do programa
# ============================================================

.section .text
.global _start              # Exporta _start como símbolo global


# ============================================================
#                       PONTO DE ENTRADA                      #
_start:
    # Inicialização da pilha 
    la sp, stack_top # sp (stack pointer) aponta para o topo da pilha

    # Configuração do trap handler
    la t0, trap_handler # Carrega endereço do da função trap_handler em t0

    # aponta mtvec para a nossa rotina de tratamento
    csrw mtvec, t0 # Escreve o endereço do trap_handler no registrador especial mtvec 

    # Configura o Primeiro disparo do Times
    jal timer_set
    # quando retornar do timer_set, o timer já estará configurado para disparar a primeira interrupção após 1 segundo

    # Habilita interrupções especíicas no MIE (Machine Interrupt Enable): 
    # Bit 7 (MTIE): É o interruptor da Interrupção de Timer. Ele avisa a CPU que ela deve ouvir o temporizador.
    # Bit 11 (MEIE): É o interruptor da Interrupção Externa. Ele avisa a CPU que ela deve ouvir o PLIC (e, consequentemente, a UART).
    li t0, (1 << 7) | (1 << 11) # Configura t0 para habilitar MTIE e MEIE, bit 7 e bit 11 respectivamente
    csrs mie, t0                # Escreve o valor em t0 no registrador mie para habilitar as interrupções de timer e externas

    # Configuração da UART e PLIC
    li t0, UART_BASE            # Carrega o endereço base do UART em t0 = 0x10000000
    li t1, 1                    # Valor para habilitar interrupção de recepção (bit 0 do IER)
    sb t1, UART_IER(t0)         # Escreve 1 no primeiro byte de UART_IER para habilitar interrupção de recepção = UART_BASE + 1 = 0x10000001;
    
    # Configura a prioridade da UART no PLIC
    li t0, PLIC_PRIORITY # Carrega o endereço base do PLIC_PRIORITY em t0 = 0x0C000000
    li t1, UART_IRQ             # t1 = 10
    slli t1, t1, 2              # t1 = 10 * 4 (cada prioridade tem 4 bytes)
    add t0, t0, t1              # t0  = PLIC_PRIORITY + (UART_IRQ * 4) - isso é feito para calcular o endereço específico da prioridade da UART no PLIC
    li t1, 1                    # Prioridade 1, quer dizer que a UART tem prioridade mínima para gerar interrupção
    sw t1, 0(t0)                # Escreve a prioridade da UART no endereço calculado

    # habilitar interrupções no PLIC
    li t0, PLIC_ENABLE          # Carrega o endereço base do PLIC_ENABLE em t0 = 0x0C002000
    li t1, (1 << UART_IRQ)      # t1 = 1 << 10, isso é feito para criar uma máscara que habilita apenas a interrupção da UART (bit 10)
    sw t1, 0(t0)                # Escreve a máscara no registrador de habilitação do PLIC para habilitar a interrupção da UART

    # Define limiar zero
    li t0, PLIC_THRESHOLD       # Carrega o endereço do PLIC_THRESHOLD em t0 = 0x0C020000
    sw zero, 0(t0)              # Escreve zero no registrador de limiar do PLIC para permitir que qualquer interrupção com prioridade maior que zero seja processada

    # habilita interrupções externas na cpu 
    # registrador mie:                                    
    # bit 11 = Machine External Interrupt Enable   
    li t0, (1 << 11)           # Configura t0 para habilitar MEIE, bit 11
    csrs mie, t0               # Escreve o valor de t0 no registrador mie para habilitar as interrupções externas (PLIC e, consequentemente, a UART)

    # Habilita interrupções globais na cpu
    # mstatus register:                                    
    # bit 3 = MIE global enable  
    li t0, (1 << 3)         # Configura t0 para habilitar MIE global, bit 3
    csrs mstatus, t0        # Escreve o valor de t0 no registrador mstatus para habilitar as interrupções globais na CPU
#

# ============================================================
#                       LOOP PRINCIPAL                      #

main_loop:
    wfi           # looping infinito sem fazer nada
    j main_loop

#

# ============================================================
# FUNÇÃO: timer_set
# Descrição: Define o próximo instante de disparo do timer
# - Lê o valor atual de MTIME (contador de tempo real)
# - Adiciona INTERVAL (período de 1 segundo)
# - Escreve o resultado em MTIMECMP para gerar interrupção

# ============================================================
#                       timer_set                            #

timer_set:

    li t0, MTIME                # Carrega o endereço de MTIME em t0
    ld t1, 0(t0)                # Lê o valor atual do contador de tempo em t1
    # t1 aqui representa o tempo atual em ciclos de clock

    li t2, INTERVAL             # Carrega o intervalo (30000000 ciclos) em t2
    add t1, t1, t2              # Calcula: t1 = tempo_atual + INTERVAL; 

    li t0, MTIMECMP             # Carrega o endereço do registrador MTIMECMP em t0
    sd t1, 0(t0)                # Escreve o novo valor em MTIMECMP (próximo disparo)

    jr ra                       # Retorna para o endereço de retorno (armazenado em ra)
#

# ============================================================
# Função: trap_handler
# Descrição: Trata interrupções e exceções
#
# Esta função é chamada automaticamente quando ocorre uma
# interrupção (timer ou UART) ou exceção na CPU.
#
# Fluxo:
# 1. Salva registradores usados (t0, t1) na pilha
# 2. Lê o registrador mcause para identificar a causa
# 3. Compara mcause com valores conhecidos de interrupções
# 4. Desvia para o handler apropriado (timer ou UART)
# 5. Restaura registradores da pilha
# 6. Retorna à instrução interrompida com mret

#                       TRAP HANDLER                         #

trap_handler:

    # 1. SALVAR CONTEXTO: Guarda registradores usados para não corromper o main_loop
    addi sp, sp, -16            # Abre espaço na pilha 
    sd t0, 0(sp)                # Salva t0
    sd t1, 8(sp)                # Salva t1

    # Identifica a causa da interrupção no registrador mcause
    csrr t0, mcause

    # Verifica se é Interrupção de Timer (Machine Timer Interrupt)
    li t1, 0x8000000000000007   # Machine Timer Interrupt
    beq t0, t1, call_timer

    # Verifica se é Interrupção Externa (Machine External Interrupt)
    li t1, 0x800000000000000B   # Machine External Interrupt
    beq t0, t1, call_external
    
    j exit_trap

    call_timer:
        # Chama o handler do timer
        jal timer_interrupt
        j exit_trap
    #

    call_external:
        # Chama o handler da UART   
        jal external_interrupt
        j exit_trap
    #

    exit_trap:  
        # RESTAURAR CONTEXTO: Devolve os valores originais aos registradores
        ld t0, 0(sp)                # Restaura t0 
        ld t1, 8(sp)                # Restaura t1
        addi sp, sp, 16             # Fecha o espaço na pilha 

        mret                        # Retorna ao ponto da interrupção
    #


# 

# TODO: IMPLEMENTAÇÕES RESTANTES                           #
# ============================================================

# 1. timer_interrupt:
#    - Incrementar segundos/minutos/horas (00:00:00 a 23:59:59)
#    - Chamar timer_set para o próximo segundo=
#    - Imprimir o tempo na UART e finalizar com mret

# 2. external_interrupt:
#    - PLIC Claim: Ler ID da interrupção em PLIC_CLAIM
#    - Se ID=10, ler caractere da UART e processar comando 'T HH:MM:SS
#    - PLIC Complete: Escrever ID de volta em PLIC_CLAIM
#    - Finalizar com mret