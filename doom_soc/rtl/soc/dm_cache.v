`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// dm_cache: direct-mapped cache array, 16-byte lines (= one MIG burst), with
// asynchronous (LUTRAM) read so it drops into the existing pipeline the same way
// the old async IROM/DMEM did.
//
// Lookup, refill and store update all use the same address: the pipeline is frozen
// (MemStall) while a line is being refilled, so the refill index is always the index
// that missed. That makes every array single-ported (RAMxxX1S).
//
//   IDX_BITS = 9 -> 512 lines x 16 B = 8 KB
//   Cached address space = ADDR_BITS (27 -> 128 MB DDR2); the caller only presents
//   addresses inside the DDR2 window.
// -----------------------------------------------------------------------------
module dm_cache #(
    parameter IDX_BITS  = 9,
    parameter ADDR_BITS = 27
)(
    input              clk,
    input              rst,          // clears all valid bits
    input      [31:0]  addr,
    output     [31:0]  rdata,        // 32-bit word at addr (combinational)
    output             hit,          // combinational
    input              fill,         // write fill_data as the line for addr (refill)
    input      [127:0] fill_data,
    input              st_en,        // store hit: merge st_data into the line under st_mask
    input      [3:0]   st_mask,
    input      [31:0]  st_data
);
    localparam LINES    = 1 << IDX_BITS;
    localparam TAG_BITS = ADDR_BITS - 4 - IDX_BITS;

    (* ram_style = "distributed" *) reg [127:0]        data [0:LINES-1];
    (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tags [0:LINES-1];
    reg [LINES-1:0] valid = {LINES{1'b0}};

    wire [IDX_BITS-1:0] idx  = addr[4 +: IDX_BITS];
    wire [TAG_BITS-1:0] tag  = addr[4 + IDX_BITS +: TAG_BITS];
    wire [127:0]        line = data[idx];

    assign rdata = line[{addr[3:2], 5'b00000} +: 32];
    assign hit   = valid[idx] & (tags[idx] == tag);

    // store hit: replace the enabled bytes of the addressed word
    reg [127:0] merged;
    integer b;
    always @(*) begin
        merged = line;
        for (b = 0; b < 4; b = b + 1)
            if (st_mask[b])
                merged[{addr[3:2], 5'b00000} + 8*b +: 8] = st_data[8*b +: 8];
    end

    always @(posedge clk) begin
        if (fill) begin
            data[idx] <= fill_data;
            tags[idx] <= tag;
        end
        else if (st_en)
            data[idx] <= merged;
    end

    always @(posedge clk) begin
        if (rst)
            valid <= {LINES{1'b0}};
        else if (fill)
            valid[idx] <= 1'b1;
    end
endmodule
