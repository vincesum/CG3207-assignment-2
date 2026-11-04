`timescale 1ns / 1ps
// Self-checking test of the memory controller and caches on their own (memctl + dm_cache).
// The testbench plays both the CPU and the DDR2 side.
module test_cache #(parameter LAT = 6)();
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [31:0] pc = 32'h0040_0000, daddr = 0, dwdata = 0;
    reg         dread = 0;
    reg  [3:0]  dwrite = 0;
    wire [31:0] instr, drdata;
    wire        mem_stall, mmio_sel, req_tog, req_we, stat_imiss, stat_dmiss, stat_stall;
    wire [22:0] req_line;
    wire [127:0] req_wdata;
    wire [15:0] req_wmask;
    reg         ack_tog = 0;
    reg  [127:0] ack_rdata = 0;

    memctl #(.ROM_FILE("test_soc_rom.mem")) dut (
        .clk(clk), .rst(rst), .pc(pc), .instr(instr), .daddr(daddr), .dread(dread), .dwrite(dwrite),
        .dwdata(dwdata), .drdata(drdata), .mem_stall(mem_stall), .mmio_sel(mmio_sel),
        .mmio_rdata(32'hFEED_0000 | daddr[7:0]), .req_tog(req_tog), .req_we(req_we), .req_line(req_line),
        .req_wdata(req_wdata), .req_wmask(req_wmask), .ack_tog(ack_tog), .ack_rdata(ack_rdata),
        .stat_imiss(stat_imiss), .stat_dmiss(stat_dmiss), .stat_stall(stat_stall)
    );

    // ---- DDR2 side: memory behind the bridge ----
    reg [127:0] ram [0:4095];
    integer i, wait_left = 0, reads = 0, writes = 0;
    reg pending = 0;
    function [127:0] pattern(input integer line);
        pattern = {32'hD000_0000 | (line << 4) | 32'hC, 32'hD000_0000 | (line << 4) | 32'h8,
                   32'hD000_0000 | (line << 4) | 32'h4, 32'hD000_0000 | (line << 4)};
    endfunction
    initial for (i = 0; i < 4096; i = i + 1) ram[i] = pattern(i);

    integer k;
    reg seen = 0;
    always @(posedge clk) begin
        if (rst) begin
            seen <= 0; ack_tog <= 0; pending <= 0;
        end
        else if (!pending && req_tog != seen) begin
            seen <= req_tog;
            pending <= 1;
            wait_left <= LAT;
        end
        else if (pending) begin
            if (wait_left == 0) begin
                if (req_we) begin
                    writes = writes + 1;
                    for (k = 0; k < 16; k = k + 1)
                        if (req_wmask[k]) ram[req_line[11:0]][8*k +: 8] = req_wdata[8*k +: 8];
                end
                else begin
                    reads = reads + 1;
                    ack_rdata <= ram[req_line[11:0]];
                end
                ack_tog <= seen;
                pending <= 0;
            end
            else wait_left <= wait_left - 1;
        end
    end

    // ---- Counters ----
    integer dmiss = 0, imiss = 0;
    always @(posedge clk) if (!rst) begin
        dmiss = dmiss + stat_dmiss;
        imiss = imiss + stat_imiss;
    end

    // ---- CPU side ----
    integer checks = 0, fails = 0, stalled = 0;
    task check(input [40*8-1:0] name, input [31:0] got, input [31:0] expected);
        begin
            checks = checks + 1;
            if (got === expected)
                $display("  pass  %0s: %h", name, got);
            else begin
                fails = fails + 1;
                $display("  FAIL  %0s: got %h, expected %h", name, got, expected);
            end
        end
    endtask

    // Runs like an instruction in the Memory stage: holds until MemStall falls
    task finish_access;
        begin
            stalled = 0;
            #1;
            while (mem_stall === 1'b1 && stalled < 200) begin
                @(negedge clk);
                stalled = stalled + 1;
            end
        end
    endtask
    task load(input [31:0] addr);
        begin
            daddr = addr; dread = 1; dwrite = 0;
            finish_access;
        end
    endtask
    task done_access;
        begin
            @(negedge clk);
            dread = 0; dwrite = 0;
        end
    endtask
    task store(input [31:0] addr, input [31:0] data, input [3:0] mask);
        begin
            daddr = addr; dwdata = data; dwrite = mask; dread = 0;
            finish_access;
            @(negedge clk);
            dwrite = 0;
        end
    endtask
    task drain;
        begin
            repeat (LAT + 6) @(negedge clk);
        end
    endtask

    localparam BASE = 32'h8000_0000;
    integer start_count;
    reg [31:0] word;
    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        $display("Regions");
        #1;
        check("instruction from ROM", instr, 32'hFFFF_0437);    // lui s0, 0xFFFF0
        load(32'h0040_0000);
        check("ROM read as data: no stall", stalled, 0);
        check("ROM read as data", drdata, 32'hFFFF_0437);
        done_access;
        load(32'hFFFF_0064);
        check("MMIO selected", mmio_sel, 1);
        check("MMIO read: no stall", stalled, 0);
        check("MMIO read data", drdata, 32'hFEED_0064);
        done_access;
        load(32'h1234_5678);
        check("MMIO not selected elsewhere", mmio_sel, 0);
        check("invalid data read gives 0", drdata, 0);
        done_access;
        pc = 32'h1234_5678;
        #1 check("invalid fetch gives NOP", instr, 32'h0000_0013);
        pc = 32'h0040_0000;

        $display("Load: miss, then hits");
        start_count = dmiss;
        load(BASE + 32'h100);
        check("cold load stalls", stalled > 0, 1);
        check("cold load data", drdata, pattern(16));
        check("cold load counted once", dmiss - start_count, 1);
        done_access;
        load(BASE + 32'h100);
        check("same word: no stall", stalled, 0);
        check("same word: data", drdata, pattern(16));
        done_access;
        load(BASE + 32'h10C);
        check("same line: no stall", stalled, 0);
        check("same line: data", drdata, 32'hD000_010C);
        done_access;
        load(BASE + 32'h110);
        check("next line misses", stalled > 0, 1);
        done_access;
        check("two misses in total", dmiss - start_count, 2);

        $display("Direct mapping: 8 KB apart share a line");
        start_count = dmiss;
        load(BASE + 32'h300);
        done_access;
        load(BASE + 32'h300 + 32'h2000);
        check("conflicting address misses", stalled > 0, 1);
        check("its data", drdata, 32'hD000_0300 + 32'h2000);
        done_access;
        load(BASE + 32'h300);
        check("first address was evicted", stalled > 0, 1);
        check("its data", drdata, 32'hD000_0300);
        done_access;
        check("three misses", dmiss - start_count, 3);

        $display("Stores");
        drain;
        start_count = writes;
        store(BASE + 32'h100, 32'hAAAA_BBBB, 4'b1111);
        check("store to a free bridge: no stall", stalled, 0);
        drain;
        check("store reaches DDR2", ram[16][31:0], 32'hAAAA_BBBB);
        check("one DDR2 write", writes - start_count, 1);
        load(BASE + 32'h100);
        check("store hit updates the cache", drdata, 32'hAAAA_BBBB);
        check("and it still hits", stalled, 0);
        done_access;
        store(BASE + 32'h104, 32'h0000_1100, 4'b0010);
        drain;
        check("byte store to DDR2", ram[16][63:32], 32'hD000_1104);
        load(BASE + 32'h104);
        check("byte store in the cache", drdata, 32'hD000_1104);
        done_access;
        start_count = dmiss;
        store(BASE + 32'h700, 32'h1234_5678, 4'b1111);
        drain;
        load(BASE + 32'h700);
        check("store miss doesn't allocate", dmiss - start_count, 1);
        check("and the data is right", drdata, 32'h1234_5678);
        done_access;
        store(BASE + 32'h800, 32'h1, 4'b1111);
        store(BASE + 32'h810, 32'h2, 4'b1111);
        check("store while the bridge is busy stalls", stalled > 0, 1);
        drain;
        check("first store arrived", ram[128][31:0], 32'h1);
        check("second store arrived", ram[129][31:0], 32'h2);

        $display("Instruction cache");
        start_count = imiss;
        pc = BASE + 32'h900;
        #1 check("fetch miss stalls", mem_stall, 1);
        while (mem_stall === 1'b1) @(negedge clk);
        check("fetched instruction", instr, 32'hD000_0900);
        check("counted once", imiss - start_count, 1);
        pc = BASE + 32'h904;
        #1 check("same line: no stall", mem_stall, 0);
        check("same line: data", instr, 32'hD000_0904);
        pc = 32'h0040_0000;
        #1;
        load(BASE + 32'h900);
        check("data cache is separate: misses", stalled > 0, 1);
        done_access;

        $display("Data and instruction miss together");
        start_count = reads;
        pc = BASE + 32'hA00;
        load(BASE + 32'hB00);
        check("both served", reads - start_count, 2);
        check("data", drdata, 32'hD000_0B00);
        check("instruction", instr, 32'hD000_0A00);
        done_access;
        pc = 32'h0040_0000;

        $display("Reset");
        @(negedge clk); rst = 1;
        @(negedge clk); rst = 0;
        @(negedge clk);
        load(BASE + 32'h100);
        check("reset invalidates the cache", stalled > 0, 1);
        done_access;

        $display("test_cache: %0d passed, %0d failed", checks - fails, fails);
        if (fails == 0) $display("==== test_cache: PASS ====");
        else            $display("==== test_cache: FAIL (%0d) ====", fails);
        $finish;
    end
endmodule
