`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/08/2025 12:53:49 PM
// Design Name: 
// Module Name: cla
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

/**
 * @param a first 1-bit input
 * @param b second 1-bit input
 * @param g whether a and b generate a carry
 * @param p whether a and b would propagate an incoming carry
 */
module gp1(input wire a, b,
           output wire g, p);
    assign g = a & b;
    assign p = a | b; // Lưu ý: Một số sách dùng XOR, nhưng đề bài dùng OR (vẫn đúng cho CLA)
endmodule

/**
 * Computes aggregate generate/propagate signals over a 4-bit window.
 * @param gin incoming generate signals
 * @param pin incoming propagate signals
 * @param cin the incoming carry
 * @param gout whether these 4 bits internally would generate a carry-out (independent of cin)
 * @param pout whether these 4 bits internally would propagate an incoming carry from cin
 * @param cout the carry outs for the low-order 3 bits (C1, C2, C3)
 */
module gp4(input wire [3:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [2:0] cout);

    // 1. Group Propagate: Tất cả các bit đều phải truyền nhớ thì nhóm mới truyền nhớ
    // P_group = p3 & p2 & p1 & p0
    assign pout = &pin;

    // 2. Group Generate: Tạo nhớ ở bit cao nhất, hoặc tạo ở thấp hơn và truyền lên
    // G_group = g3 | (p3 & g2) | (p3 & p2 & g1) | (p3 & p2 & p1 & g0)
    assign gout = gin[3] | (pin[3] & gin[2]) | (pin[3] & pin[2] & gin[1]) | (pin[3] & pin[2] & pin[1] & gin[0]);

    // 3. Internal Carries Calculation (Tính toán carry nội bộ)
    // C1 = g0 | (p0 & cin)
    assign cout[0] = gin[0] | (pin[0] & cin);
    
    // C2 = g1 | (p1 & g0) | (p1 & p0 & cin)
    assign cout[1] = gin[1] | (pin[1] & gin[0]) | (pin[1] & pin[0] & cin);
    
    // C3 = g2 | (p2 & g1) | (p2 & p1 & g0) | (p2 & p1 & p0 & cin)
    assign cout[2] = gin[2] | (pin[2] & gin[1]) | (pin[2] & pin[1] & gin[0]) | (pin[2] & pin[1] & pin[0] & cin);

endmodule

/** Same as gp4 but for an 8-bit window instead 
 * Chiến lược: Dùng 2 module gp4 ghép lại để tạo thành gp8 (Hierarchical)
 */
module gp8(input wire [7:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [6:0] cout);

    wire g_low, p_low;   // G, P của 4 bit thấp [3:0]
    wire g_high, p_high; // G, P của 4 bit cao [7:4]
    wire c_mid;          // Carry ở giữa (từ bit 3 sang bit 4, tức là C4)
    wire [2:0] c_low_internal;
    wire [2:0] c_high_internal;

    // Instance cho 4 bit thấp [3:0]
    gp4 low_nibble (
        .gin(gin[3:0]), 
        .pin(pin[3:0]), 
        .cin(cin),
        .gout(g_low), 
        .pout(p_low), 
        .cout(c_low_internal)
    );

    // Tính carry truyền sang 4 bit cao (C4)
    // C4 = G_low | (P_low & Cin)
    assign c_mid = g_low | (p_low & cin);

    // Instance cho 4 bit cao [7:4]
    gp4 high_nibble (
        .gin(gin[7:4]), 
        .pin(pin[7:4]), 
        .cin(c_mid), // Đầu vào là C4 vừa tính
        .gout(g_high), 
        .pout(p_high), 
        .cout(c_high_internal)
    );

    // Tổng hợp đầu ra cho gp8
    assign pout = p_high & p_low;
    assign gout = g_high | (p_high & g_low);

    // Gom tất cả các carry nội bộ lại: 
    // {Carry bit 7..5, Carry bit 4, Carry bit 3..1}
    // Lưu ý: gp4 output cout là [2:0] (tương ứng C1, C2, C3 local).
    // cout của gp8 cần trả về [6:0] tương ứng C1 đến C7.
    assign cout = {c_high_internal, c_mid, c_low_internal};

endmodule

module cla
  (input wire [31:0]  a, b,
   input wire         cin,
   output wire [31:0] sum);

    // Mạng dây kết nối
    wire [31:0] g_bits;    // Generate từng bit
    wire [31:0] p_bits;    // Propagate từng bit
    
    wire [7:0]  g_groups;  // Generate của 8 nhóm (mỗi nhóm 4 bit)
    wire [7:0]  p_groups;  // Propagate của 8 nhóm
    
    wire [6:0]  c_groups;  // Carry giữa các nhóm (output từ gp8 trùm)
    
    // Wire chứa toàn bộ carry cho 32 bit (để tính Sum)
    // C_full[0] sẽ nối với cin của bit 0 (global cin)
    // C_full[1] nối với bit 1, v.v...
    wire [31:0] carry_full; 

    // --- Tầng 1: Tính g, p cho từng bit (32 instances) ---
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gp1_gen
            gp1 bit_level (
                .a(a[i]), 
                .b(b[i]), 
                .g(g_bits[i]), 
                .p(p_bits[i])
            );
        end
    endgenerate

    // --- Tầng 3: Lookahead Unit trung tâm (Dùng gp8) ---
    // Mặc dù tên là gp8, ta dùng nó để xử lý cho 8 nhóm (mỗi nhóm 4 bit) => phủ hết 32 bit
    // Input là vector g_groups và p_groups lấy từ output của tầng 2
    wire g_super, p_super; // Không dùng đến output g/p tổng của 32 bit trong bài này
    
    gp8 central_lookahead (
        .gin(g_groups), 
        .pin(p_groups), 
        .cin(cin),          // Global Carry In
        .gout(g_super), 
        .pout(p_super), 
        .cout(c_groups)     // Đây là các carry C4, C8, C12, ..., C28
    );

    // --- Tầng 2 & Tính Sum: 8 nhóm gp4 ---
    // Chúng ta cần kết nối carry từ "central_lookahead" vào từng nhóm gp4
    // Và lấy carry nội bộ của từng nhóm để tính Sum.
    
    wire [2:0] internal_couts [7:0]; // Mảng dây để chứa output cout của từng nhóm gp4

    generate
        for (i = 0; i < 8; i = i + 1) begin : gp4_groups
            // Xác định carry đầu vào cho nhóm này
            // Nhóm 0 (bit 0-3) nhận cin global
            // Nhóm 1 (bit 4-7) nhận c_groups[0] (tức C4)
            // ...
            wire cin_group;
            assign cin_group = (i == 0) ? cin : c_groups[i-1];

            gp4 group_level (
                .gin(g_bits[4*i+3 : 4*i]), 
                .pin(p_bits[4*i+3 : 4*i]), 
                .cin(cin_group), 
                .gout(g_groups[i]), 
                .pout(p_groups[i]), 
                .cout(internal_couts[i])
            );
            
            // --- Tính Sum cho 4 bit trong nhóm này ---
            // Sum = A ^ B ^ Cin. 
            // Lưu ý: A ^ B chính là output của XOR gate, nhưng gp1 của ta dùng OR.
            // Tuy nhiên, để đúng chuẩn bộ cộng, Sum = a ^ b ^ c.
            
            // Xây dựng vector carry cục bộ cho 4 bit này:
            // bit 0 nhận cin_group
            // bit 1 nhận internal_couts[0]
            // bit 2 nhận internal_couts[1]
            // bit 3 nhận internal_couts[2]
            wire [3:0] c_local;
            assign c_local = {internal_couts[i], cin_group};
            
            // Thực hiện phép XOR cho từng bit trong nhóm
            assign sum[4*i]   = a[4*i]   ^ b[4*i]   ^ c_local[0];
            assign sum[4*i+1] = a[4*i+1] ^ b[4*i+1] ^ c_local[1];
            assign sum[4*i+2] = a[4*i+2] ^ b[4*i+2] ^ c_local[2];
            assign sum[4*i+3] = a[4*i+3] ^ b[4*i+3] ^ c_local[3];
        end
    endgenerate

endmodule