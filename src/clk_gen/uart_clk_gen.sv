module uart_clk_gen (
    input  logic        clk,
    input  logic        rst,
    input  logic [16:0] baud,
    output logic        tx_clk,
    output logic        rx_clk
);

    // 50 MHz input clock. Each maximum is the approximate number of input
    // clock cycles in one complete output-clock period.
    int unsigned tx_max;
    int unsigned rx_max;
    int unsigned tx_count;
    int unsigned rx_count;

    // The only block that drives tx_max and rx_max.
    always @(posedge clk) begin
        if (rst) begin
            tx_max <= 0;  
            rx_max <= 0;   
        end else begin
            case (baud)
                4800: begin
                    tx_max <= 10416;
                    rx_max <= 652;
                end
                9600: begin
                    tx_max <= 5208;
                    rx_max <= 326;
                end
                14400: begin
                    tx_max <= 3472;
                    rx_max <= 218;
                end
                19200: begin
                    tx_max <= 2604;
                    rx_max <= 162;
                end
                38400: begin
                    tx_max <= 1302;
                    rx_max <= 82;
                end
                57600: begin
                    tx_max <= 868;
                    rx_max <= 54;
                end
                115200: begin
                    tx_max <= 434;
                    rx_max <= 28;
                end
                128000: begin
                    tx_max <= 392;
                    rx_max <= 24;
                end
                default: begin
                    tx_max <= 5208;     // Default: 9600 baud
                    rx_max <= 326;      // Default: 16 * 9600 Hz
                end
            endcase
        end
    end

    // A toggle is half of a TX clock period. Counting from zero requires
    // subtracting one to toggle after exactly tx_max / 2 input cycles.
    always @(posedge clk) begin
        if (rst) begin
            tx_count <= 0;
            tx_clk   <= 1'b0;
        end else if (tx_count >= tx_max / 2 - 1) begin
            tx_count <= 0;
            tx_clk   <= ~tx_clk;
        end else begin
            tx_count <= tx_count + 1;
        end
    end

    // RX runs at approximately 16 times the selected baud rate.
    always @(posedge clk) begin
        if (rst) begin
            rx_count <= 0;
            rx_clk   <= 1'b0;
        end else if (rx_count >= rx_max / 2 - 1) begin
            rx_count <= 0;
            rx_clk   <= ~rx_clk;
        end else begin
            rx_count <= rx_count + 1;
        end
    end

endmodule
