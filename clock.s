# Definição e Inicialização 

# Mapeamento de memória e constantes
# Endereços do CLINT (Para o Timer) e do PLIC (Para UART)

.equ MTIME, 0x0200BFF8 # contador de tempo real
.equ MTIMECMP, 0x02004000 # registrador de comparação para o timer
.equ UART_BASE, 0x10000000 # base do UART
.equ PLIC_CLAIM, 0x0C200004 # registrador para identificar/limpar interrupções
.equ INTERVAL, 10000000 # intervalo para o timer (ajustável)

.section .bss
.align 4 # Alinhamento para 4 bytes 

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