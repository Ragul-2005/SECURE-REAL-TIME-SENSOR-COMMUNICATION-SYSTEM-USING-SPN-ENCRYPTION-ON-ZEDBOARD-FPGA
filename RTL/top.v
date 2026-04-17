module secure_ultrasonic_system (
    input  wire clk,        // 100 MHz
    input  wire echo,
    output wire trig,
    output wire uart_tx
);
    // ---------------- Ultrasonic ----------------
    wire [7:0] distance;
    wire dist_valid;

    ultrasonic_core u_sensor (
        .clk(clk),
        .echo(echo),
        .trig(trig),
        .distance_cm(distance),
        .valid(dist_valid)
    );

    // ---------------- Encryption ----------------
    wire [15:0] plaintext  = {8'b0, distance};
    wire [15:0] cipher;
    wire enc_valid;

    encrypt_engine_16 u_enc (
        .clk(clk),
        .rst(1'b0),
        .in_valid(dist_valid),
        .plain_in(plaintext),
        .key_in(32'hCAFEBABE),
        .out_valid(enc_valid),
        .cipher_out(cipher)
    );

    // ---------------- UART Control ----------------
    reg  [7:0] tx_data;
    reg        tx_start;
    reg        phase;
    wire       tx_busy;

    uart_tx u_uart (
        .clk(clk),
        .start(tx_start),
        .data(tx_data),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    always @(posedge clk) begin
        tx_start <= 0;

        if (enc_valid && !tx_busy && !phase) begin
            tx_data  <= cipher[7:0];
            tx_start <= 1;
            phase    <= 1;
        end
        else if (!tx_busy && phase) begin
            tx_data  <= cipher[15:8];
            tx_start <= 1;
            phase    <= 0;
        end
    end
endmodule