/*
 * ------------------------------------------------------------
 *  Project  : FIFO Memory
 *  File     : fifo_tb.v
 *  HDL      : Verilog
 *  Base     : Adapted from FPGA4Student FIFO design
 * ------------------------------------------------------------
 *  Modified by  : Cleber Moretti
 *  Date         : 02-Apr-2026
 *  Version      : 0.1.0
 * ------------------------------------------------------------
 *
 *  Description:
 *    Testbench for the FIFO memory module. Exercises the DUT
 *    by writing 17 words (one more than the FIFO depth to
 *    trigger overflow) and then reading them back. A
 *    self-checking mechanism compares each output against a
 *    local reference memory and reports PASS or FAIL for
 *    every read transaction.
 *
 * ------------------------------------------------------------
 *  Simulation (Icarus Verilog):
 * ------------------------------------------------------------
 *
 *  1. Compile:
 *     iverilog -o sim_fifo fifo.v fifo_tb.v
 *
 *  2. Run:
 *     vvp sim_fifo
 *
 *  3. View waveform (optional):
 *     gtkwave dump.vcd
 *
 */


// ------------------------------------------------------------
// Timescale directive
// Sets the simulation time unit and precision.
// Format: `timescale <unit> / <precision>
// Here: 1 ns per tick, precision of 1 ps.
// ------------------------------------------------------------
`timescale 1ns / 1ps

// ------------------------------------------------------------
// DELAY constant
// Defines the base time unit used throughout the testbench.
// All waits are multiples of this value, making it easy to
// scale timing by changing a single number.
// ------------------------------------------------------------
`define DELAY 10

// ============================================================
// TESTBENCH MODULE: fifo_tb
// ============================================================
// A testbench has no ports — it is a closed, self-contained
// simulation environment. Inputs to the DUT are driven by
// 'reg' variables (because we assign them procedurally), and
// outputs from the DUT are captured on 'wire' variables.
// ============================================================
module fifo_tb;

  // ----------------------------------------------------------
  // Simulation limit
  // If the self-checking logic does not call $finish before
  // this time is reached, the simulation stops on its own.
  // ----------------------------------------------------------
  parameter ENDTIME = 40000;

  // ----------------------------------------------------------
  // DUT inputs — declared as reg so we can drive them from
  // initial/always blocks.
  // ----------------------------------------------------------
  reg       clk;      // Clock signal driven by clock_generator task
  reg       rst_n;    // Active-low reset driven by reset_generator task
  reg       wr;       // Write request sent to the FIFO
  reg       rd;       // Read request sent to the FIFO
  reg [7:0] data_in;  // Data word to write into the FIFO

  // ----------------------------------------------------------
  // DUT outputs — declared as wire because they are driven by
  // the DUT itself, not by the testbench.
  // ----------------------------------------------------------
  wire [7:0] data_out;       // Data word coming out of the FIFO
  wire       empty;          // Asserted when the FIFO has no data
  wire       full;           // Asserted when the FIFO is completely full
  wire       threshold;      // Asserted when occupancy reaches the threshold
  wire       overflow;       // Asserted when a write was attempted while full
  wire       underflow;      // Asserted when a read was attempted while empty

  // Loop index used in the write and read for-loops
  integer i;

  // ----------------------------------------------------------
  // DUT instantiation
  // Connects the testbench signals to the FIFO module ports.
  // Named connections (.port(signal)) are used so the order
  // does not matter and mismatches are caught at compile time.
  // ----------------------------------------------------------
  fifo u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .wr        (wr),
    .rd        (rd),
    .data_in   (data_in),
    .data_out  (data_out),
    .full      (full),
    .empty     (empty),
    .threshold (threshold),
    .overflow  (overflow),
    .underflow (underflow)
  );

  // ----------------------------------------------------------
  // Waveform dump — GTKWave
  // $dumpfile sets the name of the output file in VCD format
  // (Value Change Dump). VCD is a standard text format that
  // records every signal transition during the simulation.
  //
  // $dumpvars(levels, module):
  //   - levels = 0 means dump ALL hierarchy levels below the
  //     specified module (no depth limit).
  //   - fifo_tb is the root module, so every signal in the
  //     design — including signals inside u_dut — is captured.
  //
  // After running vvp, open the waveform with:
  //   gtkwave dump.vcd
  // ----------------------------------------------------------
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, fifo_tb);
  end

  // ----------------------------------------------------------
  // Initial conditions
  // All inputs start at a known safe state before any clock
  // edge or reset occurs.
  // ----------------------------------------------------------
  initial begin
    clk     = 1'b0;
    rst_n   = 1'b0;
    wr      = 1'b0;
    rd      = 1'b0;
    data_in = 8'd0;
  end

  // ----------------------------------------------------------
  // Test entry point
  // Launches all tasks in parallel using a fork/join block.
  // Each task runs concurrently, mimicking a real environment
  // where clock, reset and stimulus all happen simultaneously.
  // ----------------------------------------------------------
  initial begin
    fork
      clock_generator;   // Produces the clock forever
      reset_generator;   // Pulses reset at the start
      operation_process; // Drives write and read sequences
      debug_display;     // Monitors signals in real time
      watchdog;          // Ends simulation after ENDTIME
    join
  end

  // ----------------------------------------------------------
  // Task: clock_generator
  // Toggles the clock every DELAY units, producing a
  // continuous square wave with period = 2 * DELAY.
  // 'forever' runs indefinitely until $finish is called.
  // ----------------------------------------------------------
  task clock_generator;
    begin
      forever #`DELAY clk = ~clk;
    end
  endtask

  // ----------------------------------------------------------
  // Task: reset_generator
  // Briefly releases and re-asserts reset after startup to
  // verify the DUT recovers correctly from an mid-run reset.
  //
  // Timeline:
  //   t=0        rst_n = 0 (set in initial block above)
  //   t=2*DELAY  rst_n = 1 (release reset)
  //   t=+7.9ns   rst_n = 0 (apply a glitch reset)
  //   t=+7.09ns  rst_n = 1 (release again — DUT runs normally)
  // ----------------------------------------------------------
  task reset_generator;
    begin
      #(`DELAY * 2) rst_n = 1'b1;
      #7.9          rst_n = 1'b0;
      #7.09         rst_n = 1'b1;
    end
  endtask

  // ----------------------------------------------------------
  // Task: operation_process
  // Drives the main write and read sequences.
  //
  // Write phase: 17 words are written (one more than DEPTH=16)
  // to intentionally trigger the overflow condition and verify
  // the flag is asserted correctly.
  //
  // Read phase: 17 read cycles are issued. Reads while empty
  // are blocked internally by the DUT (rd_en = rd & ~empty),
  // so the underflow flag will be tested as well.
  // ----------------------------------------------------------
  task operation_process;
    begin
      // Write 17 words — last one overflows
      for (i = 0; i < 17; i = i + 1) begin
        #(`DELAY * 5)
        wr      = 1'b1;
        data_in = data_in + 8'd1; // Increment data each cycle
        #(`DELAY * 2)
        wr = 1'b0;
      end

      // Small gap between write and read phases
      #(`DELAY)

      // Read 17 words — last one underflows (FIFO will be empty)
      for (i = 0; i < 17; i = i + 1) begin
        #(`DELAY * 2)
        rd = 1'b1;
        #(`DELAY * 2)
        rd = 1'b0;
      end
    end
  endtask

  // ----------------------------------------------------------
  // Task: debug_display
  // Prints a header banner and then continuously monitors key
  // signals using $monitor. Unlike $display (which prints once),
  // $monitor fires automatically every time any listed signal
  // changes value — so you get a timestamped log of every
  // relevant event without adding $display calls everywhere.
  // ----------------------------------------------------------
  task debug_display;
    begin
      $display("");
      $display("  ============================================");
      $display("           FIFO SIMULATION — START           ");
      $display("  ============================================");
      $display("  Depth: 16 | Width: 8-bit | Threshold: 8   ");
      $display("  --------------------------------------------");
      $display("");
      // Column header so the monitor lines are easier to read
      $display("  %8s  %2s  %2s  %8s  %4s  %5s  %8s  %9s",
               "TIME(ns)", "WR", "RD", "DATA_IN", "FULL", "EMPTY",
               "OVERFLOW", "UNDERFLOW");
      $display("  --------------------------------------------");
      $monitor("  %8t  %2b   %2b    0x%h      %b      %b       %b         %b",
               $time, wr, rd, data_in, full, empty, overflow, underflow);
    end
  endtask

  // ----------------------------------------------------------
  // Self-checking logic
  // Maintains a local reference memory (ref_mem) that mirrors
  // every write made to the DUT. On each valid read, the
  // expected value is compared against data_out and the result
  // is printed in a clean table format.
  //
  // waddr  : next write slot in the reference memory
  // raddr  : next read slot in the reference memory
  // ref_mem: shadow copy of what should come out of the FIFO
  // passes : counts successful comparisons
  // ----------------------------------------------------------
  reg  [5:0] waddr, raddr;
  reg  [7:0] ref_mem [0:63];
  integer    passes;

  initial passes = 0;

  always @(posedge clk) begin

    if (~rst_n) begin
      waddr <= 6'd0;
      raddr <= 6'd0;
    end else begin

      // Mirror every write into the reference memory
      if (wr) begin
        ref_mem[waddr] <= data_in;
        waddr          <= waddr + 1;
      end

      // On a valid read, compare DUT output against reference
      if (rd & ~empty) begin

        if (data_out == ref_mem[raddr]) begin
          passes = passes + 1;
          $display("  [READ %02d]  got=0x%h  expected=0x%h  --> PASS",
                   passes, data_out, ref_mem[raddr]);

          // All 16 slots read back correctly — simulation done
          if (raddr == 15) begin
            $display("");
            $display("  ============================================");
            $display("   RESULT: ALL %0d READS PASSED", passes);
            $display("  ============================================");
            $display("");
            $finish;
          end

        end else begin
          $display("  [READ %02d]  got=0x%h  expected=0x%h  --> FAIL  <<<",
                   raddr + 1, data_out, ref_mem[raddr]);
          $display("");
          $display("  ============================================");
          $display("   RESULT: MISMATCH — SIMULATION ABORTED     ");
          $display("  ============================================");
          $display("");
          $finish;
        end

        raddr <= raddr + 1;
      end

    end
  end

  // ----------------------------------------------------------
  // Task: watchdog
  // Safety net — if the self-checking logic never calls
  // $finish (e.g. due to a stimulus bug or deadlock), the
  // simulation stops after ENDTIME regardless.
  // ----------------------------------------------------------
  task watchdog;
    begin
      #ENDTIME
      $display("");
      $display("  ============================================");
      $display("   RESULT: TIMEOUT — simulation limit reached ");
      $display("   Passes so far: %0d / 16", passes);
      $display("  ============================================");
      $display("");
      $finish;
    end
  endtask

endmodule