module uart_rx_tick (
    input  logic        clk,
    input  logic        rx_tick,
    input  logic        rx_start,
    input  logic        rst,
    input  logic        rx,
    input  logic [3:0]  length,
    input  logic        parity_type,
    input  logic        parity_en,
    input  logic        stop2,
    output logic [7:0]  rx_out,
    output logic        rx_done,
    output logic        rx_error
);

    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP1,
        RX_STOP2,
        RX_DONE
    } rx_state_e;

    rx_state_e state_q, state_d;
    logic       rx_meta;
    logic       rx_sync;
    logic [7:0] data_reg;
    logic [3:0] length_reg;
    logic       parity_type_reg;
    logic       parity_en_reg;
    logic       stop2_reg;
    logic       frame_error;
    logic [3:0] sample_count;
    logic [2:0] bit_index;

    function automatic logic [7:0] data_mask(input logic [3:0] word_length);
        case (word_length)
            4'd5:    data_mask = 8'h1f;
            4'd6:    data_mask = 8'h3f;
            4'd7:    data_mask = 8'h7f;
            4'd8:    data_mask = 8'hff;
            default: data_mask = 8'h00;
        endcase
    endfunction

    function automatic logic expected_parity(
        input logic [7:0] data,
        input logic [3:0] word_length,
        input logic       odd_parity
    );
        logic data_xor;
        begin
            data_xor = ^(data & data_mask(word_length));
            expected_parity = odd_parity ? ~data_xor : data_xor;
        end
    endfunction

    // Synchronize the asynchronous serial input using the full-rate system
    // clock, not the much slower oversampling enable.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always_comb begin
        state_d = state_q;

        case (state_q)
            RX_IDLE: begin
                if (rx_start && !rx_sync &&
                    length >= 4'd5 && length <= 4'd8)
                    state_d = RX_START;
            end

            RX_START: begin
                if (sample_count == 4'd7)
                    state_d = rx_sync ? RX_IDLE : RX_DATA;
            end

            RX_DATA: begin
                if (sample_count == 4'd15 &&
                    bit_index == length_reg - 1'b1)
                    state_d = parity_en_reg ? RX_PARITY : RX_STOP1;
            end

            RX_PARITY: begin
                if (sample_count == 4'd15)
                    state_d = RX_STOP1;
            end

            RX_STOP1: begin
                if (sample_count == 4'd15)
                    state_d = stop2_reg ? RX_STOP2 : RX_DONE;
            end

            RX_STOP2: begin
                if (sample_count == 4'd15)
                    state_d = RX_DONE;
            end

            RX_DONE: state_d = RX_IDLE;
            default: state_d = RX_IDLE;
        endcase
    end

    // rx_tick enables the 16-times-baud sampling logic. All registers remain
    // in the clk domain, including the synchronizer above.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q         <= RX_IDLE;
            data_reg        <= 8'h00;
            length_reg      <= 4'd8;
            parity_type_reg <= 1'b0;
            parity_en_reg   <= 1'b0;
            stop2_reg       <= 1'b0;
            frame_error     <= 1'b0;
            sample_count    <= 4'd0;
            bit_index       <= 3'd0;
            rx_out          <= 8'h00;
            rx_done         <= 1'b0;
            rx_error        <= 1'b0;
        end else begin
            rx_done  <= 1'b0;
            rx_error <= 1'b0;

            if (rx_tick) begin
                state_q <= state_d;

                case (state_q)
                    RX_IDLE: begin
                        sample_count <= 4'd0;
                        bit_index    <= 3'd0;
                        if (rx_start && !rx_sync) begin
                            if (length >= 4'd5 && length <= 4'd8) begin
                                data_reg        <= 8'h00;
                                length_reg      <= length;
                                parity_type_reg <= parity_type;
                                parity_en_reg   <= parity_en;
                                stop2_reg       <= stop2;
                                frame_error     <= 1'b0;
                            end else begin
                                rx_done  <= 1'b1;
                                rx_error <= 1'b1;
                            end
                        end
                    end

                    RX_START: begin
                        if (sample_count == 4'd7)
                            sample_count <= 4'd0;
                        else
                            sample_count <= sample_count + 1'b1;
                    end

                    RX_DATA: begin
                        if (sample_count == 4'd15) begin
                            sample_count        <= 4'd0;
                            data_reg[bit_index] <= rx_sync;
                            if (bit_index == length_reg - 1'b1)
                                bit_index <= 3'd0;
                            else
                                bit_index <= bit_index + 1'b1;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end

                    RX_PARITY: begin
                        if (sample_count == 4'd15) begin
                            sample_count <= 4'd0;
                            if (rx_sync != expected_parity(data_reg, length_reg,
                                                           parity_type_reg))
                                frame_error <= 1'b1;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end

                    RX_STOP1: begin
                        if (sample_count == 4'd15) begin
                            sample_count <= 4'd0;
                            if (!rx_sync)
                                frame_error <= 1'b1;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end

                    RX_STOP2: begin
                        if (sample_count == 4'd15) begin
                            sample_count <= 4'd0;
                            if (!rx_sync)
                                frame_error <= 1'b1;
                        end else begin
                            sample_count <= sample_count + 1'b1;
                        end
                    end

                    RX_DONE: begin
                        rx_out   <= data_reg & data_mask(length_reg);
                        rx_done  <= 1'b1;
                        rx_error <= frame_error;
                    end

                    default: begin
                        sample_count <= 4'd0;
                        bit_index    <= 3'd0;
                    end
                endcase
            end
        end
    end

endmodule
