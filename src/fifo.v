`default_nettype none

/*
 * ------------------------------------------------------------
 *  Project  : FIFO Memory
 *  File     : fifo.v
 *  HDL      : Verilog
 *  Base     : Adapted from FPGA4Student FIFO design
 * ------------------------------------------------------------
 *  Modified by  : Cleber Moretti
 *  Date         : 02-Apr-2026
 *  Version      : 0.1.0
 * ------------------------------------------------------------
 *
 *  Description:
 *    This project implements a FIFO (First-In, First-Out)
 *    memory structure in Verilog, suitable for FPGA-based
 *    systems. The design is based on a reference
 *    implementation and modified for study and testing.
 *
 *    The memory is organized as 16 stages with 8-bit wide
 *    data entries. The following status signals are provided:
 *
 *      Full      : asserted when the FIFO has no remaining
 *                  capacity; deasserted otherwise.
 *
 *      Empty     : asserted when no data is stored in the
 *                  FIFO; deasserted otherwise.
 *
 *      Overflow  : asserted when a write is attempted while
 *                  the FIFO is already full; deasserted
 *                  otherwise.
 *
 *      Underflow : asserted when a read is attempted while
 *                  the FIFO is empty; deasserted otherwise.
 *
 *      Threshold : asserted when the number of entries in
 *                  the FIFO reaches a defined threshold;
 *                  deasserted otherwise.
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


// ============================================================
// TOP-LEVEL MODULE: fifo
// ============================================================
// This is the main module. It does not contain any logic by
// itself — its only job is to connect all submodules together,
// wiring inputs, outputs and internal signals between them.
//
// Parameters let you change the FIFO size and behavior without
// editing the internal logic:
//
//   DEPTH     : number of storage slots (default: 16)
//   WIDTH     : size of each data word in bits (default: 8)
//   THRESHOLD : occupancy level that triggers the threshold
//               flag (default: 8, i.e. half full)
// ============================================================
module fifo #(
  parameter DEPTH     = 16,
  parameter WIDTH     = 8,
  parameter THRESHOLD = 8
)(
  input                  clk,      // Clock — all sequential logic triggers on the rising edge
  input                  rst_n,    // Active-low reset — when low, all registers are cleared
  input                  wr,       // Write request from the user
  input                  rd,       // Read request from the user
  input      [WIDTH-1:0] data_in,  // Data word to be written into the FIFO
  output     [WIDTH-1:0] data_out, // Data word read from the FIFO
  output                 full,     // High when the FIFO is full
  output                 empty,    // High when the FIFO is empty
  output                 threshold, // High when occupancy reaches THRESHOLD
  output                 overflow,  // High when a write was attempted while full
  output                 underflow  // High when a read was attempted while empty
);

  // PTR_W: pointer width in bits.
  // We need one extra bit beyond what is required to index DEPTH slots.
  // That extra MSB is what lets us tell full from empty when both
  // pointers point to the same index (see status_ctrl for details).
  // Example: DEPTH=16 → $clog2(16)=4, so PTR_W=5.
  localparam PTR_W = $clog2(DEPTH) + 1;

  // wr_ptr: write pointer — points to the next slot to be written.
  // rd_ptr: read  pointer — points to the next slot to be read.
  wire [PTR_W-1:0] wr_ptr, rd_ptr;

  // wr_en: internal write enable — only high when wr=1 AND the FIFO is not full.
  // rd_en: internal read  enable — only high when rd=1 AND the FIFO is not empty.
  wire wr_en, rd_en;

  // ------------------------------------------------------------
  // Instantiate submodules
  // ------------------------------------------------------------

  wr_ctrl #(
    .PTR_W (PTR_W)
  ) u_wr_ctrl (
    .clk    (clk),
    .rst_n  (rst_n),
    .wr     (wr),
    .full   (full),
    .wr_en  (wr_en),
    .wr_ptr (wr_ptr)
  );

  rd_ctrl #(
    .PTR_W (PTR_W)
  ) u_rd_ctrl (
    .clk    (clk),
    .rst_n  (rst_n),
    .rd     (rd),
    .empty  (empty),
    .rd_en  (rd_en),
    .rd_ptr (rd_ptr)
  );

  mem_array #(
    .DEPTH (DEPTH),
    .WIDTH (WIDTH),
    .PTR_W (PTR_W)
  ) u_mem (
    .clk      (clk),
    .wr_en    (wr_en),
    .wr_ptr   (wr_ptr),
    .rd_ptr   (rd_ptr),
    .data_in  (data_in),
    .data_out (data_out)
  );

  status_ctrl #(
    .PTR_W     (PTR_W),
    .THRESHOLD (THRESHOLD)
  ) u_status (
    .clk       (clk),
    .rst_n     (rst_n),
    .wr        (wr),
    .rd        (rd),
    .wr_en     (wr_en),
    .rd_en     (rd_en),
    .wr_ptr    (wr_ptr),
    .rd_ptr    (rd_ptr),
    .full      (full),
    .empty     (empty),
    .threshold (threshold),
    .overflow  (overflow),
    .underflow (underflow)
  );

endmodule


// ============================================================
// SUBMODULE: wr_ctrl  (Write Controller)
// ============================================================
// Manages the write pointer and the internal write enable.
//
// How it works:
//   - wr_en is asserted only when the user requests a write
//     (wr=1) AND the FIFO still has space (full=0).
//   - On every rising clock edge where wr_en is high, the
//     write pointer advances by one position.
//   - On reset, the pointer goes back to zero.
// ============================================================
module wr_ctrl #(
  parameter PTR_W = 5
)(
  input                  clk,    // Clock
  input                  rst_n,  // Active-low reset
  input                  wr,     // Write request from the user
  input                  full,   // Full flag from status_ctrl
  output                 wr_en,  // Actual write enable (wr AND NOT full)
  output reg [PTR_W-1:0] wr_ptr  // Write pointer
);

  // Block a write if the FIFO is already full
  assign wr_en = wr & ~full;

  always @(posedge clk or negedge rst_n) begin
    if (~rst_n)
      wr_ptr <= 'b0;       // Clear pointer on reset
    else if (wr_en)
      wr_ptr <= wr_ptr + 1'b1; // Advance to next slot
  end

endmodule


// ============================================================
// SUBMODULE: rd_ctrl  (Read Controller)
// ============================================================
// Manages the read pointer and the internal read enable.
//
// How it works:
//   - rd_en is asserted only when the user requests a read
//     (rd=1) AND the FIFO has data available (empty=0).
//   - On every rising clock edge where rd_en is high, the
//     read pointer advances by one position.
//   - On reset, the pointer goes back to zero.
// ============================================================
module rd_ctrl #(
  parameter PTR_W = 5
)(
  input                  clk,    // Clock
  input                  rst_n,  // Active-low reset
  input                  rd,     // Read request from the user
  input                  empty,  // Empty flag from status_ctrl
  output                 rd_en,  // Actual read enable (rd AND NOT empty)
  output reg [PTR_W-1:0] rd_ptr  // Read pointer
);

  // Block a read if the FIFO has no data
  assign rd_en = rd & ~empty;

  always @(posedge clk or negedge rst_n) begin
    if (~rst_n)
      rd_ptr <= 'b0;        // Clear pointer on reset
    else if (rd_en)
      rd_ptr <= rd_ptr + 1'b1; // Advance to next slot
  end

endmodule


// ============================================================
// SUBMODULE: mem_array  (Memory Array)
// ============================================================
// The actual storage of the FIFO — a simple register array.
//
// How it works:
//   - mem is an array of WIDTH-bit registers with DEPTH slots.
//   - Writes are synchronous: data_in is stored on the rising
//     clock edge when wr_en is high.
//   - Reads are asynchronous (combinational): data_out always
//     reflects whatever is at the current rd_ptr position,
//     with no clock delay.
//   - Only the lower bits of each pointer are used to index
//     into the array — the MSB is only used for full/empty
//     detection in status_ctrl.
// ============================================================
module mem_array #(
  parameter DEPTH = 16,
  parameter WIDTH = 8,
  parameter PTR_W = 5
)(
  input                  clk,      // Clock
  input                  wr_en,    // Write enable from wr_ctrl
  input      [PTR_W-1:0] wr_ptr,   // Write pointer from wr_ctrl
  input      [PTR_W-1:0] rd_ptr,   // Read pointer from rd_ctrl
  input      [WIDTH-1:0] data_in,  // Data to write
  output     [WIDTH-1:0] data_out  // Data being read
);

  // mem: the register array that stores the FIFO contents.
  // Indexed by the lower bits of the pointer (MSB excluded).
  reg [WIDTH-1:0] mem [0:DEPTH-1];

  // Synchronous write
  always @(posedge clk) begin
    if (wr_en)
      mem[wr_ptr[PTR_W-2:0]] <= data_in;
  end

  // Asynchronous read — output follows rd_ptr immediately
  assign data_out = mem[rd_ptr[PTR_W-2:0]];

endmodule


// ============================================================
// SUBMODULE: status_ctrl  (Status Controller)
// ============================================================
// Derives all status flags by comparing the write and read
// pointers. This is the most conceptually interesting module.
//
// Full / Empty detection trick:
//   The pointers are one bit wider than needed to index DEPTH
//   slots. That extra MSB acts as a "lap counter" — it flips
//   every time the pointer wraps around past the last slot.
//
//   If both pointers have the same MSB, the write pointer has
//   NOT lapped the read pointer → same number of laps → EMPTY.
//
//   If the MSBs differ, the write pointer has lapped once more
//   than the read pointer → the array is exactly FULL.
//
//   In both cases, the lower bits must be equal (same index).
//
// Threshold:
//   occupancy = wr_ptr - rd_ptr gives the number of entries
//   currently stored. When it reaches THRESHOLD, the flag is
//   asserted.
//
// Overflow / Underflow:
//   These are registered (sequential) flags, not combinational.
//   Overflow  is set when the user writes while full,
//             and cleared once a read makes room.
//   Underflow is set when the user reads while empty,
//             and cleared once a write adds data.
// ============================================================
module status_ctrl #(
  parameter PTR_W     = 5,
  parameter THRESHOLD = 8
)(
  input                  clk,       // Clock
  input                  rst_n,     // Active-low reset
  input                  wr,        // Write request from user
  input                  rd,        // Read request from user
  input                  wr_en,     // Actual write enable from wr_ctrl
  input                  rd_en,     // Actual read enable from rd_ctrl
  input      [PTR_W-1:0] wr_ptr,    // Write pointer from wr_ctrl
  input      [PTR_W-1:0] rd_ptr,    // Read pointer from rd_ctrl
  output reg             full,      // FIFO is completely full
  output reg             empty,     // FIFO has no data
  output reg             threshold, // Occupancy has reached THRESHOLD
  output reg             overflow,  // A write was attempted while full
  output reg             underflow  // A read was attempted while empty
);

  // msb_diff: compares the most significant bit of both pointers.
  // When they differ, it means the write pointer has lapped the
  // read pointer exactly once, indicating the FIFO is full.
  wire msb_diff = wr_ptr[PTR_W-1] ^ rd_ptr[PTR_W-1];

  // idx_equal: checks if the lower bits (the actual array index)
  // of both pointers are the same.
  wire idx_equal = (wr_ptr[PTR_W-2:0] == rd_ptr[PTR_W-2:0]);

  // occupancy: the number of entries currently in the FIFO.
  // Computed by subtracting the read pointer from the write pointer.
  // This works correctly across wrap-arounds because of the extra MSB.
  wire [PTR_W-1:0] occupancy = wr_ptr - rd_ptr;

  // ------------------------------------------------------------
  // Combinational flags — update instantly whenever pointers change
  // ------------------------------------------------------------
  always @(*) begin
    // Full:  MSBs differ AND lower bits match
    full      = msb_diff & idx_equal;

    // Empty: MSBs are equal AND lower bits match
    empty     = ~msb_diff & idx_equal;

    // Threshold: asserted when stored entries reach the limit
    threshold = (occupancy >= THRESHOLD[PTR_W-1:0]);
  end

  // ------------------------------------------------------------
  // Overflow — registered flag
  // Set  : user requests a write while the FIFO is full
  //        and no read is happening at the same time.
  // Clear: a successful read frees space, so the condition is gone.
  // ------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n)
      overflow <= 1'b0;
    else if (full & wr & ~rd_en)
      overflow <= 1'b1;
    else if (rd_en)
      overflow <= 1'b0;
  end

  // ------------------------------------------------------------
  // Underflow — registered flag
  // Set  : user requests a read while the FIFO is empty
  //        and no write is happening at the same time.
  // Clear: a successful write adds data, so the condition is gone.
  // ------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n)
      underflow <= 1'b0;
    else if (empty & rd & ~wr_en)
      underflow <= 1'b1;
    else if (wr_en)
      underflow <= 1'b0;
  end

endmodule

`default_nettype wire