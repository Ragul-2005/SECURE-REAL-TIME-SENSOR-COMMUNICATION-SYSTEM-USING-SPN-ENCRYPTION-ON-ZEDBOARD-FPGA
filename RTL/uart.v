module uart_tx (
    input  wire clk,
    input  wire start,
    input  wire [7:0] data,
    output reg  tx,
    output reg  busy
);
    localparam BAUD_DIV = 10416; // 100MHz / 9600

    reg [13:0] baud_cnt;
    reg [3:0]  bit_cnt;
    reg [9:0]  shift;

    always @(posedge clk) begin
        if (!busy && start) begin
            shift <= {1'b1, data, 1'b0};
            busy  <= 1;
            baud_cnt <= 0;
            bit_cnt  <= 0;
        end
        else if (busy) begin
            if (baud_cnt == BAUD_DIV-1) begin
                baud_cnt <= 0;
                tx <= shift[0];
                shift <= {1'b1, shift[9:1]};
                bit_cnt <= bit_cnt + 1;
                if (bit_cnt == 9)
                    busy <= 0;
            end else
                baud_cnt <= baud_cnt + 1;
        end
        else
            tx <= 1'b1;
    end
endmodule