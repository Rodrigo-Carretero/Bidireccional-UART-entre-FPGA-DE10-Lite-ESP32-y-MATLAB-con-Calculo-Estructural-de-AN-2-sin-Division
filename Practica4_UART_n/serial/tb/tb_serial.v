`timescale 1ns/1ps
// Banco de pruebas UART con BAUD=1,000,000 y CLK_FREQ=10,000,000
// -> 10 ciclos por bit para simular rapidamente.
module tb_serial;
    reg clk=0;
    always #50 clk=~clk;
    reg reset_n=0;
    reg rx=1;
    wire tx;
    integer errors=0;

    top_uart_de10lite #(.CLK_FREQ(10000000), .BAUD_RATE(1000000)) dut (
        .CLOCK_50(clk), .RESET_N(reset_n), .UART_RX(rx), .UART_TX(tx)
    );

    task send_byte(input [7:0] value);
        integer b;
        begin
            rx=0; repeat(10) @(posedge clk);
            for(b=0;b<8;b=b+1) begin
                rx=value[b]; repeat(10) @(posedge clk);
            end
            rx=1; repeat(10) @(posedge clk);
        end
    endtask

    task read_byte(output [7:0] value);
        integer b;
        begin
            value=0;
            wait(tx==0);
            repeat(15) @(posedge clk);
            for(b=0;b<8;b=b+1) begin
                value[b]=tx;
                repeat(10) @(posedge clk);
            end
            if(tx !== 1'b1) begin
                $display("ERROR: stop bit incorrecto"); errors=errors+1;
            end
            repeat(5) @(posedge clk);
        end
    endtask

    task test(input [7:0] base, input [8*40-1:0] digits,
              input integer digit_count, input [7:0] exp_status,
              input [31:0] exp_result);
        reg [7:0] r0, r1, r2, r3, r4;
        integer k;
        begin
            // Enviar a la vez que un receptor de testbench escucha TX.
            fork
                begin
                    send_byte(base);
                    for(k=digit_count-1;k>=0;k=k-1)
                        send_byte((digits >> (8*k)) & 8'hff);
                    send_byte(8'd10);
                end
                begin
                    read_byte(r0);
                    read_byte(r1);
                    read_byte(r2);
                    read_byte(r3);
                    read_byte(r4);
                end
            join
            if (r0 !== exp_status || {r4,r3,r2,r1} !== exp_result) begin
                $display("FAIL A=%d n=%s status=%d resultado=%h expected=%h",
                         base,digits,r0,{r4,r3,r2,r1},exp_result);
                errors=errors+1;
            end else
                $display("OK A=%d n=%s status=%d resultado=%d",
                         base,digits,r0,{r4,r3,r2,r1});
            repeat(100) @(posedge clk);
        end
    endtask

    initial begin
        #1200 reset_n=1;
        // La entrada n es un texto ASCII enviado despues de A.
        test(8'd4,"7",1,8'd0,32'd128);
        test(8'd4,"10",2,8'd0,32'd1024);
        test(8'd2,"40",2,8'd0,32'd1048576);
        test(8'd2,"63",2,8'd0,32'd3037000499);
        test(8'd2,"64",2,8'd1,32'd0);
        test(8'd255,"8",1,8'd0,32'd4228250625);
        test(8'd255,"9",1,8'd1,32'd0);
        test(8'd1,"999999999999",12,8'd0,32'd1);
        test(8'd0,"999999999999",12,8'd0,32'd0);
        test(8'd0,"0",1,8'd0,32'd1);
        test(8'd9,"7",1,8'd0,32'd2187);
        if(errors == 0) $display("PASSED: todas las pruebas");
        else $display("FAILED: %d errores",errors);
        $finish;
    end
    initial begin
        #100000000;
        $display("TIMEOUT DEL TESTBENCH");
        $finish;
    end
endmodule
