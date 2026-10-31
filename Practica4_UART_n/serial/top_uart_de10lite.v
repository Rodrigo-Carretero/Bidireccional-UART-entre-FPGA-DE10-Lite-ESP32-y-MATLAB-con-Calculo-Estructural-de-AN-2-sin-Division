// DE10-Lite - Protocolo UART para calcular floor(A^(n/2)) en la FPGA.
// Entrada  : 1 byte binario A (0..255) + n en ASCII decimal + '\n'.
//             n es un entero NO NEGATIVO de cualquier cantidad de digitos.
// Salida   : 5 bytes: status + uint32 little-endian.
//             status 0=OK, 1=OVERFLOW, 2=ENTRADA_INVALIDA.
//             El valor de salida es floor(sqrt(A^n)).
//             0^0=1 por convenio computacional.
// Nota     : no hay divisor de tiempo de ejecucion para la potencia/raiz.
//             N interno se satura en 64: para A>=2, n>=64 siempre
//             produce resultado > 2^32-1; A=0/1 se calculan exactamente.
// UART     : 9600 8N1, sin hardware flow control, una solicitud a la vez.
module top_uart_de10lite #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BAUD_RATE = 9600
)(
    input  wire CLOCK_50,
    input  wire RESET_N,
    input  wire UART_RX,
    output wire UART_TX
);
    wire reset;
    assign reset = ~RESET_N;

    wire [7:0] rx_data;
    wire rx_done;
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) RX0 (
        .clk(CLOCK_50), .reset(reset), .rx(UART_RX),
        .data_out(rx_data), .data_valid(rx_done)
    );
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) TX0 (
        .clk(CLOCK_50), .reset(reset), .tx_start(tx_start),
        .data_in(tx_data), .tx(UART_TX), .busy(tx_busy)
    );

    localparam [3:0]
        S_WAIT_A        = 4'd0,
        S_READ_N        = 4'd1,
        S_MUL_START     = 4'd2,
        S_MUL_RUN       = 4'd3,
        S_MUL_FINISH    = 4'd4,
        S_ROOT_INIT     = 4'd5,
        S_ROOT_RUN      = 4'd6,
        S_SEND          = 4'd7,
        S_WAIT_TX_BUSY  = 4'd8,
        S_WAIT_TX_IDLE  = 4'd9;

    reg [3:0] state;
    reg [7:0] a_value;
    reg [6:0] n_sat;      // 0..63, o 64 si n >= 64
    reg seen_digit;
    reg invalid_digit;
    reg [6:0] exp_counter;

    // Multiplicacion secuencial de 64 x 8 bits por sumas y desplazamientos.
    // 72 bits detectan overflow sin perder bits altos del producto.
    reg [63:0] power_value;
    reg [71:0] mul_accum;
    reg [71:0] mul_term;
    reg [7:0] mul_byte;
    reg [2:0] mul_index;

    // Algoritmo restaurador de raiz cuadrada de 64 bits (32 ciclos).
    reg [63:0] radicand;
    reg [33:0] remainder;
    reg [31:0] root;
    reg [5:0] root_index;
    wire [33:0] rem_candidate;
    wire [33:0] root_trial;
    assign rem_candidate = {remainder[31:0], radicand[63:62]};
    assign root_trial = {root, 2'b01};

    reg [7:0] status;
    reg [31:0] result;
    reg [2:0] byte_index;

    // La comunicacion devuelve status y luego 4 bytes del resultado.
    always @(*) begin
        case (byte_index)
            3'd0: tx_data = status;
            3'd1: tx_data = result[7:0];
            3'd2: tx_data = result[15:8];
            3'd3: tx_data = result[23:16];
            3'd4: tx_data = result[31:24];
            default: tx_data = 8'd0;
        endcase
    end

    always @(posedge CLOCK_50 or posedge reset) begin
        if (reset) begin
            state <= S_WAIT_A;
            a_value <= 8'd0;
            n_sat <= 7'd0;
            seen_digit <= 1'b0;
            invalid_digit <= 1'b0;
            exp_counter <= 7'd0;
            power_value <= 64'd0;
            mul_accum <= 72'd0;
            mul_term <= 72'd0;
            mul_byte <= 8'd0;
            mul_index <= 3'd0;
            radicand <= 64'd0;
            remainder <= 34'd0;
            root <= 32'd0;
            root_index <= 6'd0;
            status <= 8'd0;
            result <= 32'd0;
            byte_index <= 3'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            case (state)
                // Byte inicial: A binario 0..255.
                S_WAIT_A: begin
                    if (rx_done) begin
                        a_value <= rx_data;
                        n_sat <= 7'd0;
                        seen_digit <= 1'b0;
                        invalid_digit <= 1'b0;
                        state <= S_READ_N;
                    end
                end

                // n decimal de longitud arbitraria, terminado en LF (10).
                // Solo almacenamos hasta 64 para evitar multiplicaciones
                // innecesarias; NO rechazamos un n con muchos digitos.
                S_READ_N: begin
                    if (rx_done) begin
                        if (rx_data == 8'd10) begin
                            status <= 8'd0;
                            result <= 32'd0;
                            byte_index <= 3'd0;
                            if (!seen_digit || invalid_digit) begin
                                status <= 8'd2;
                                state <= S_SEND;
                            end else if (a_value == 8'd0) begin
                                // 0^0 = 1; 0^n=0 para n>0.
                                if (n_sat == 7'd0) result <= 32'd1;
                                state <= S_SEND;
                            end else if (a_value == 8'd1 || n_sat == 7'd0) begin
                                result <= 32'd1;
                                state <= S_SEND;
                            end else if (n_sat == 7'd64) begin
                                status <= 8'd1;
                                state <= S_SEND;
                            end else begin
                                power_value <= 64'd1;
                                exp_counter <= 7'd0;
                                state <= S_MUL_START;
                            end
                        end else if (rx_data >= 8'd48 && rx_data <= 8'd57) begin
                            seen_digit <= 1'b1;
                            if (n_sat >= 7'd7) begin
                                n_sat <= 7'd64;
                            end else if (n_sat == 7'd6 && rx_data >= 8'd52) begin
                                n_sat <= 7'd64;
                            end else begin
                                // n = 10*n + digito. Solo desplazamientos/suma.
                                n_sat <= (n_sat << 3) + (n_sat << 1)
                                         + (rx_data - 8'd48);
                            end
                        end else if (rx_data == 8'd13) begin
                            // CR opcional: compatible con CRLF.
                        end else begin
                            invalid_digit <= 1'b1;
                        end
                    end
                end

                S_MUL_START: begin
                    mul_accum <= 72'd0;
                    mul_term <= {8'd0, power_value};
                    mul_byte <= a_value;
                    mul_index <= 3'd0;
                    state <= S_MUL_RUN;
                end

                S_MUL_RUN: begin
                    if (mul_byte[0])
                        mul_accum <= mul_accum + mul_term;
                    mul_term <= {mul_term[70:0], 1'b0};
                    mul_byte <= {1'b0, mul_byte[7:1]};
                    if (mul_index == 3'd7)
                        state <= S_MUL_FINISH;
                    else
                        mul_index <= mul_index + 1'b1;
                end

                S_MUL_FINISH: begin
                    if (mul_accum[71:64] != 8'd0) begin
                        status <= 8'd1;
                        result <= 32'd0;
                        byte_index <= 3'd0;
                        state <= S_SEND;
                    end else begin
                        power_value <= mul_accum[63:0];
                        if (exp_counter + 7'd1 == n_sat)
                            state <= S_ROOT_INIT;
                        else begin
                            exp_counter <= exp_counter + 1'b1;
                            state <= S_MUL_START;
                        end
                    end
                end

                S_ROOT_INIT: begin
                    radicand <= power_value;
                    remainder <= 34'd0;
                    root <= 32'd0;
                    root_index <= 6'd0;
                    state <= S_ROOT_RUN;
                end

                S_ROOT_RUN: begin
                    radicand <= {radicand[61:0], 2'b00};
                    if (rem_candidate >= root_trial) begin
                        remainder <= rem_candidate - root_trial;
                        root <= {root[30:0], 1'b1};
                        if (root_index == 6'd31)
                            result <= {root[30:0], 1'b1};
                    end else begin
                        remainder <= rem_candidate;
                        root <= {root[30:0], 1'b0};
                        if (root_index == 6'd31)
                            result <= {root[30:0], 1'b0};
                    end
                    if (root_index == 6'd31) begin
                        status <= 8'd0;
                        byte_index <= 3'd0;
                        state <= S_SEND;
                    end else
                        root_index <= root_index + 1'b1;
                end

                S_SEND: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        state <= S_WAIT_TX_BUSY;
                    end
                end
                S_WAIT_TX_BUSY: begin
                    if (tx_busy) state <= S_WAIT_TX_IDLE;
                end
                S_WAIT_TX_IDLE: begin
                    if (!tx_busy) begin
                        if (byte_index == 3'd4)
                            state <= S_WAIT_A;
                        else begin
                            byte_index <= byte_index + 1'b1;
                            state <= S_SEND;
                        end
                    end
                end
                default: state <= S_WAIT_A;
            endcase
        end
    end
endmodule
