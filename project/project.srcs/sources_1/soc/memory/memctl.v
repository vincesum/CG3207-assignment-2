`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// memctl: CPU-side memory system for rv_soc (CPU clock domain).
//
//   0x0040_0000  boot ROM, 4 KB, async read on both ports (like the old IROM)
//   0x8000_0000  DDR2 128 MB via I-cache / D-cache (dm_cache, 8 KB each by default)
//   0xFFFF_0000  MMIO (uncached, handled by mmio.v; this block only selects it)
//
// Policy: D-cache write-through, no allocate on a write miss. Stores are posted: the
// request goes to the bridge and the CPU continues; the next DDR2 access waits until
// the bridge has handed the write to the MIG (MIG ordering is Strict).
//
// MemStall is computed from F-stage (PC) and M-stage registers only - nothing from
// the Execute-stage branch decision - so it stays off the CPU's critical path.
//
// Bridge handshake (to mig_bridge.v in the ui_clk domain): req_* hold steady while
// req_tog != ack_tog. ui_clk = 2 x clk (same MMCM), so the paths are timed normally.
// -----------------------------------------------------------------------------
module memctl #(
    parameter IC_IDX   = 9,
    parameter DC_IDX   = 9,
    parameter ROM_FILE = "boot.mem"
)(
    input              clk,
    input              rst,
    // fetch (F stage)
    input      [31:0]  pc,
    output reg [31:0]  instr,
    // data (M stage)
    input      [31:0]  daddr,
    input              dread,
    input      [3:0]   dwrite,
    input      [31:0]  dwdata,
    output reg [31:0]  drdata,
    output             mem_stall,
    // MMIO
    output             mmio_sel,
    input      [31:0]  mmio_rdata,
    // bridge
    output reg         req_tog,
    output reg         req_we,
    output reg [22:0]  req_line,      // byte address [26:4]
    output reg [127:0] req_wdata,
    output reg [15:0]  req_wmask,     // 1 = write this byte
    input              ack_tog,
    input      [127:0] ack_rdata,
    // statistics (one-cycle pulses / levels)
    output             stat_imiss,    // I refill started
    output             stat_dmiss,    // D refill started
    output             stat_stall     // MemStall this cycle
);
    localparam [31:0] NOP = 32'h0000_0013;

    // ---------------- boot ROM ----------------
    reg [31:0] rom [0:1023];
    initial $readmemh(ROM_FILE, rom);

    // ---------------- region decode ----------------
    wire i_rom = (pc[31:12]    == 20'h00400);
    wire i_ddr = (pc[31:27]    == 5'b10000);
    wire d_rom = (daddr[31:12] == 20'h00400);
    wire d_ddr = (daddr[31:27] == 5'b10000);
    assign mmio_sel = (daddr[31:8] == 24'hFFFF00);

    // ---------------- caches ----------------
    wire [31:0] ic_rdata, dc_rdata;
    wire        ic_hit, dc_hit;
    wire        ic_fill, dc_fill, dc_st;

    dm_cache #(.IDX_BITS(IC_IDX)) icache (
        .clk(clk), .rst(rst), .addr(pc), .rdata(ic_rdata), .hit(ic_hit),
        .fill(ic_fill), .fill_data(ack_rdata),
        .st_en(1'b0), .st_mask(4'b0), .st_data(32'b0));

    dm_cache #(.IDX_BITS(DC_IDX)) dcache (
        .clk(clk), .rst(rst), .addr(daddr), .rdata(dc_rdata), .hit(dc_hit),
        .fill(dc_fill), .fill_data(ack_rdata),
        .st_en(dc_st), .st_mask(dwrite), .st_data(dwdata));

    // ---------------- read muxes ----------------
    always @(*) begin
        if (i_rom)      instr = rom[pc[11:2]];
        else if (i_ddr) instr = ic_rdata;
        else            instr = NOP;                 // like Wrapper: invalid fetch = NOP

        if (mmio_sel)   drdata = mmio_rdata;
        else if (d_rom) drdata = rom[daddr[11:2]];
        else if (d_ddr) drdata = dc_rdata;
        else            drdata = 32'd0;
    end

    // ---------------- miss / stall ----------------
    localparam P_NONE = 2'd0, P_WR = 2'd1, P_DRD = 2'd2, P_IRD = 2'd3;
    reg  [1:0] pend;                                  // what the outstanding request is
    wire busy   = req_tog ^ ack_tog;                  // bridge still working on it
    wire i_miss = i_ddr & ~ic_hit;
    wire d_ld   = dread & d_ddr;
    wire d_st   = (|dwrite) & d_ddr;
    wire d_miss = d_ld & ~dc_hit;

    assign mem_stall = i_miss | d_miss | (d_st & busy);

    // read data arrives: refill (pend stays set for exactly this cycle)
    wire fill_now = ~busy & pend[1];
    assign ic_fill = fill_now & (pend == P_IRD);
    assign dc_fill = fill_now & (pend == P_DRD);
    assign dc_st   = d_st & ~mem_stall & dc_hit;      // write-through: update a hit line too

    wire can_issue = ~busy & ~pend[1];
    wire issue_wr  = can_issue & d_st & ~mem_stall;   // store commits this cycle
    wire issue_drd = can_issue & ~issue_wr & d_miss;
    wire issue_ird = can_issue & ~issue_wr & ~d_miss & i_miss;

    always @(posedge clk) begin
        if (rst) begin
            req_tog   <= 1'b0;
            req_we    <= 1'b0;
            req_line  <= 23'd0;
            req_wdata <= 128'd0;
            req_wmask <= 16'd0;
            pend      <= P_NONE;
        end
        else begin
            if (issue_wr) begin
                req_tog   <= ~req_tog;
                req_we    <= 1'b1;
                req_line  <= daddr[26:4];
                req_wdata <= {4{dwdata}};             // CPU already places bytes in their lanes
                req_wmask <= {12'd0, dwrite} << {daddr[3:2], 2'b00};
                pend      <= P_WR;
            end
            else if (issue_drd) begin
                req_tog  <= ~req_tog;
                req_we   <= 1'b0;
                req_line <= daddr[26:4];
                pend     <= P_DRD;
            end
            else if (issue_ird) begin
                req_tog  <= ~req_tog;
                req_we   <= 1'b0;
                req_line <= pc[26:4];
                pend     <= P_IRD;
            end
            else if (~busy)
                pend <= P_NONE;                       // write acknowledged, or refill done
        end
    end

    assign stat_imiss = issue_ird;
    assign stat_dmiss = issue_drd;
    assign stat_stall = mem_stall;
endmodule
