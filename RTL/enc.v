// ============================================================
// HW Encryption Engine (RTL-only)
// 16-bit block encryption with multi-stage transforms:
//   Stage0: XOR whitening with key
//   Stage1: 4-bit S-Box substitution (non-linear)
//   Stage2: Bit permutation (P-Box)
//   Stage3: Non-linear mixing (add + xorshift + rotate)
//   Stage4: Final key mixing (+ round constant)
// Latency: 5 cycles (from in_valid to out_valid)
// ============================================================

module encrypt_engine_16 (
    input  wire        clk,
    input  wire        rst,        // synchronous reset (active high)
    input  wire        in_valid,
    input  wire [15:0] plain_in,
    input  wire [31:0] key_in,     // 32-bit master key (static or programmable)
    output reg         out_valid,
    output reg  [15:0] cipher_out
);

    // --------------------------
    // Internal key schedule (simple RTL LFSR-based evolving key)
    // This makes each block use a changing subkey -> stronger than fixed XOR.
    // --------------------------
    reg [31:0] key_state;
    wire       lfsr_fb = key_state[31] ^ key_state[21] ^ key_state[1] ^ key_state[0];

    // Subkeys derived from key_state
    wire [15:0] k0 = key_state[15:0];
    wire [15:0] k1 = {key_state[7:0], key_state[15:8]};     // rotate bytes
    wire [15:0] k2 = key_state[31:16];

    // Round counter / constant (predefined, deterministic)
    reg [7:0] round_ctr;

    // --------------------------
    // Pipeline registers for 5 stages
    // --------------------------
    reg        v0, v1, v2, v3, v4;
    reg [15:0] s0, s1, s2, s3, s4;

    // --------------------------
    // S-Box (4-bit) : non-linear substitution
    // (You can replace with any fixed predefined mapping.)
    // --------------------------
    function automatic [3:0] sbox4;
        input [3:0] x;
        begin
            case (x)
                4'h0: sbox4 = 4'hC;
                4'h1: sbox4 = 4'h5;
                4'h2: sbox4 = 4'h6;
                4'h3: sbox4 = 4'hB;
                4'h4: sbox4 = 4'h9;
                4'h5: sbox4 = 4'h0;
                4'h6: sbox4 = 4'hA;
                4'h7: sbox4 = 4'hD;
                4'h8: sbox4 = 4'h3;
                4'h9: sbox4 = 4'hE;
                4'hA: sbox4 = 4'hF;
                4'hB: sbox4 = 4'h8;
                4'hC: sbox4 = 4'h4;
                4'hD: sbox4 = 4'h7;
                4'hE: sbox4 = 4'h1;
                4'hF: sbox4 = 4'h2;
            endcase
        end
    endfunction

    // Apply S-Box to 16-bit (nibble-wise)
    function automatic [15:0] sub_bytes16;
        input [15:0] x;
        begin
            sub_bytes16 = {
                sbox4(x[15:12]),
                sbox4(x[11:8]),
                sbox4(x[7:4]),
                sbox4(x[3:0])
            };
        end
    endfunction

    // --------------------------
    // P-Box permutation (bit shuffle)
    // Predefined permutation:
    // out[i] = in[p[i]]
    // --------------------------
    function automatic [15:0] permute16;
        input [15:0] x;
        reg [15:0] y;
        begin
            // A fixed permutation (spreads bits across positions)
            y[15] = x[0];
            y[14] = x[4];
            y[13] = x[8];
            y[12] = x[12];
            y[11] = x[1];
            y[10] = x[5];
            y[9]  = x[9];
            y[8]  = x[13];
            y[7]  = x[2];
            y[6]  = x[6];
            y[5]  = x[10];
            y[4]  = x[14];
            y[3]  = x[3];
            y[2]  = x[7];
            y[1]  = x[11];
            y[0]  = x[15];
            permute16 = y;
        end
    endfunction

    // Rotate-left helper
    function automatic [15:0] rol16;
        input [15:0] x;
        input [3:0]  sh;
        begin
            rol16 = (x << sh) | (x >> (16 - sh));
        end
    endfunction

    // --------------------------
    // Sequential pipeline
    // --------------------------
    always @(posedge clk) begin
        if (rst) begin
            key_state  <= 32'h0;
            round_ctr  <= 8'h00;

            v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0; v4 <= 1'b0;
            s0 <= 16'h0; s1 <= 16'h0; s2 <= 16'h0; s3 <= 16'h0; s4 <= 16'h0;

            out_valid  <= 1'b0;
            cipher_out <= 16'h0;
        end else begin
            // Load key_state once (or keep updating if you want)
            // If you want key_state fixed: comment out the update on each block.
            if (key_state == 32'h0) begin
                key_state <= (key_in ^ 32'hA5A5_1C3D); // deterministic init
            end

            // ---------------- Stage0: XOR whitening ----------------
            v0 <= in_valid;
            if (in_valid) begin
                s0 <= plain_in ^ k0; // key mix
            end

            // ---------------- Stage1: Substitution ----------------
            v1 <= v0;
            if (v0) begin
                s1 <= sub_bytes16(s0);
            end

            // ---------------- Stage2: Permutation -----------------
            v2 <= v1;
            if (v1) begin
                s2 <= permute16(s1) ^ k1; // extra mixing with derived key
            end

            // ---------------- Stage3: Non-linear mixing ------------
            // mix = rol(add,3) ^ xorshift-like diffusion
            v3 <= v2;
            if (v2) begin
                // non-linear (addition) + diffusion (shifts/xor/rotate)
                // add stage introduces carry-based non-linearity
                // include round_ctr for per-block variation
                // NOTE: all synthesizable
                begin : mix_block
                    reg [15:0] addv;
                    reg [15:0] xs;
                    addv = s2 + k2 + {8'h00, round_ctr};     // non-linear mapping via addition
                    xs   = addv ^ (addv << 5) ^ (addv >> 3); // xorshift diffusion
                    s3   <= rol16(xs, 4'd3);
                end
            end

            // ---------------- Stage4: Final key + round constant ---
            v4 <= v3;
            if (v3) begin
                // final whitening and round constant injection
                s4 <= s3 ^ {round_ctr, ~round_ctr}; // predefined constant pattern
            end

            // Output
            out_valid  <= v4;
            if (v4) begin
                cipher_out <= s4;
            end

            // Update key schedule + round counter only when a block enters
            if (in_valid) begin
                round_ctr <= round_ctr + 8'd1;
                key_state <= {key_state[30:0], lfsr_fb}; // LFSR shift
            end
        end
    end

endmodule