`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12.10.2026 18:05:23
// Design Name: 
// Module Name: cic_top
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
// this is a low pass filter with CIC 512 and a FIR with 4 decimator respectively

module cic_top #(
    parameter OUT_WIDTH = 38                // = TB's cicout[37:0]
)(
    input  wire clk,
    input  wire reset,
    input  wire enable,
    input  wire signed [1:0] din,
    output wire signed [OUT_WIDTH-1:0] dout,
    output wire outready
);

   
    reg signed [1:0] din_r;
    always @(negedge clk) din_r <= din;

    wire signed [29:0] cic_out;             
    wire               cic_valid;           
    wire signed [19:0] fir_out;             // final result, 20 bits

    cic_core #(.STAGES(5), .DECIMATION(512)) u_cic (
        .clk(clk), .reset(reset), .enable(enable),
        .din(din_r),
        .dout(cic_out), .outready(cic_valid)
    );

    fir_comp u_fir (
        .clk(clk), .reset(reset), .enable(enable),
        .din(cic_out), .in_valid(cic_valid),
        .dout(fir_out), .out_valid(outready)
    );

    assign dout = fir_out;                  // sign-extends 20 -> 38 bits

endmodule



//  CIC decimator (512)

module cic_core #(
    parameter STAGES     = 5,
    parameter DECIMATION = 512,
    parameter IN_WIDTH   = 2,
    parameter M          = 1,
    parameter OUT_BITS   = 30
)(
    input  wire clk,
    input  wire reset,
    input  wire enable,
    input  wire signed [IN_WIDTH-1:0] din,
    output reg  signed [OUT_BITS-1:0] dout,
    output reg  outready
);

    // Hogenauer: N*log2(R*M) + Bin = 5(9)+2=47..
    localparam WIDTH = STAGES*$clog2(DECIMATION*M) + IN_WIDTH;

    // 1.INTEGRATOR (block1)
    reg signed [WIDTH-1:0] integrator [0:STAGES-1];
    integer i;

    always @(posedge clk) begin
        if (reset) begin
            for(i=0;i<STAGES;i=i+1)
                integrator[i]<=0;
        end
        else if (enable) begin
            integrator[0]<=integrator[0]+din;
            for (i=1;i<STAGES;i=i+1)
                integrator[i]<=integrator[i]+integrator[i-1];
        end
        end

    // 2.DECIMATOR COUNTER  (block2)
    reg [$clog2(DECIMATION)-1:0] count;
    wire sample_out=(count==DECIMATION-1);

    always @(posedge clk) begin
        if (reset)
            count<=0;
        else if (enable) begin
            if (sample_out) count <=0;
            else            count <= count+1'b1;
        end
        end

    // 3.COMBS (block3) 
    reg signed [WIDTH-1:0] comb_delay [0:STAGES-1];
    reg signed [WIDTH-1:0] comb_value [0:STAGES];
    integer j, k;

    always @(*) begin
        comb_value[0]=integrator[STAGES-1];
        for (j=0;j<STAGES;j=j+1)
            comb_value[j+1]=comb_value[j]-comb_delay[j];
        end

    always @(posedge clk) begin
        if (reset) begin
            for (k=0; k<STAGES;k=k+1)
                comb_delay[k]<= 0;
        end
        else if (enable && sample_out) begin
            for (k=0;k<STAGES;k=k+1)
                comb_delay[k]<=comb_value[k];
            end
    end

    // 4. OUTPUT (block4)
    
    always @(posedge clk) begin
        if (reset) begin
            dout<=0;
            outready<=0;
        end
        else begin
            outready<=0;
            if (enable && sample_out) begin
                dout<=comb_value[STAGES][WIDTH-2-:OUT_BITS];
                outready<=1;
            end
        end
        end

endmodule



//  FIR Decimator 4x

module fir_comp (
    input  wire clk,
    input  wire reset,
    input  wire enable,
    input  wire signed [29:0] din,
    input  wire in_valid,
 
    output reg  signed [19:0] dout,
    output reg  out_valid
);
 
    localparam TAPS = 25;
    // coefficients (Q16) - constant ROM, synthesizable for FPGA and ASIC
    function signed [17:0] h;
        input integer k;
        case (k)
             0: h =   1205;     1: h =   4680;     2: h =  10299;     3: h =  16316;
             4: h =  19548;     5: h =  17402;     6: h =   9848;     7: h =     76;
             8: h =  -7217;     9: h =  -8754;    10: h =  -4815;    11: h =   1126;
            12: h =   4933;    13: h =   4620;    14: h =   1330;    15: h =  -2021;
            16: h =  -3134;    17: h =  -1816;    18: h =    363;    19: h =   1646;
            20: h =   1415;    21: h =    315;    22: h =   -601;    23: h =   -790;
            24: h =   -438;
            default: h = 0;
        endcase
    endfunction
    reg signed [29:0] x [0:TAPS-1];
    reg [1:0] count;
 
    
    reg signed [51:0] sum;
    integer n;
 
    always @(*) begin
        sum = 0;
        for (n = 0; n < TAPS; n = n + 1)
            sum = sum + h(n) * x[n];
    end
 
    integer m;
 
    always @(posedge clk) begin
        if (reset) begin
            for (m=0;m<TAPS;m=m+1)
                x[m]<=0;
            count<=0;
            dout<=0;
            out_valid<=0;
        end
        else begin
            out_valid <= 0;
 
            if (enable && in_valid) begin
                x[0] <= din;
                for (m=1;m<TAPS;m=m+1)
                    x[m]<=x[m-1];
                if (count==3) begin
                    count<=0;
                    dout <=sum[44:25];
                    out_valid <= 1;
                end
                else
                    count<=count+1'b1;
            end
        end
    end
 
endmodule
 