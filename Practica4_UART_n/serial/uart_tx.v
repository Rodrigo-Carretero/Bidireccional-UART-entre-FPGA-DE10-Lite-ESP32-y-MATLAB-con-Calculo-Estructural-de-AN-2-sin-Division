// Transmisor UART 8N1: 1 start, 8 datos LSB primero, 1 stop.
module uart_tx #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer BAUD_RATE = 9600
)(
    input wire clk,
    input wire reset,
    input wire tx_start,
    input wire [7:0] data_in,
    output reg tx,
    output reg busy
);
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam [1:0] IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;

    reg [1:0] state;
    reg [15:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] tx_buffer;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            tx <= 1'b1;
            busy <= 1'b0;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            tx_buffer <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    busy <= 1'b0;
                    clk_count <= 16'd0;
                    if (tx_start) begin
                        tx_buffer <= data_in;
                        busy <= 1'b1;
                        tx <= 1'b0;
                        state <= START;
                    end
                end
                START: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        bit_index <= 3'd0;
                        tx <= tx_buffer[0];
                        state <= DATA;
                    end else clk_count <= clk_count + 1'b1;
                end
                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        if (bit_index == 3'd7) begin
                            tx <= 1'b1;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            tx <= tx_buffer[bit_index + 1'b1];
                        end
                    end else clk_count <= clk_count + 1'b1;
                end
                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        tx <= 1'b1;
                        busy <= 1'b0;
                        state <= IDLE;
                    end else clk_count <= clk_count + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
