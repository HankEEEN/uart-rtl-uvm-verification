module uart_tx_tick (
    input  logic        clk,
    input  logic        tx_tick,
    input  logic        tx_start,
    input  logic        rst,
    input  logic [7:0]  tx_data,
    input  logic [3:0]  length,
    input  logic        parity_type,
    input  logic        parity_en,
    input  logic        stop2,
    output logic        tx,
    output logic        tx_done,
    output logic        tx_err
);

    typedef enum logic [2:0] {
        TX_IDLE,
        TX_DATA,
        TX_PARITY,
        TX_STOP1,
        TX_STOP2,
        TX_DONE
    } tx_state_e;

    tx_state_e state_q, state_d;
    logic [7:0] data_reg;
    logic [3:0] length_reg;
    logic       parity_en_reg;
    logic       parity_bit_reg;
    logic       stop2_reg;
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

    function automatic logic make_parity(
        input logic [7:0] data,
        input logic [3:0] word_length,
        input logic       odd_parity
    );
        logic data_xor;
        begin
            data_xor = ^(data & data_mask(word_length));
            make_parity = odd_parity ? ~data_xor : data_xor;
        end
    endfunction

    always_comb begin
        state_d = state_q;

        case (state_q)
            TX_IDLE: begin
                if (tx_start && length >= 4'd5 && length <= 4'd8)
                    state_d = TX_DATA;
            end

            TX_DATA: begin
                if (bit_index == length_reg - 1'b1)
                    state_d = parity_en_reg ? TX_PARITY : TX_STOP1;
            end

            TX_PARITY: state_d = TX_STOP1;
            TX_STOP1:  state_d = stop2_reg ? TX_STOP2 : TX_DONE;
            TX_STOP2:  state_d = TX_DONE;
            TX_DONE:   state_d = TX_IDLE;
            default:   state_d = TX_IDLE;
        endcase
    end

    // All state is clocked by clk. tx_tick is only a clock enable, so this
    // module introduces no generated-clock domain.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q         <= TX_IDLE;
            data_reg        <= 8'h00;
            length_reg      <= 4'd8;
            parity_en_reg   <= 1'b0;
            parity_bit_reg  <= 1'b0;
            stop2_reg       <= 1'b0;
            bit_index       <= 3'd0;
            tx              <= 1'b1;
            tx_done         <= 1'b0;
            tx_err          <= 1'b0;
        end else begin
            // Status signals are one-system-clock pulses.
            tx_done <= 1'b0;
            tx_err  <= 1'b0;

            if (tx_tick) begin
                state_q <= state_d;

                case (state_q)
                    TX_IDLE: begin
                        tx        <= 1'b1;
                        bit_index <= 3'd0;
                        if (tx_start) begin
                            if (length >= 4'd5 && length <= 4'd8) begin
                                data_reg       <= tx_data;
                                length_reg     <= length;
                                parity_en_reg  <= parity_en;
                                parity_bit_reg <= make_parity(tx_data, length,
                                                              parity_type);
                                stop2_reg      <= stop2;
                                tx             <= 1'b0;
                            end else begin
                                tx_err <= 1'b1;
                            end
                        end
                    end

                    TX_DATA: begin
                        tx <= data_reg[bit_index];
                        if (bit_index == length_reg - 1'b1)
                            bit_index <= 3'd0;
                        else
                            bit_index <= bit_index + 1'b1;
                    end

                    TX_PARITY: tx <= parity_bit_reg;
                    TX_STOP1, TX_STOP2: tx <= 1'b1;

                    TX_DONE: begin
                        tx      <= 1'b1;
                        tx_done <= 1'b1;
                    end

                    default: begin
                        tx        <= 1'b1;
                        bit_index <= 3'd0;
                    end
                endcase
            end
        end
    end

endmodule
