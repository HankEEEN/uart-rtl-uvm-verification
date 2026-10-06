`timescale 1ns/1ps

module uart_tick_smoke_tb;
    localparam int unsigned CLK_HZ = 50_000_000;

    logic        clk = 1'b0;
    logic        rst = 1'b1;
    logic        tx_start = 1'b0;
    logic        rx_start = 1'b0;
    logic [7:0]  tx_data = 8'h00;
    logic [16:0] baud = 17'd9600;
    logic [3:0]  length = 4'd8;
    logic        parity_type = 1'b0;
    logic        parity_en = 1'b0;
    logic        stop2 = 1'b0;
    logic        serial;
    logic        tx_done;
    logic        rx_done;
    logic        tx_err;
    logic        rx_err;
    logic [7:0]  rx_out;

    uart_top_tick dut (
        .clk        (clk),
        .rst        (rst),
        .tx_start   (tx_start),
        .rx_start   (rx_start),
        .tx_data    (tx_data),
        .baud       (baud),
        .length     (length),
        .parity_type(parity_type),
        .parity_en  (parity_en),
        .stop2      (stop2),
        .rx         (serial),
        .tx         (serial),
        .tx_done    (tx_done),
        .rx_done    (rx_done),
        .tx_err     (tx_err),
        .rx_err     (rx_err),
        .rx_out     (rx_out)
    );

    always #10 clk = ~clk;

    function automatic logic [7:0] mask_for(input logic [3:0] word_length);
        case (word_length)
            4'd5:    return 8'h1f;
            4'd6:    return 8'h3f;
            4'd7:    return 8'h7f;
            default: return 8'hff;
        endcase
    endfunction

    function automatic int unsigned effective_baud(
        input logic [16:0] selected_baud
    );
        case (selected_baud)
            17'd4800, 17'd9600, 17'd14400, 17'd19200,
            17'd38400, 17'd57600, 17'd115200, 17'd128000:
                return selected_baud;
            default: return 9600;
        endcase
    endfunction

    task automatic apply_reset;
        @(negedge clk);
        rst <= 1'b1;
        tx_start <= 1'b0;
        rx_start <= 1'b0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
    endtask

    task automatic run_frame(
        input logic [7:0]  data,
        input logic [16:0] selected_baud,
        input logic [3:0]  word_length,
        input logic        parity_enabled,
        input logic        odd_parity,
        input logic        two_stop_bits
    );
        int unsigned timeout_cycles;
        bit tx_seen;
        bit rx_seen;

        timeout_cycles = 20 * ((CLK_HZ + effective_baud(selected_baud) - 1) /
                               effective_baud(selected_baud)) + 2000;
        tx_seen = 1'b0;
        rx_seen = 1'b0;

        @(negedge clk);
        tx_data <= data;
        baud <= selected_baud;
        length <= word_length;
        parity_en <= parity_enabled;
        parity_type <= odd_parity;
        stop2 <= two_stop_bits;
        tx_start <= 1'b1;
        rx_start <= 1'b1;

        for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
            @(posedge clk);
            #1;
            if (tx_done) begin
                tx_seen = 1'b1;
                tx_start <= 1'b0;
            end
            if (rx_done) begin
                rx_seen = 1'b1;
                rx_start <= 1'b0;
                if (rx_out !== (data & mask_for(word_length)))
                    $fatal(1, "RX mismatch: baud=%0d length=%0d expected=%02h got=%02h",
                           selected_baud, word_length,
                           data & mask_for(word_length), rx_out);
                if (rx_err)
                    $fatal(1, "Unexpected RX error: baud=%0d data=%02h",
                           selected_baud, data);
            end
            if (tx_err)
                $fatal(1, "Unexpected TX error: baud=%0d data=%02h",
                       selected_baud, data);
            if (tx_seen && rx_seen)
                break;
        end

        if (!tx_seen || !rx_seen)
            $fatal(1, "Timeout: baud=%0d tx_done=%0b rx_done=%0b",
                   selected_baud, tx_seen, rx_seen);

        @(negedge clk);
        tx_start <= 1'b0;
        rx_start <= 1'b0;
        repeat (4) @(posedge clk);
    endtask

    initial begin
        apply_reset();

        run_frame(8'h00, 17'd4800,   4'd8, 1'b0, 1'b0, 1'b0);
        run_frame(8'hff, 17'd9600,   4'd8, 1'b1, 1'b0, 1'b0);
        run_frame(8'haa, 17'd14400,  4'd7, 1'b1, 1'b1, 1'b1);
        run_frame(8'h55, 17'd19200,  4'd6, 1'b0, 1'b0, 1'b1);
        run_frame(8'h81, 17'd38400,  4'd5, 1'b1, 1'b0, 1'b0);
        run_frame(8'h3c, 17'd57600,  4'd8, 1'b1, 1'b1, 1'b0);
        run_frame(8'ha5, 17'd115200, 4'd8, 1'b0, 1'b0, 1'b0);
        run_frame(8'h5a, 17'd128000, 4'd8, 1'b1, 1'b1, 1'b1);
        run_frame(8'hc3, 17'd12345,  4'd8, 1'b0, 1'b0, 1'b0);

        $display("UART tick-based loopback smoke test passed.");
        $finish;
    end
endmodule
