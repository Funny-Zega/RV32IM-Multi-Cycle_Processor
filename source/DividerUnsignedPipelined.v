`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/08/2025 10:09:21 PM
// Design Name: 
// Module Name: DividerUnsignedPipelined
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// -------------------------------------------------------------------------
// MODULE CHÍNH: DIVIDER 8 TẦNG PIPELINE
// -------------------------------------------------------------------------
module DividerUnsignedPipelined (
    input  wire        clk, 
    input  wire        rst,
    input  wire        stall,  // Đã thêm xử lý Stall
    input  wire [31:0] i_dividend,
    input  wire [31:0] i_divisor,
    output wire [31:0] o_remainder,
    output wire [31:0] o_quotient
);

    // Mảng dây nối giữa các tầng (Wiring)
    // chain_div[0] là Input, chain_div[1] là Output của Stage 1,...
    wire [31:0] chain_dividend  [0:8];
    wire [31:0] chain_remainder [0:8];
    wire [31:0] chain_quotient  [0:8];
    wire [31:0] chain_divisor   [0:8];

    // Gán tín hiệu đầu vào cho chuỗi dây (Stage 0)
    assign chain_dividend[0]  = i_dividend;
    assign chain_divisor[0]   = i_divisor;
    assign chain_remainder[0] = 32'd0;
    assign chain_quotient[0]  = 32'd0;

    // Sinh ra 8 tầng Pipeline (Stage 1 -> Stage 8)
    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : PIPELINE_STAGES
            // Gọi module con "DividerStage" thay vì viết loop lồng
            DividerStage stage_inst (
                .clk      (clk),
                .rst      (rst),
                .stall    (stall),
                
                // Input từ mắc xích trước (k)
                .i_div    (chain_dividend[k]),
                .i_rem    (chain_remainder[k]),
                .i_quo    (chain_quotient[k]),
                .i_dvs    (chain_divisor[k]),
                
                // Output sang mắc xích sau (k+1)
                .o_div    (chain_dividend[k+1]),
                .o_rem    (chain_remainder[k+1]),
                .o_quo    (chain_quotient[k+1]),
                .o_dvs    (chain_divisor[k+1])
            );
        end
    endgenerate

    // Lấy kết quả cuối cùng từ dây số 8
    assign o_quotient  = chain_quotient[8];
    assign o_remainder = chain_remainder[8];

endmodule

// -------------------------------------------------------------------------
// MODULE CON: 1 TẦNG PIPELINE (Chứa 4 Iterations + 1 Thanh ghi)
// -------------------------------------------------------------------------
module DividerStage (
    input  wire        clk, rst, stall,
    input  wire [31:0] i_div, i_rem, i_quo, i_dvs,
    output reg  [31:0] o_div, o_rem, o_quo, o_dvs
);
    // Dây nối nội bộ cho 4 phép chia (Combinational logic wires)
    wire [31:0] t_div [0:4];
    wire [31:0] t_rem [0:4];
    wire [31:0] t_quo [0:4];

    // Gán đầu vào cho chuỗi logic
    assign t_div[0] = i_div;
    assign t_rem[0] = i_rem;
    assign t_quo[0] = i_quo;

    // Thực hiện 4 phép chia liên tiếp (Combinational Loop)
    genvar m;
    generate
        for (m = 0; m < 4; m = m + 1) begin : CLUSTER_4_ITERS
            divu_1iter unit (
                .i_dividend (t_div[m]),
                .i_divisor  (i_dvs),        // Divisor không đổi trong 1 stage
                .i_remainder(t_rem[m]),
                .i_quotient (t_quo[m]),
                
                .o_dividend (t_div[m+1]),
                .o_remainder(t_rem[m+1]),
                .o_quotient (t_quo[m+1])
            );
        end
    endgenerate

    // Cập nhật Thanh ghi (Sequential Logic)
    always @(posedge clk) begin
        if (rst) begin
            // Reset toàn bộ về 0
            o_div <= 32'd0;
            o_rem <= 32'd0;
            o_quo <= 32'd0;
            o_dvs <= 32'd0; 
        end else if (!stall) begin 
            // Nếu KHÔNG Stall thì mới cập nhật dữ liệu mới
            // Lấy kết quả từ bước thứ 4 (t_...[4]) lưu vào thanh ghi
            o_div <= t_div[4];
            o_rem <= t_rem[4];
            o_quo <= t_quo[4];
            o_dvs <= i_dvs; // Truyền Divisor sang tầng sau
        end
        // Nếu Stall = 1, giữ nguyên giá trị cũ (implicit latch)
    end

endmodule

// -------------------------------------------------------------------------
// MODULE CƠ SỞ: 1 ITERATION (Giữ nguyên logic Code 4 nhưng viết gọn lại)
// -------------------------------------------------------------------------
module divu_1iter (
   input  wire [31:0] i_dividend,
   input  wire [31:0] i_divisor,
   input  wire [31:0] i_remainder,
   input  wire [31:0] i_quotient,
   output wire [31:0] o_dividend,
   output wire [31:0] o_remainder,
   output wire [31:0] o_quotient       
);
    // Logic dịch bit và ghép bit (Concatenation & Shift)
    // Tương đương: (rem << 1) | MSB(dividend)
    wire [32:0] remainder_next;
    assign remainder_next = {i_remainder[30:0], i_dividend[31], 1'b0} >> 1; 
    // Mẹo: Code trên tương đương {i_remainder, i_dividend[31]} nếu i_remainder đủ rộng.
    // Viết theo kiểu Code 4 để an toàn nhất:
    wire [32:0] rem_shifted_safe;
    assign rem_shifted_safe = {1'b0, i_remainder} << 1;
    
    wire [32:0] rem_with_bit;
    assign rem_with_bit = rem_shifted_safe | {32'd0, i_dividend[31]};

    // Logic Trừ (Subtraction)
    wire [32:0] diff;
    assign diff = rem_with_bit - {1'b0, i_divisor};

    // Logic So sánh (Condition)
    wire condition;
    assign condition = (rem_with_bit >= {1'b0, i_divisor});

    // Output Mux
    assign o_remainder = condition ? diff[31:0] : rem_with_bit[31:0];
    assign o_quotient  = (i_quotient << 1) | {31'b0, condition};
    assign o_dividend  = i_dividend << 1;

endmodule












// `timescale 1ns / 1ns

// // quotient = dividend / divisor

// module DividerUnsignedPipelined (
//     input             clk, rst, stall,
//     input      [31:0] i_dividend,
//     input      [31:0] i_divisor,
//     output reg [31:0] o_remainder,
//     output reg [31:0] o_quotient
// );
//     // --- KHAI BÁO DÂY NỐI PIPELINE (Internal Wires) ---
//     // Mảng dây nối giữa các tầng: 8 tầng -> cần index 0 đến 8
//     wire [31:0] chain_dividend  [0:8];
//     wire [31:0] chain_remainder [0:8];
//     wire [31:0] chain_quotient  [0:8];
//     wire [31:0] chain_divisor   [0:8];

//     // --- GÁN INPUT VÀO ĐẦU CHUỖI (Stage 0) ---
//     assign chain_dividend[0]  = i_dividend;
//     assign chain_divisor[0]   = i_divisor;
//     assign chain_remainder[0] = 32'd0;
//     assign chain_quotient[0]  = 32'd0;

//     // --- SINH RA 8 TẦNG PIPELINE (Stage 1 -> 8) ---
//     genvar k;
//     generate
//         for (k = 0; k < 8; k = k + 1) begin : PIPELINE_STAGES
//             DividerStage stage_inst (
//                 .clk      (clk),
//                 .rst      (rst),
//                 .stall    (stall),
                
//                 // Input từ tầng trước (k)
//                 .i_div    (chain_dividend[k]),
//                 .i_rem    (chain_remainder[k]),
//                 .i_quo    (chain_quotient[k]),
//                 .i_dvs    (chain_divisor[k]),
                
//                 // Output sang tầng sau (k+1)
//                 .o_div    (chain_dividend[k+1]),
//                 .o_rem    (chain_remainder[k+1]),
//                 .o_quo    (chain_quotient[k+1]),
//                 .o_dvs    (chain_divisor[k+1])
//             );
//         end
//     endgenerate

//     // --- GÁN OUTPUT CUỐI CÙNG (Stage 8) ---
//     // Vì output là 'reg', ta dùng always block thay vì assign
//     always @(*) begin
//         o_quotient  = chain_quotient[8];
//         o_remainder = chain_remainder[8];
//     end

// endmodule


// module divu_1iter (
//     input      [31:0] i_dividend,
//     input      [31:0] i_divisor,
//     input      [31:0] i_remainder,
//     input      [31:0] i_quotient,
//     output reg [31:0] o_dividend,
//     output reg [31:0] o_remainder,
//     output reg [31:0] o_quotient
// );
//     // Logic tổ hợp cho 1 bước chia
//     // Vì output là 'reg', ta phải thực hiện tính toán trong always @(*)
//     always @(*) begin
//         // 1. Shift Remainder left 1, bring in MSB of Dividend
//         // Logic tương đương: {i_remainder[30:0], i_dividend[31]}
//         // Sử dụng biến tạm để code rõ ràng hơn
//         reg [31:0] remainder_next;
//         reg [31:0] diff;
//         reg        condition; // 1 nếu Rem >= Div
        
//         remainder_next = (i_remainder << 1) | ((i_dividend >> 31) & 1);
        
//         // 2. Compare & Subtract
//         if (remainder_next >= i_divisor) begin
//             condition = 1'b1;
//             diff = remainder_next - i_divisor;
//         end else begin
//             condition = 1'b0;
//             diff = remainder_next; // Không quan trọng, vì mux sẽ chọn cái khác
//         end

//         // 3. Update Outputs
//         o_remainder = condition ? diff : remainder_next;
//         o_quotient  = (i_quotient << 1) | {31'b0, condition};
//         o_dividend  = i_dividend << 1;
//     end

// endmodule


// // -------------------------------------------------------------------------
// // MODULE PHỤ TRỢ: 1 TẦNG PIPELINE (Helper Module)
// // Module này không có trong file gốc nhưng cần thiết cho cấu trúc của bạn.
// // Verilog cho phép định nghĩa thêm module trong cùng file.
// // -------------------------------------------------------------------------
// module DividerStage (
//     input  wire        clk, rst, stall,
//     input  wire [31:0] i_div, i_rem, i_quo, i_dvs,
//     output reg  [31:0] o_div, o_rem, o_quo, o_dvs
// );
//     // Dây nối nội bộ cho 4 phép chia liên tiếp (Combinational Chain)
//     wire [31:0] t_div [0:4];
//     wire [31:0] t_rem [0:4];
//     wire [31:0] t_quo [0:4];

//     // Gán đầu vào
//     assign t_div[0] = i_div;
//     assign t_rem[0] = i_rem;
//     assign t_quo[0] = i_quo;

//     // Thực hiện 4 phép chia (4 Iterations)
//     genvar m;
//     generate
//         for (m = 0; m < 4; m = m + 1) begin : CLUSTER_ITERS
//             divu_1iter unit (
//                 .i_dividend (t_div[m]),
//                 .i_divisor  (i_dvs),        // Divisor giữ nguyên
//                 .i_remainder(t_rem[m]),
//                 .i_quotient (t_quo[m]),
                
//                 .o_dividend (t_div[m+1]),
//                 .o_remainder(t_rem[m+1]),
//                 .o_quotient (t_quo[m+1])
//             );
//         end
//     endgenerate

//     // Pipeline Register (Cập nhật kết quả sau 4 iters vào Flip-Flop)
//     always @(posedge clk) begin
//         if (rst) begin
//             o_div <= 32'd0;
//             o_rem <= 32'd0;
//             o_quo <= 32'd0;
//             o_dvs <= 32'd0; 
//         end else if (!stall) begin 
//             // Chỉ cập nhật khi không Stall
//             o_div <= t_div[4];
//             o_rem <= t_rem[4];
//             o_quo <= t_quo[4];
//             o_dvs <= i_dvs; // Chuyển tiếp Divisor
//         end
//         // Nếu Stall, giữ nguyên giá trị cũ
//     end

// endmodule