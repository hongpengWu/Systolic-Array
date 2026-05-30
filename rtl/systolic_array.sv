module systolic_array #(
    parameter int N       = 4,
    parameter int DATA_W  = 16,
    parameter int ACC_W   = 32
)(
    input  logic              clk,
    input  logic              rst_n,

    input  logic              clear,        // from controller (sa_clear)
    input  logic              start,        // from controller (sa_start)

    // Streams from controller / memories (one per row/column for true NxN skew feed)
    input  logic [DATA_W-1:0] sa_in_a [0:N-1],   // A values at west edge, row r
    input  logic [DATA_W-1:0] sa_in_b [0:N-1],   // B values at north edge, col c

    // Results back to controller
    output logic [ACC_W-1:0]  sa_out_data,  // C elements
    output logic              sa_out_valid,
    output logic              sa_done
);

    // ------------------------------------------------------------------------
    // Internal wiring for PE mesh
    // ------------------------------------------------------------------------
    // a_bus: horizontal A values flowing from left to right.
    //  - Indexing: [row][column tap]
    //  - a_bus[r][c] feeds in_a of PE(r,c), out_a of that PE drives a_bus[r][c+1].
    logic [DATA_W-1:0] a_bus [0:N-1][0:N];

    // b_bus: vertical B values flowing from top to bottom.
    //  - b_bus[r][c] feeds in_b of PE(r,c), out_b of that PE drives b_bus[r+1][c].
    logic [DATA_W-1:0] b_bus [0:N][0:N-1];

    // Accumulators from each PE (local C elements).
    logic [ACC_W-1:0]  acc_grid [0:N-1][0:N-1];

    // ------------------------------------------------------------------------
    // Cycle counter and output drain: feed for (2*N-1) cycles, then drain N^2 results
    // ------------------------------------------------------------------------
    localparam int FEED_CYCLES = 2 * N - 1;
    localparam int DRAIN_CYCLES = N * N;
    localparam int TOTAL_CYCLES = FEED_CYCLES + DRAIN_CYCLES;

    logic [$clog2(TOTAL_CYCLES+1)-1:0] cycle_cnt;
    logic [$clog2(N*N)-1:0]            out_idx;
    logic                               running;
    logic                               drain_phase;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt <= '0;
            out_idx   <= '0;
            running   <= 1'b0;
        end else if (clear) begin
            cycle_cnt <= '0;
            out_idx   <= '0;
            running   <= 1'b0;
        end else if (start && !running) begin
            running   <= 1'b1;
            cycle_cnt <= '0;
        end else if (running) begin
            cycle_cnt <= cycle_cnt + 1;
            if (drain_phase && (out_idx < DRAIN_CYCLES)) begin
                out_idx <= out_idx + 1;
            end
        end
    end

    assign drain_phase = running && (cycle_cnt >= FEED_CYCLES);
    assign sa_out_valid = drain_phase && (out_idx < DRAIN_CYCLES);
    assign sa_done      = running && (cycle_cnt >= TOTAL_CYCLES - 1);

    // Row-major output: out_idx = row*N + col -> row = out_idx / N, col = out_idx % N
    logic [$clog2(N)-1:0] out_row, out_col;
    assign out_row = out_idx / N;
    assign out_col = out_idx % N;
    assign sa_out_data = acc_grid[out_row][out_col];

    // ------------------------------------------------------------------------
    // Drive only the west and north edges from the controller.
    // Internal mesh links are driven exclusively by neighboring PEs.
    // ------------------------------------------------------------------------
    genvar edge_r, edge_c;
    generate
        for (edge_r = 0; edge_r < N; edge_r++) begin : WEST_EDGE
            assign a_bus[edge_r][0] = sa_in_a[edge_r];
        end
        for (edge_c = 0; edge_c < N; edge_c++) begin : NORTH_EDGE
            assign b_bus[0][edge_c] = sa_in_b[edge_c];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Instantiate N x N PE grid and connect buses
    // ------------------------------------------------------------------------
    genvar i, j;
    generate
        for (i = 0; i < N; i++) begin : ROW
            for (j = 0; j < N; j++) begin : COL
                pe #(
                    .DATA_W(DATA_W),
                    .ACC_W (ACC_W)
                ) u_pe (
                    .clk    (clk),
                    .rst_n  (rst_n),
                    .clear  (clear),

                    .in_a   (a_bus[i][j]),
                    .in_b   (b_bus[i][j]),
                    .out_a  (a_bus[i][j+1]),
                    .out_b  (b_bus[i+1][j]),
                    .acc_out(acc_grid[i][j])
                );
            end
        end
    endgenerate

endmodule
