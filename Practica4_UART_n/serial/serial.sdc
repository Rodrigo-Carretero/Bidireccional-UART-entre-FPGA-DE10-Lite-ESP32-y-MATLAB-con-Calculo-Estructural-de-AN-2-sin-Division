# TimeQuest: clock del oscilador de la DE10-Lite = 50 MHz.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty
# UART y reset son entradas asincronas externas (sin tiempo de llegada fijo).
# Los caminos internos sincronizados SI son analizados por create_clock.
set_false_path -from [get_ports {UART_RX}]
set_false_path -from [get_ports {RESET_N}]
set_false_path -to [get_ports {UART_TX}]
