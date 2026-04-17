module ultrasonic_core (
    input  wire clk,
    input  wire echo,
    output reg  trig,
    output reg [7:0] distance_cm,
    output reg valid
);
    localparam TRIG_PULSE = 1000;
    localparam WAIT_60MS  = 6_000_000;

    reg [31:0] cnt;
    reg [2:0] state;

    always @(posedge clk) begin
        case (state)
            0: begin trig<=1; cnt<=0; valid<=0; state<=1; end
            1: begin if(cnt>=TRIG_PULSE) begin trig<=0; cnt<=0; state<=2; end
                     else cnt<=cnt+1; end
            2: begin if(echo) begin cnt<=0; state<=3; end
                     else cnt<=cnt+1; end
            3: begin
                if(echo) cnt<=cnt+1;
                else begin
                    distance_cm <= cnt / 5800;
                    valid <= 1;
                    cnt <= 0;
                    state <= 4;
                end
            end
            4: begin if(cnt>=WAIT_60MS) begin cnt<=0; state<=0; end
                     else cnt<=cnt+1; end
        endcase
    end
endmodule