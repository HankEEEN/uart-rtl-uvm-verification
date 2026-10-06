module uart_clk_gen_tick #(
    parameter int unsigned CLK_HZ = 50_000_000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic [16:0] baud,
    output logic        tx_tick,
    output logic        rx_tick
);

    // Fractional divider (phase accumulator). rx_tick is asserted for one clk
    // cycle at 16 times the selected baud. Its intervals differ by at most one
    // clk cycle, while its long-term average has no integer-divider drift.
    logic [31:0] phase_acc;
    logic [31:0] active_increment;
    logic [31:0] selected_increment;
    logic [32:0] phase_sum;
    logic [3:0]  oversample_count;

    // Preserve the original generator's programming contract. Unsupported
    // values select 9600 baud rather than becoming arbitrary rates.
    always_comb begin
        case (baud)
            17'd4800:   selected_increment = 32'd76_800;
            17'd9600:   selected_increment = 32'd153_600;
            17'd14400:  selected_increment = 32'd230_400;
            17'd19200:  selected_increment = 32'd307_200;
            17'd38400:  selected_increment = 32'd614_400;
            17'd57600:  selected_increment = 32'd921_600;
            17'd115200: selected_increment = 32'd1_843_200;
            17'd128000: selected_increment = 32'd2_048_000;
            default:    selected_increment = 32'd153_600;
        endcase
    end

    always_comb begin
        phase_sum = {1'b0, phase_acc} + {1'b0, active_increment};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            phase_acc        <= 32'd0;
            active_increment <= 32'd153_600;
            oversample_count <= 4'd0;
            tx_tick          <= 1'b0;
            rx_tick          <= 1'b0;
        end else begin
            tx_tick <= 1'b0;
            rx_tick <= 1'b0;

            // Restart cleanly when software changes the baud. This avoids a
            // shortened first interval and realigns TX to the RX tick stream.
            if (active_increment != selected_increment) begin
                phase_acc        <= 32'd0;
                active_increment <= selected_increment;
                oversample_count <= 4'd0;
            end else if (phase_sum >= CLK_HZ) begin
                phase_acc <= phase_sum - CLK_HZ;
                rx_tick   <= 1'b1;

                // TX advances exactly once for every sixteen RX ticks.
                if (oversample_count == 4'd15) begin
                    oversample_count <= 4'd0;
                    tx_tick          <= 1'b1;
                end else begin
                    oversample_count <= oversample_count + 1'b1;
                end
            end else begin
                phase_acc <= phase_sum[31:0];
            end
        end
    end

endmodule
