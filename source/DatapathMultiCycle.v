/* INSERT NAME AND PENNKEY HERE */

`timescale 1ns / 1ns

// registers are 32 bits in RV32
`define REG_SIZE 31

// RV opcodes are 7 bits
`define OPCODE_SIZE 6

// Don't forget your CLA and Divider
//`include "cla.v"
//`include "DividerUnsignedPipelined.v"

module RegFile (
  input      [        4:0] rd,
  input      [`REG_SIZE:0] rd_data,
  input      [        4:0] rs1,
  output reg [`REG_SIZE:0] rs1_data,
  input      [        4:0] rs2,
  output reg [`REG_SIZE:0] rs2_data,
  input                    clk,
  input                    we,
  input                    rst
);
    localparam NumRegs = 32;
    // Đổi tên 'rf' thành 'regs' để khớp với Testbench
    reg [`REG_SIZE:0] regs [0:NumRegs-1];
    integer i;

    // Synchronous Write
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < NumRegs; i = i + 1) regs[i] <= 32'd0;
        end else if (we && (rd != 5'd0)) begin
            regs[rd] <= rd_data;
        end
    end

    // Asynchronous Read
    always @(*) begin
        rs1_data = (rs1 == 0) ? 32'd0 : regs[rs1];
        rs2_data = (rs2 == 0) ? 32'd0 : regs[rs2];
    end
endmodule

module DatapathMultiCycle (
    input                    clk,
    input                    rst,
    output reg               halt,
    output     [`REG_SIZE:0] pc_to_imem,
    input      [`REG_SIZE:0] inst_from_imem,
    // addr_to_dmem is a read-write port
    output reg [`REG_SIZE:0] addr_to_dmem,
    input      [`REG_SIZE:0] load_data_from_dmem,
    output reg [`REG_SIZE:0] store_data_to_dmem,
    output reg [        3:0] store_we_to_dmem
);
    // --- 1. GIẢI MÃ LỆNH (DECODING) ---
    wire [6:0] inst_funct7;
    wire [4:0] inst_rs2, inst_rs1, inst_rd;
    wire [2:0] inst_funct3;
    wire [`OPCODE_SIZE:0] inst_opcode;

    assign {inst_funct7, inst_rs2, inst_rs1, inst_funct3, inst_rd, inst_opcode} = inst_from_imem;

    // Immediate Generation
    wire [11:0] imm_i = inst_from_imem[31:20];
    wire [11:0] imm_s = {inst_funct7, inst_rd};
    wire [12:0] imm_b = {inst_funct7[6], inst_rd[0], inst_funct7[5:0], inst_rd[4:1], 1'b0};
    wire [20:0] imm_j = {inst_from_imem[31], inst_from_imem[19:12], inst_from_imem[20], inst_from_imem[30:21], 1'b0};

    // Sign Extension
    wire [`REG_SIZE:0] imm_i_sext = {{20{imm_i[11]}}, imm_i};
    wire [`REG_SIZE:0] imm_s_sext = {{20{imm_s[11]}}, imm_s};
    wire [`REG_SIZE:0] imm_b_sext = {{19{imm_b[12]}}, imm_b};
    wire [`REG_SIZE:0] imm_j_sext = {{11{imm_j[20]}}, imm_j};
    wire [`REG_SIZE:0] imm_u_sext = {inst_from_imem[31:12], 12'b0}; 

    // Opcode Definitions
    localparam OpLoad = 7'b00_000_11, OpStore = 7'b01_000_11, OpBranch = 7'b11_000_11;
    localparam OpJalr = 7'b11_001_11, OpMiscMem = 7'b00_011_11, OpJal = 7'b11_011_11;
    localparam OpRegImm = 7'b00_100_11, OpRegReg = 7'b01_100_11, OpEnviron = 7'b11_100_11;
    localparam OpAuipc = 7'b00_101_11, OpLui = 7'b01_101_11;

    // Control Signals Mapping
    wire inst_lui    = (inst_opcode == OpLui);
    wire inst_auipc  = (inst_opcode == OpAuipc);
    wire inst_jal    = (inst_opcode == OpJal);
    wire inst_jalr   = (inst_opcode == OpJalr);
    wire inst_beq    = (inst_opcode == OpBranch) & (inst_funct3 == 3'b000);
    wire inst_bne    = (inst_opcode == OpBranch) & (inst_funct3 == 3'b001);
    wire inst_blt    = (inst_opcode == OpBranch) & (inst_funct3 == 3'b100);
    wire inst_bge    = (inst_opcode == OpBranch) & (inst_funct3 == 3'b101);
    wire inst_bltu   = (inst_opcode == OpBranch) & (inst_funct3 == 3'b110);
    wire inst_bgeu   = (inst_opcode == OpBranch) & (inst_funct3 == 3'b111);
    
    wire inst_lb     = (inst_opcode == OpLoad)   & (inst_funct3 == 3'b000);
    wire inst_lh     = (inst_opcode == OpLoad)   & (inst_funct3 == 3'b001);
    wire inst_lw     = (inst_opcode == OpLoad)   & (inst_funct3 == 3'b010);
    wire inst_lbu    = (inst_opcode == OpLoad)   & (inst_funct3 == 3'b100);
    wire inst_lhu    = (inst_opcode == OpLoad)   & (inst_funct3 == 3'b101);
    
    wire inst_sb     = (inst_opcode == OpStore)  & (inst_funct3 == 3'b000);
    wire inst_sh     = (inst_opcode == OpStore)  & (inst_funct3 == 3'b001);
    wire inst_sw     = (inst_opcode == OpStore)  & (inst_funct3 == 3'b010);
    
    wire inst_addi   = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b000);
    wire inst_slti   = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b010);
    wire inst_sltiu  = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b011);
    wire inst_xori   = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b100);
    wire inst_ori    = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b110);
    wire inst_andi   = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b111);
    wire inst_slli   = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b001);
    wire inst_srli   = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b101) & (inst_funct7 == 0);
    wire inst_srai   = (inst_opcode == OpRegImm) & (inst_funct3 == 3'b101) & (inst_funct7 == 7'b0100000);
    
    wire inst_add    = (inst_opcode == OpRegReg) & (inst_funct3 == 0) & (inst_funct7 == 0);
    wire inst_sub    = (inst_opcode == OpRegReg) & (inst_funct3 == 0) & (inst_funct7 == 7'b0100000);
    wire inst_sll    = (inst_opcode == OpRegReg) & (inst_funct3 == 1);
    wire inst_slt    = (inst_opcode == OpRegReg) & (inst_funct3 == 2);
    wire inst_sltu   = (inst_opcode == OpRegReg) & (inst_funct3 == 3);
    wire inst_xor    = (inst_opcode == OpRegReg) & (inst_funct3 == 4);
    wire inst_srl    = (inst_opcode == OpRegReg) & (inst_funct3 == 5) & (inst_funct7 == 0);
    wire inst_sra    = (inst_opcode == OpRegReg) & (inst_funct3 == 5) & (inst_funct7 == 7'b0100000);
    wire inst_or     = (inst_opcode == OpRegReg) & (inst_funct3 == 6);
    wire inst_and    = (inst_opcode == OpRegReg) & (inst_funct3 == 7);
    
    wire inst_mul    = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 0);
    wire inst_mulh   = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 1);
    wire inst_mulhsu = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 2);
    wire inst_mulhu  = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 3);
    
    // Nhóm lệnh chia
    wire inst_div    = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 4);
    wire inst_divu   = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 5);
    wire inst_rem    = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 6);
    wire inst_remu   = (inst_opcode == OpRegReg) & (inst_funct7 == 1) & (inst_funct3 == 7);
    
    wire inst_ecall  = (inst_opcode == OpEnviron) & (inst_from_imem[31:7] == 0);
    wire inst_fence  = (inst_opcode == OpMiscMem);

    // Dấu hiệu nhận biết phép chia
    wire is_div_op = inst_div | inst_divu | inst_rem | inst_remu;

    // --- 2. LOGIC COUNTER CHO STALL (MULTI-CYCLE CONTROL) ---
    reg [3:0] div_counter;
    
    always @(posedge clk) begin
        if (rst) begin
            div_counter <= 0;
        end else if (is_div_op) begin
            // Nếu đang là lệnh chia và chưa đếm đủ 8 (latency của divider), tăng counter
            if (div_counter < 8) div_counter <= div_counter + 1;
            else div_counter <= 0; // Đã xong, reset về 0 để đón lệnh tiếp theo
        end else begin
            div_counter <= 0;
        end
    end

    // =========================================================================
    // SỬA LỖI: Thêm Cycle Counters mà Testbench yêu cầu
    // =========================================================================
    reg [`REG_SIZE:0] cycles_current, num_inst_current;
    always @(posedge clk) begin
        if (rst) begin
            cycles_current <= 0;
            num_inst_current <= 0;
        end else begin
            cycles_current <= cycles_current + 1;
            if (!rst) num_inst_current <= num_inst_current + 1;
        end
    end
    // =========================================================================

    // --- 3. DÂY KẾT NỐI VÀ INSTANTIATE ---
    reg [`REG_SIZE:0] pcNext, pcCurrent;
    wire [`REG_SIZE:0] rs1_data, rs2_data;
    reg  [`REG_SIZE:0] rd_data_val;
    reg                rf_we_val;

    // Biến phụ trợ cho ALU
    reg [63:0] mul_temp_64;
    reg [7:0]  byte_tmp;
    reg [15:0] half_tmp;
    reg [31:0] div_dividend_abs, div_divisor_abs;
    wire [31:0] div_quot_u, div_rem_u;

    // PC Update
    always @(posedge clk) begin
        if (rst) pcCurrent <= 32'd0;
        else     pcCurrent <= pcNext;
    end
    assign pc_to_imem = pcCurrent;

    // Register File
    RegFile rf (
        .clk(clk), .rst(rst), .we(rf_we_val), .rd(inst_rd), 
        .rd_data(rd_data_val), .rs1(inst_rs1), .rs2(inst_rs2), 
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    // CLA Adder
    reg [31:0] cla_b; 
    reg cla_cin;
    wire [31:0] cla_sum;
    cla cla_inst (
        .a(rs1_data), .b(cla_b), .cin(cla_cin), .sum(cla_sum)
    );

    // --- PIPELINED DIVIDER INSTANTIATION ---
    DividerUnsignedPipelined div_inst (
        .clk(clk),
        .rst(rst),
        .stall(1'b0), 
        .i_dividend(div_dividend_abs),
        .i_divisor(div_divisor_abs),
        .o_remainder(div_rem_u),
        .o_quotient(div_quot_u)
    );

    // --- 4. MAIN LOGIC & STALL CONTROL ---
    reg illegal_inst;

    always @(*) begin
        // Defaults
        illegal_inst       = 0;
        halt               = 0;
        rf_we_val          = 0;
        rd_data_val        = 0;
        addr_to_dmem       = 0;
        store_data_to_dmem = 0;
        store_we_to_dmem   = 0;
        cla_b = 0; cla_cin = 0;
        div_dividend_abs = 0; div_divisor_abs = 0;
        mul_temp_64 = 0; byte_tmp = 0; half_tmp = 0;

        // Mặc định PC nhảy tới lệnh tiếp theo
        pcNext = pcCurrent + 4;

        // *** LOGIC STALL CHO PHÉP CHIA ***
        if (is_div_op) begin
            // Nếu counter chưa đếm đủ 8 (tức là 8 chu kỳ pipeline)
            if (div_counter < 8) begin
                pcNext = pcCurrent; // Freeze PC (Stall)
                rf_we_val = 0;      // Không ghi Register
            end else begin
                // Khi counter == 8, kết quả từ Divider đã sẵn sàng
                pcNext = pcCurrent + 4;
                rf_we_val = 1; 
                // (Dữ liệu rd_data_val sẽ được gán ở case bên dưới)
            end
        end

        // Xử lý Logic từng lệnh
        case (inst_opcode)
            OpLui: begin
                rd_data_val = imm_u_sext;
                rf_we_val = 1;
            end
            OpAuipc: begin
                rd_data_val = pcCurrent + imm_u_sext;
                rf_we_val = 1;
            end
            OpJal: begin
                rd_data_val = pcCurrent + 4;
                pcNext = pcCurrent + imm_j_sext;
                rf_we_val = 1;
            end
            OpJalr: begin
                rd_data_val = pcCurrent + 4;
                pcNext = (rs1_data + imm_i_sext) & ~32'd1;
                rf_we_val = 1;
            end
            OpBranch: begin
                if (inst_beq  && (rs1_data == rs2_data)) pcNext = pcCurrent + imm_b_sext;
                if (inst_bne  && (rs1_data != rs2_data)) pcNext = pcCurrent + imm_b_sext;
                if (inst_blt  && ($signed(rs1_data) < $signed(rs2_data))) pcNext = pcCurrent + imm_b_sext;
                if (inst_bge  && ($signed(rs1_data) >= $signed(rs2_data))) pcNext = pcCurrent + imm_b_sext;
                if (inst_bltu && (rs1_data < rs2_data))  pcNext = pcCurrent + imm_b_sext;
                if (inst_bgeu && (rs1_data >= rs2_data)) pcNext = pcCurrent + imm_b_sext;
            end
            OpLoad: begin
                addr_to_dmem = rs1_data + imm_i_sext;
                rf_we_val = 1;
                case (addr_to_dmem[1:0])
                    2'b00: byte_tmp = load_data_from_dmem[7:0];
                    2'b01: byte_tmp = load_data_from_dmem[15:8];
                    2'b10: byte_tmp = load_data_from_dmem[23:16];
                    2'b11: byte_tmp = load_data_from_dmem[31:24];
                endcase
                case (addr_to_dmem[1])
                    1'b0: half_tmp = load_data_from_dmem[15:0];
                    1'b1: half_tmp = load_data_from_dmem[31:16];
                endcase
                if (inst_lb)       rd_data_val = {{24{byte_tmp[7]}}, byte_tmp};
                else if (inst_lbu) rd_data_val = {24'b0, byte_tmp};
                else if (inst_lh)  rd_data_val = {{16{half_tmp[15]}}, half_tmp};
                else if (inst_lhu) rd_data_val = {16'b0, half_tmp};
                else if (inst_lw)  rd_data_val = load_data_from_dmem;
            end
            OpStore: begin
                addr_to_dmem = rs1_data + imm_s_sext;
                case (addr_to_dmem[1:0])
                    2'b00: store_data_to_dmem = rs2_data;
                    2'b01: store_data_to_dmem = rs2_data << 8;
                    2'b10: store_data_to_dmem = rs2_data << 16;
                    2'b11: store_data_to_dmem = rs2_data << 24;
                endcase
                if (inst_sb)      store_we_to_dmem = 4'b0001 << addr_to_dmem[1:0];
                else if (inst_sh) store_we_to_dmem = (addr_to_dmem[1] == 0) ? 4'b0011 : 4'b1100;
                else if (inst_sw) store_we_to_dmem = 4'b1111;
            end
            OpRegImm: begin
                rf_we_val = 1;
                if (inst_addi) begin cla_b = imm_i_sext; cla_cin = 0; rd_data_val = cla_sum; end
                else if (inst_slti)  rd_data_val = ($signed(rs1_data) < $signed(imm_i_sext)) ? 1 : 0;
                else if (inst_sltiu) rd_data_val = (rs1_data < imm_i_sext) ? 1 : 0;
                else if (inst_xori)  rd_data_val = rs1_data ^ imm_i_sext;
                else if (inst_ori)   rd_data_val = rs1_data | imm_i_sext;
                else if (inst_andi)  rd_data_val = rs1_data & imm_i_sext;
                else if (inst_slli)  rd_data_val = rs1_data << imm_i[4:0];
                else if (inst_srli)  rd_data_val = rs1_data >> imm_i[4:0];
                else if (inst_srai)  rd_data_val = $signed(rs1_data) >>> imm_i[4:0];
            end
            OpRegReg: begin
                rf_we_val = 1;
                if (inst_add) begin cla_b = rs2_data; cla_cin = 0; rd_data_val = cla_sum; end
                else if (inst_sub) begin cla_b = ~rs2_data; cla_cin = 1; rd_data_val = cla_sum; end
                else if (inst_mul || inst_mulh || inst_mulhsu || inst_mulhu) begin
                    if (inst_mul)         mul_temp_64 = rs1_data * rs2_data;
                    else if (inst_mulh)   mul_temp_64 = $signed(rs1_data) * $signed(rs2_data);
                    else if (inst_mulhsu) mul_temp_64 = $signed({{32{rs1_data[31]}}, rs1_data}) * $signed({32'b0, rs2_data});
                    else if (inst_mulhu)  mul_temp_64 = rs1_data * rs2_data;
                    rd_data_val = (inst_mul) ? mul_temp_64[31:0] : mul_temp_64[63:32];
                end
                // else if (is_div_op) begin
                //     // 1. Prepare Abs inputs for Divider
                //     if (inst_divu || inst_remu) begin
                //         div_dividend_abs = rs1_data; div_divisor_abs = rs2_data;
                //     end else begin
                //         div_dividend_abs = rs1_data[31] ? (~rs1_data + 1) : rs1_data;
                //         div_divisor_abs  = rs2_data[31] ? (~rs2_data + 1) : rs2_data;
                //     end
                    
                //     // 2. Select Output & Fix Sign
                //     // Kết quả div_quot_u chỉ được dùng khi div_counter >= 8 (hết stall)
                //     if (inst_divu) rd_data_val = div_quot_u;
                //     else if (inst_remu) rd_data_val = div_rem_u;
                //     else if (inst_div)  rd_data_val = (rs1_data[31] ^ rs2_data[31]) ? (~div_quot_u + 1) : div_quot_u;
                //     else if (inst_rem)  rd_data_val = (rs1_data[31]) ? (~div_rem_u + 1) : div_rem_u;
                // end


                else if (is_div_op) begin
                    // 1. Prepare Abs inputs for Divider
                    if (inst_divu || inst_remu) begin
                        div_dividend_abs = rs1_data; div_divisor_abs = rs2_data;
                    end else begin
                        div_dividend_abs = rs1_data[31] ? (~rs1_data + 1) : rs1_data;
                        div_divisor_abs  = rs2_data[31] ? (~rs2_data + 1) : rs2_data;
                    end
                    
                    // 2. Select Output & Fix Sign (Bao gồm Corner Cases)
                    // Kết quả div_quot_u chỉ được dùng khi div_counter >= 8 (hết stall)
                    
                    // --- Xử lý Corner Cases (Theo chuẩn RISC-V) ---
                    if (rs2_data == 32'd0) begin
                        // Case A: Chia cho 0
                        if (inst_div || inst_divu) rd_data_val = 32'hFFFFFFFF; // DIV/DIVU by 0 -> -1
                        else                       rd_data_val = rs1_data;     // REM/REMU by 0 -> Dividend
                    end 
                    else if ((inst_div || inst_rem) && (rs1_data == 32'h80000000) && (rs2_data == 32'hFFFFFFFF)) begin
                        // Case B: Signed Overflow (-2^31 / -1)
                        if (inst_div) rd_data_val = 32'h80000000; // Kết quả là -2^31
                        else          rd_data_val = 32'd0;        // Dư là 0
                    end 
                    else begin
                        // Case C: Normal Operation
                        if (inst_divu)      rd_data_val = div_quot_u;
                        else if (inst_remu) rd_data_val = div_rem_u;
                        else if (inst_div)  rd_data_val = (rs1_data[31] ^ rs2_data[31]) ? (~div_quot_u + 1) : div_quot_u;
                        else /*rem*/        rd_data_val = (rs1_data[31]) ? (~div_rem_u + 1) : div_rem_u;
                    end
                end







                else if (inst_sll)  rd_data_val = rs1_data << rs2_data[4:0];
                else if (inst_slt)  rd_data_val = ($signed(rs1_data) < $signed(rs2_data)) ? 1 : 0;
                else if (inst_sltu) rd_data_val = (rs1_data < rs2_data) ? 1 : 0;
                else if (inst_xor)  rd_data_val = rs1_data ^ rs2_data;
                else if (inst_srl)  rd_data_val = rs1_data >> rs2_data[4:0];
                else if (inst_sra)  rd_data_val = $signed(rs1_data) >>> rs2_data[4:0];
                else if (inst_or)   rd_data_val = rs1_data | rs2_data;
                else if (inst_and)  rd_data_val = rs1_data & rs2_data;
            end
            OpEnviron: begin
                if (inst_ecall) halt = 1;
            end
            default: illegal_inst = 1;
        endcase
    end
endmodule

module MemorySingleCycle #(
    parameter NUM_WORDS = 512
) (
  input                    rst,                 // rst for both imem and dmem
  input                    clock_mem,           // clock for both imem and dmem
  input      [`REG_SIZE:0] pc_to_imem,          // must always be aligned to a 4B boundary
  output reg [`REG_SIZE:0] inst_from_imem,      // the value at memory location pc_to_imem
  input      [`REG_SIZE:0] addr_to_dmem,        // must always be aligned to a 4B boundary
  output reg [`REG_SIZE:0] load_data_from_dmem, // the value at memory location addr_to_dmem
  input      [`REG_SIZE:0] store_data_to_dmem,  // the value to be written to addr_to_dmem, controlled by store_we_to_dmem
  // Each bit determines whether to write the corresponding byte of store_data_to_dmem to memory location addr_to_dmem.
  // E.g., 4'b1111 will write 4 bytes. 4'b0001 will write only the least-significant byte.
  input      [        3:0] store_we_to_dmem
);
  // memory is arranged as an array of 4B words
  reg [`REG_SIZE:0] mem_array[0:NUM_WORDS-1];
  // preload instructions to mem_array
  initial begin
    $readmemh("mem_initial_contents.hex", mem_array);
  end

  localparam AddrMsb = $clog2(NUM_WORDS) + 1;
  localparam AddrLsb = 2;
  always @(posedge clock_mem) begin
    inst_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
  end

  always @(negedge clock_mem) begin
    if (store_we_to_dmem[0]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
    end
    if (store_we_to_dmem[1]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
    end
    if (store_we_to_dmem[2]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
    end
    if (store_we_to_dmem[3]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
    end
    // dmem is "read-first": read returns value before the write
    load_data_from_dmem <= mem_array[{addr_to_dmem[AddrMsb:AddrLsb]}];
  end
endmodule

module Processor (
    input  clock_proc,
    input  clock_mem,
    input  rst,
    output halt
);
  wire [`REG_SIZE:0] pc_to_imem, inst_from_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
  wire [        3:0] mem_data_we;
  // This wire is set by cocotb to the name of the currently-running test, to make it easier
  // to see what is going on in the waveforms.
  wire [(8*32)-1:0] test_case;

  MemorySingleCycle #(
      .NUM_WORDS(8192)
  ) memory (
    .rst                 (rst),
    .clock_mem           (clock_mem),
    // imem is read-only
    .pc_to_imem          (pc_to_imem),
    .inst_from_imem      (inst_from_imem),
    // dmem is read-write
    .addr_to_dmem        (mem_data_addr),
    .load_data_from_dmem (mem_data_loaded_value),
    .store_data_to_dmem  (mem_data_to_write),
    .store_we_to_dmem    (mem_data_we)
  );
  DatapathMultiCycle datapath (
    .clk                 (clock_proc),
    .rst                 (rst),
    .pc_to_imem          (pc_to_imem),
    .inst_from_imem      (inst_from_imem),
    .addr_to_dmem        (mem_data_addr),
    .store_data_to_dmem  (mem_data_to_write),
    .store_we_to_dmem    (mem_data_we),
    .load_data_from_dmem (mem_data_loaded_value),
    .halt                (halt)
  );
endmodule