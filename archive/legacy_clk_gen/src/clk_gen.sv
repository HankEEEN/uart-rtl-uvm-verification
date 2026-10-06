module clk_gen(
    input clk, rst,
    input [16:0] baud,
    output tx_clk
);

    reg t_clk = 0;
    int tx_max = 0;
    int tx_count = 0;

    always @(posedge clk) begin
        if (rst) begin
            tx_max <= 0;
        end
        else begin
            case (baud)
                4800: tx_max <= 10416;  // 50mhz / 4800
                9600: tx_max <= 5208;
                14400: tx_max <= 3472;
                19200: tx_max <= 2604;
                38400: tx_max <= 1302;
                57600: tx_max <= 868;
                default: tx_max <= 5208;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            t_clk <= 1'b0;
            tx_count <= 0;
        end
        else begin
            if (tx_count < tx_max / 2) begin
                tx_count <= tx_count + 1;
            end
            else begin
                t_clk <= ~t_clk;
                tx_count <= 0;
            end
        end
    end

    assign tx_clk = t_clk;

endmodule

interface clk_if;
    logic clk, rst;
    logic [16:0] baud;
    logic tx_clk;
endinterface