/*
Copyright (c) 2018 Princeton University
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Princeton University nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

module ao486_l15_tri(   
    input clk,
    input rst_n,

    //Outputs dealing with L.15 and transducer (transducer -> L1.5)

    output [4:0]   transducer_l15_rqtype,
    output [39:0]  transducer_l15_address,
    output [63:0]  transducer_l15_data,
    output [63:0]  transducer_l15_data_next_entry,
    output         transducer_l15_req_ack,
    output         transducer_l15_val,
    output [2:0]   transducer_l15_size,
    output [3:0]   transducer_l15_amo_op,
    output         transducer_l15_nc,
    output [1:0]   transducer_l15_l1rplway,
    output         transducer_l15_blockinitstore,
    output         transducer_l15_blockstore,
    output [32:0]  transducer_l15_csm_data,
    output         transducer_l15_invalidate_cacheline,
    output         transducer_l15_prefetch,
    output         transducer_l15_threadid,
        
    //Inputs dealing with L1.5 and transducer (L1.5 -> transducer)

    input          l15_transducer_ack,
    input          l15_transducer_noncacheable,
    input          l15_transducer_atomic,
    input [63:0]   l15_transducer_data_0,
    input [63:0]   l15_transducer_data_1,
    input [63:0]   l15_transducer_data_2,
    input [63:0]   l15_transducer_data_3,
    input          l15_transducer_header_ack,                         
    input [3:0]    l15_transducer_returntype,
    input          l15_transducer_val,

    //Inputs dealing with transducer and core (core -> transducer)

    input          ao486_transducer_ifill_req_readcode_do,
    input [31:0]   ao486_transducer_ifill_req_readcode_address,

    input          ao486_transducer_store_req_writeburst_do,
    input [31:0]   ao486_transducer_store_req_writeburst_address,
    input [1:0]    ao486_transducer_store_req_writeburst_dword_length,
    input [55:0]   ao486_transducer_store_req_writeburst_data,
    input [3:0]    ao486_transducer_store_req_writeburst_length,

    input          ao486_transducer_load_req_readburst_do,
    input [31:0]   ao486_transducer_load_req_readburst_address,
    input [3:0]    ao486_transducer_load_req_readburst_byte_length,

    //Outpts from transducer to core

    output [31:0]  transducer_ao486_readcode_partial,
    output [127:0] transducer_ao486_readcode_line,
    output         transducer_ao486_request_readcode_done,
    output         transducer_ao486_readcode_partial_done,

    output         transducer_ao486_writeburst_done,

    output         transducer_ao486_readburst_done,
    output [95:0]  transducer_ao486_readburst_data,

    output         ao486_int
);

//Tying off all outputs not being generated
    assign transducer_l15_data_next_entry = 64'b0;
    assign transducer_l15_amo_op = 4'd0;
    assign transducer_l15_l1rplway = 2'd0;
    
//Tying off unused transducer_l15_ signals for ao486 to zero
    assign transducer_l15_blockinitstore = 1'b0;
    assign transducer_l15_blockstore = 1'b0;
    assign transducer_l15_csm_data = 33'd0;
    assign transducer_l15_invalidate_cacheline = 1'b0;
    assign transducer_l15_prefetch = 1'b0;
    assign transducer_l15_threadid = 1'b0;
//..........................................................................

//Parameters and reg variables
localparam IDLE  = 3'b000;
localparam NEW   = 3'b001;
localparam BUSY  = 3'b010;
localparam STORE = 3'b100;
localparam LOAD  = 3'b011;
localparam IFILL = 3'b101;
localparam ALIGNED_STORE = 2'b0;
localparam UNALIGNED_STORE = 2'b11;
localparam START_LOAD = 2'b00;
localparam WAITLOOP_LOAD = 2'b10;
localparam END_LOAD = 2'b01;
localparam IDLE_LOAD = 2'b11;

reg [2:0] state_reg;                   //Current state of processor <-> OP interface
reg [2:0] next_state;              //Next state of processor <-> OP interface
reg [2:0] req_type;                //Meant for READ/WRITE requests 
reg [31:0] addr_reg;               //Reg to store address received from ao486 (ao486_transducer_ifill_req_readcode_address)
reg flop_bus;
reg int_recv;
reg ao486_int_reg;
reg [31:0] transducer_l15_address_reg_ifill;
reg [4:0] transducer_l15_rqtype_reg;
reg transducer_l15_val_reg;
reg transducer_l15_val_next_reg;
reg transducer_l15_req_ack_reg;
reg [3:0] returntype_reg;
reg request_readcode_done_reg;
reg [31:0] readcode_partial_reg;
reg [127:0] readcode_line_reg;
reg ifill_response;
reg toggle_ifill_partial;
reg [1:0] counter_state_ifill_partial;
reg continue_ifill_count;
reg readcode_done_reg;
reg readcode_partial_done_reg;
reg [3:0] request_size;
reg [2:0] transducer_l15_req_size_reg;
reg double_access;
reg [31:0] ifill_double_access_first_address;
reg [31:0] ifill_double_access_second_address;
reg [1:0] double_access_count;
reg second_ifill_access_done;
reg first_ifill_access_done;
reg double_access_ifill_done;
reg [511:0] l15_transducer_data_vector_ifill;
reg [7:0] ifill_index;
reg [1:0] ifill_index_counter;
reg reset_ifill_index_counter;
reg ifill_response_received;
reg interrupt_received;

reg flop_bus_store;
reg [31:0] addr_reg_store;
reg [55:0] writeburst_data_reg;
reg [2:0] writeburst_length_reg;
reg new_store_req;
reg [1:0] number_of_store_requests;
reg [1:0] alignment_store;
reg single_store;
reg double_store;
reg triple_store;
reg [63:0] transducer_l15_data_reg;
reg store_response_received;
reg [39:0] transducer_l15_address_reg_store;
reg [2:0] next_state_store;
reg writeburst_done_reg;
reg [2:0] store_length_1;
reg [2:0] store_length_2;
reg [2:0] store_length_3;
reg [31:0] store_address_1;
reg [31:0] store_address_2;
reg [31:0] store_address_3;
reg first_store_ack;
reg second_store_ack;
reg third_store_ack;
reg third_store_header;
reg [2:0] req_type_store;
reg [55:0] writeburst_flipped_data_reg;
reg [2:0] aligned_store_index;
reg [1:0] unaligned_store_req_count;
reg double_store_done;
reg triple_store_done;

reg flop_bus_load;
reg [31:0] addr_reg_load;
reg [3:0] readburst_length_reg;
reg new_load_req;
reg load_response_received;
reg [2:0] next_state_load;
reg readburst_done_reg;
reg [2:0] req_type_load;
reg [39:0] transducer_l15_address_reg_load;
reg [1:0] number_of_load_requests;
reg alignment_load;
reg single_load;
reg [95:0] readburst_data_reg;
reg [4:0] load_address_index;
reg [1:0] fsm_current_state_load;
reg [1:0] fsm_next_state_load;
reg [3:0] difference_load_size;
reg load_fsm_output_done;
reg outstanding_load_req;
reg [3:0] remaining_load_length;
reg [31:0] next_load_address;
reg [3:0] unaligned_load_size;
reg unaligned_load_new_request;
reg unaligned_load_response_received;
reg [31:0] unaligned_load_address_reg;
reg first_unaligned_load_req_initialised;
reg [63:0] unaligned_load_data;
reg [6:0] unaligned_load_data_index;
reg [3:0] concatenate_unaligned_load_data;

reg transducer_l15_nc_reg;
reg l15_transducer_ack_received;

wire [1:0] counter_ifill_partial;
wire [2:0] state_wire;
wire [127:0] unaligned_load_data_flipped;
//..........................................................................

//Assign statements
assign ao486_int = ao486_int_reg;
assign transducer_l15_val = transducer_l15_val_reg;
assign transducer_l15_address = (state_reg == IFILL) ? {{8{transducer_l15_address_reg_ifill[31]}}, transducer_l15_address_reg_ifill} : (state_reg == STORE) ? transducer_l15_address_reg_store : (state_reg == LOAD) ? transducer_l15_address_reg_load : 40'b0;
assign transducer_l15_rqtype = transducer_l15_rqtype_reg;
assign transducer_l15_req_ack = transducer_l15_req_ack_reg;
assign transducer_ao486_request_readcode_done = readcode_done_reg;
assign transducer_ao486_readcode_partial = readcode_partial_reg;
assign transducer_ao486_readcode_line = readcode_line_reg;
assign state_wire = next_state;
assign counter_ifill_partial = counter_state_ifill_partial;
assign transducer_ao486_readcode_partial_done = readcode_partial_done_reg;
assign transducer_l15_size = transducer_l15_req_size_reg;
assign transducer_l15_data = transducer_l15_data_reg;
assign transducer_l15_nc = transducer_l15_nc_reg;

assign transducer_ao486_writeburst_done = writeburst_done_reg;

assign transducer_ao486_readburst_done = readburst_done_reg;
assign transducer_ao486_readburst_data = readburst_data_reg;
assign unaligned_load_data_flipped = {l15_transducer_data_1[7:0], l15_transducer_data_1[15:8], l15_transducer_data_1[23:16], l15_transducer_data_1[31:24], l15_transducer_data_1[39:32], l15_transducer_data_1[47:40], l15_transducer_data_1[55:48], l15_transducer_data_1[63:56], l15_transducer_data_0[7:0], l15_transducer_data_0[15:8], l15_transducer_data_0[23:16], l15_transducer_data_0[31:24], l15_transducer_data_0[39:32], l15_transducer_data_0[47:40], l15_transducer_data_0[55:48], l15_transducer_data_0[63:56]};
//..........................................................................

//always block to trigger new load request for updating remaining load size 
always @(*) begin
    if(transducer_l15_rqtype_reg == `LOAD_RQ & transducer_l15_val & ~alignment_load) begin
        unaligned_load_new_request = 1;
        unaligned_load_response_received = 0;
        outstanding_load_req = 1;
    end
    else if(l15_transducer_returntype == `LOAD_RET & l15_transducer_val & ~alignment_load) begin
        unaligned_load_response_received = 1;
        unaligned_load_new_request = 0;
        outstanding_load_req = 0;
    end
    else if(~rst_n) begin
        unaligned_load_new_request = 0;
        unaligned_load_response_received = 0;
        outstanding_load_req = 0;
    end
    else begin
        unaligned_load_response_received = 0;
    end
end
//..........................................................................

//always block to calculate remaining ualigned load request size
always @(posedge clk) begin
    if(first_unaligned_load_req_initialised) begin
        remaining_load_length <= readburst_length_reg;
        difference_load_size <= readburst_length_reg;
    end
    else if(unaligned_load_response_received) begin
        remaining_load_length <= remaining_load_length - unaligned_load_size;
        difference_load_size <= remaining_load_length - unaligned_load_size;
    end
    else if(~rst_n) begin
        remaining_load_length <= 0;
        difference_load_size <= 0;
    end
end
//..........................................................................

//always block to flop next address for unlaigned loads
always @(posedge clk) begin
    if(unaligned_load_new_request) begin
        unaligned_load_address_reg <= next_load_address;
    end
    else if(~rst_n) begin
        unaligned_load_address_reg <= 0;
    end
end
//..........................................................................

//always block to calculate next load address for unaligned load requests
always @(*) begin
    if(~rst_n) begin
        unaligned_load_size = 0;
        next_load_address = 0;
    end
    else if(state_reg == LOAD & ~alignment_load & ~outstanding_load_req & ~l15_transducer_val) begin
        case (fsm_current_state_load)
            START_LOAD: begin
                next_load_address = addr_reg_load;
                if(addr_reg_load[1:0] == 2'd0 & readburst_length_reg >= 4'd4) begin
                    unaligned_load_size = 4'd4;
                end 
                else if(addr_reg_load[0] == 0 & readburst_length_reg >= 4'd2) begin
                    unaligned_load_size = 4'd2;
                end
                else begin
                    unaligned_load_size = 4'd1;
                end
            end
            WAITLOOP_LOAD, END_LOAD: begin
                next_load_address = addr_reg_load + (readburst_length_reg - remaining_load_length);
                if(next_load_address[1:0] == 2'd0 & remaining_load_length >= 4'd4) begin
                    unaligned_load_size = 4'd4;
                end
                else if(next_load_address[0] == 0 & remaining_load_length >= 4'd2) begin
                    unaligned_load_size = 4'd2;
                end
                else begin
                    unaligned_load_size = 4'd1;
                end
            end
        endcase
    end
end                                
//..........................................................................

//always block to set unaligned load data index and position of updating data for multiple requests 
always @* begin
    unaligned_load_data_index = 0;
    concatenate_unaligned_load_data = 0;
    if(~alignment_load & l15_transducer_val & l15_transducer_returntype == `LOAD_RET) begin
        unaligned_load_data_index = next_load_address[3:0] << 3;
        concatenate_unaligned_load_data = readburst_length_reg - remaining_load_length;
    end
end
//..........................................................................

//always block to accumulate data obtained from multiple requests for unaligned loads
always @(posedge clk) begin
    if(~rst_n) begin
        unaligned_load_data <= 0;
    end
    else if(~alignment_load & l15_transducer_val & l15_transducer_returntype == `LOAD_RET) begin
        case (unaligned_load_size)
            4'd1: begin
                unaligned_load_data[concatenate_unaligned_load_data*8+:8] <= unaligned_load_data_flipped[unaligned_load_data_index+:8];
            end
            4'd2: begin
                unaligned_load_data[concatenate_unaligned_load_data*8+:16] <= unaligned_load_data_flipped[unaligned_load_data_index+:16];
            end
            4'd4: begin
                unaligned_load_data[concatenate_unaligned_load_data*8+:32] <= unaligned_load_data_flipped[unaligned_load_data_index+:32];
            end
            4'd8: begin
                unaligned_load_data[concatenate_unaligned_load_data*8+:64] <= unaligned_load_data_flipped[unaligned_load_data_index+:64];
            end
        endcase
    end
end
//..........................................................................

//always block to obtain data from load response
always @(posedge clk) begin
    if(number_of_load_requests == 2'b01 & alignment_load) begin
        if(l15_transducer_returntype == `LOAD_RET & l15_transducer_val) begin
            if(readburst_length_reg == 4'b0001) begin
                readburst_data_reg[load_address_index+:8] <= l15_transducer_data_0[7:0];
            end
            else if(readburst_length_reg == 4'b0010) begin
                readburst_data_reg[load_address_index+:16] <= {l15_transducer_data_0[7:0], l15_transducer_data_0[15:8]};
            end
            else if(readburst_length_reg == 4'b0100) begin
                readburst_data_reg[load_address_index+:32] <= {l15_transducer_data_0[7:0], l15_transducer_data_0[15:8], l15_transducer_data_0[23:16], l15_transducer_data_0[31:24]};
            end
            else if(readburst_length_reg == 4'b1000) begin
                readburst_data_reg[load_address_index+:64] <= {l15_transducer_data_0[7:0], l15_transducer_data_0[15:8], l15_transducer_data_0[23:16], l15_transducer_data_0[31:24], l15_transducer_data_0[39:32], l15_transducer_data_0[47:40], l15_transducer_data_0[55:48], l15_transducer_data_0[63:56]};
            end
        end
    end
    else if(~alignment_load & load_fsm_output_done) begin
        case (readburst_length_reg)
            4'd1: begin
                readburst_data_reg[load_address_index+:8] <= unaligned_load_data[7:0];
            end
            4'd2: begin
                readburst_data_reg[load_address_index+:16] <= unaligned_load_data[15:0];
            end
            4'd4: begin
                readburst_data_reg[load_address_index+:32] <= unaligned_load_data[31:0];
            end
            4'd8: begin
                readburst_data_reg[load_address_index+:64] <= unaligned_load_data[63:0];
            end
        endcase
    end
    else if(~rst_n) begin
        readburst_data_reg <= 0;
    end
end
//..........................................................................

//always block to set readburst_done signal upon receiving load response from L1.5
always @(posedge clk) begin
    if(number_of_load_requests == 2'b01 & alignment_load) begin
        if(l15_transducer_returntype == `LOAD_RET & l15_transducer_val) begin
            readburst_done_reg <= 1;                      
        end
        else begin
            readburst_done_reg <= 0;
        end
    end
    else if(~alignment_load) begin
        if(load_fsm_output_done) begin
            readburst_done_reg <= 1;
        end else begin
           readburst_done_reg <= 0; 
        end
    end
    else if(~rst_n) begin
        readburst_done_reg <= 0;
    end
end
//..........................................................................

//always block to create state register for handling load requests FSM                  FSM State Register
always @(posedge clk or posedge new_load_req) begin
    if(~new_load_req) begin
        fsm_current_state_load <= IDLE_LOAD;
    end
    else if (new_load_req & ~alignment_load & state_reg == LOAD) begin
        fsm_current_state_load <= fsm_next_state_load;
    end
end
//..........................................................................

//always block to compute output logic for load requests FSM                            FSM Output Logic 
always @(fsm_current_state_load or outstanding_load_req) begin
    load_fsm_output_done = 0;
    case (fsm_current_state_load) 
        START_LOAD: begin
            load_fsm_output_done = 0;
        end
        WAITLOOP_LOAD: begin
            load_fsm_output_done = 0;
        end
        END_LOAD: begin
            load_fsm_output_done = 1;
        end
    endcase
end
//..........................................................................

//always block to set first unaligned request initialisation 
always @(fsm_next_state_load or posedge outstanding_load_req) begin
    if(fsm_next_state_load == START_LOAD & ~outstanding_load_req) begin
        first_unaligned_load_req_initialised = 1;
    end
    else begin
        first_unaligned_load_req_initialised = 0;
    end
end
//..........................................................................

//always block to compute next state logic for load requests FSM                           FSM Next State Logic
always @(fsm_current_state_load or outstanding_load_req or difference_load_size or state_reg) begin
    if(state_reg == LOAD) begin
        case (fsm_current_state_load) 
            START_LOAD: begin   
                if(outstanding_load_req) begin
                    fsm_next_state_load = START_LOAD;
                end
                else if(difference_load_size == 0) begin
                    fsm_next_state_load = END_LOAD;
                end
                else if(~first_unaligned_load_req_initialised) begin
                    fsm_next_state_load = WAITLOOP_LOAD;
                end
            end
            WAITLOOP_LOAD: begin
                if(~outstanding_load_req & difference_load_size == 0) begin
                    fsm_next_state_load = END_LOAD;
                end
                else begin
                    fsm_next_state_load = WAITLOOP_LOAD;
                end
            end
            END_LOAD: begin
                if(~outstanding_load_req & difference_load_size != 0) begin
                    fsm_next_state_load = END_LOAD;
                end
                else begin
                    fsm_next_state_load = IDLE_LOAD;
                end
            end
            IDLE_LOAD: begin
                fsm_next_state_load = START_LOAD;
            end
        endcase    
    end
    else begin
        fsm_next_state_load = IDLE_LOAD;
    end
end
//..........................................................................

//always block to decide index at which load data is to be put based on address
always @* begin
    case (addr_reg_load[1:0])
        2'b00: begin
            load_address_index = 0;
        end
        2'b01: begin
            load_address_index = 5'b01000;
        end
        2'b10: begin
            load_address_index = 5'b10000;
        end
        2'b11: begin
            load_address_index = 5'b11000;  
        end
    endcase
end
//..........................................................................

//always block to decide number of load requests to be sent to L1.5 for each request received from core
always @(*) begin
    if(new_load_req) begin
        case (readburst_length_reg)
            4'b0001: begin
                number_of_load_requests = 2'b01;
                alignment_load = 1;
            end
            4'b0010: begin
                if(~addr_reg_load[0]) begin
                    number_of_load_requests = 2'b01;
                    alignment_load = 1;
                end
                else if(addr_reg_load[0]) begin
                    $display("Unaligned load");
                    alignment_load = 0;
                end
            end
            4'b0011, 4'b0101, 4'b0110, 4'b0111: begin
                $display("Unaligned load");
                alignment_load = 0;
            end                    
            4'b0100: begin
                if(addr_reg_load[1:0] == 2'b0) begin
                    number_of_load_requests = 2'b01;
                    alignment_load = 1;
                end
                else begin
                    alignment_load = 0;
                    $display("Unaligned load");
                end
            end
            4'b1000: begin
                if(addr_reg_load[2:0] == 3'b0) begin
                    number_of_load_requests = 2'b01;
                    alignment_load = 1;
                end
                else begin
                    $display("Unaligned load");
                    alignment_load = 0;
                end
            end
        endcase
    end
    else if(~rst_n) begin
        number_of_load_requests = 0;
        alignment_load = 0;
    end
end
//..........................................................................

//always block to decide number of store requests required to be sent to L1.5 
always @(posedge clk) begin
    if(new_store_req) begin
        case (writeburst_length_reg)
            3'b001: begin
                number_of_store_requests <= 2'b01;
                alignment_store <= ALIGNED_STORE;
            end
            3'b010: begin
                if(~addr_reg_store[0]) begin
                    alignment_store <= ALIGNED_STORE;
                    number_of_store_requests <= 2'b01;
                end
                else if(addr_reg_store[0]) begin
                    $display("Unaligned store with 2 requests");
                    alignment_store <= UNALIGNED_STORE;
                    number_of_store_requests <= 2'b10;
                    store_length_1 <= 3'b001;
                    store_length_2 <= 3'b001;
                    store_address_1 <= addr_reg_store;
                    store_address_2 <= addr_reg_store + 1'b1;
                end
            end
            3'b011: begin                          
                alignment_store <= UNALIGNED_STORE;
                $display("Unaligned store with 2 requests");
                number_of_store_requests = 2'b10;
                store_address_1 <= addr_reg_store;
                if(~addr_reg_store[0]) begin
                    store_length_1 <= 3'b010;
                    store_address_2 <= addr_reg_store + 2'b10;
                    store_length_2 <= 3'b001;
                end
                else if(addr_reg_store[0]) begin
                    store_length_1 <= 3'b001;
                    store_length_2 <= 3'b010;
                    store_address_2 <= addr_reg_store + 1'b1;
                end
            end
            3'b100: begin
                if(addr_reg_store[1:0] == 2'b0) begin
                    alignment_store <= ALIGNED_STORE;
                    number_of_store_requests <= 2'b01;
                end
                else if(addr_reg_store[1:0] == 2'b01) begin
                    alignment_store <= UNALIGNED_STORE;
                    $display("Unaligned store with 3 requests");
                    number_of_store_requests <= 2'b11;
                    store_length_1 <= 3'b001;
                    store_length_2 <= 3'b010;
                    store_length_3 <= 3'b001;
                    store_address_1 <= addr_reg_store;
                    store_address_2 <= addr_reg_store + 1'b1;
                    store_address_3 <= addr_reg_store + 2'b11;
                end
                else if(addr_reg_store[1:0] == 2'b10) begin
                    alignment_store <= UNALIGNED_STORE;
                    number_of_store_requests <= 2'b10;
                    $display("Unaligned store with 2 requests");
                    store_length_1 <= 3'b010;
                    store_length_2 <= 3'b010;
                    store_address_1 <= addr_reg_store;
                    store_address_2 <= addr_reg_store + 2'b10;
                end
                else if(addr_reg_store[1:0] == 2'b11) begin
                    alignment_store <= UNALIGNED_STORE;
                    number_of_store_requests <= 2'b11;
                    $display("Unaligned store with 3 requests");
                    store_length_1 <= 3'b001;
                    store_length_2 <= 3'b010;
                    store_length_3 <= 3'b001;
                    store_address_1 <= addr_reg_store;
                    store_address_2 <= addr_reg_store + 1'b1;
                    store_address_3 <= addr_reg_store + 2'b11;
                end
            end
        endcase
    end
    else if(~rst_n) begin
        number_of_store_requests <= 2'b00;
        alignment_store <= 2'b00;
        store_length_1 <= 0;
        store_length_2 <= 0;
        store_length_3 <= 0;
        store_address_1 <= 0;
        store_address_2 <= 0;
        store_address_3 <= 0;
    end
end     
//..........................................................................

//always block to assign transducer -> L1.5 signals for different store requests
always @(*) begin
    if(number_of_store_requests == 2'b01 & transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack) begin
        single_store = 1;
        case (writeburst_length_reg)
            3'b100: begin
                transducer_l15_data_reg = {2{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:32]}};
            end
            3'b010: begin
                transducer_l15_data_reg = {4{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:16]}};
            end
            3'b001: begin
                transducer_l15_data_reg = {8{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:8]}};
            end
        endcase
    end
    else if(number_of_store_requests == 2'b10 & transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack) begin
        double_store = 1;
        if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & ~first_store_ack) begin
            case (store_length_1)
                3'b100: begin
                    transducer_l15_data_reg = {2{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:32]}};
                end
                3'b010: begin
                    transducer_l15_data_reg = {4{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:16]}};
                end
                3'b001: begin
                    transducer_l15_data_reg = {8{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:8]}};
                end
            endcase
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
            if(~second_store_ack) begin
                case (store_length_2)
                    3'b100: begin
                        transducer_l15_data_reg = {2{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - store_length_1*8)-:32]}};
                    end
                    3'b010: begin
                        transducer_l15_data_reg = {4{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - store_length_1*8)-:16]}};
                    end
                    3'b001: begin
                        transducer_l15_data_reg = {8{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - store_length_1*8)-:8]}};
                    end
                endcase
            end
            else begin
                transducer_l15_data_reg = 0;
            end
        end                        
    end
    else if(number_of_store_requests == 2'b11 & transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack) begin
        triple_store = 1;
        if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & ~first_store_ack) begin
            case (store_length_1)
                3'b100: begin
                    transducer_l15_data_reg = {2{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:32]}};
                end
                3'b010: begin
                    transducer_l15_data_reg = {4{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:16]}};
                end
                3'b001: begin
                    transducer_l15_data_reg = {8{writeburst_flipped_data_reg[(aligned_store_index*8-1'b1)-:8]}};
                end
            endcase
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
            if(~second_store_ack) begin
                case (store_length_2)
                    3'b100: begin
                        transducer_l15_data_reg = {2{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - store_length_1*8)-:32]}};
                    end
                    3'b010: begin
                        transducer_l15_data_reg = {4{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - store_length_1*8)-:16]}};
                    end
                    3'b001: begin
                        transducer_l15_data_reg = {8{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - store_length_1*8)-:8]}};
                    end
                endcase
            end
            else if(~third_store_ack) begin
                case (store_length_3) 
                    3'b100: begin
                        transducer_l15_data_reg = {2{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - (store_length_1+store_length_2)*8)-:32]}};
                    end
                    3'b010: begin
                        transducer_l15_data_reg = {4{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - (store_length_1+store_length_2)*8)-:16]}};
                    end
                    3'b001: begin
                        transducer_l15_data_reg = {8{writeburst_flipped_data_reg[((aligned_store_index*8-1'b1) - (store_length_1+store_length_2)*8)-:8]}};
                    end
                endcase
            end
            else begin
                transducer_l15_data_reg = 0;
            end
        end                        
    end
    else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
        if(number_of_store_requests == 2'b01) begin
            transducer_l15_data_reg = 0;
            single_store = 0; 
        end
        else if(number_of_store_requests == 2'b10 & double_store_done) begin
            double_store = 0;
        end
        else if(number_of_store_requests == 2'b11 & triple_store_done) begin
            triple_store = 0;
        end 
    end
    else if(~rst_n) begin
        transducer_l15_data_reg = 0;
        single_store = 0;
        double_store = 0;
        triple_store = 0;
    end
end
//..........................................................................

//always block to set second and third store acknowledge 
always @* begin
    if(number_of_store_requests == 2'b10) begin
        if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & ~first_store_ack) begin
            second_store_ack = 0;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & first_store_ack) begin
            second_store_ack = 1;
            double_store_done = 1;
        end
        else begin
            double_store_done = 0;
        end
    end
    else if(number_of_store_requests == 2'b11) begin
        if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & ~first_store_ack) begin
            second_store_ack = 0;
            third_store_ack = 0;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & first_store_ack & ~third_store_header) begin
            second_store_ack = 1;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & third_store_header) begin
            third_store_ack = 1;
            triple_store_done = 1;
        end
        else begin
            triple_store_done = 0;
        end
    end
    else if(~rst_n) begin
        second_store_ack = 0;
        third_store_ack = 0;
        double_store_done = 0;
        triple_store_done = 0;
    end
end
//..........................................................................

//always block to set writeburst_done signal upon receiving store acknowledgement from L1.5
always @(posedge clk) begin
    if(number_of_store_requests == 2'b01) begin
        if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
            writeburst_done_reg <= 1;
        end
        else begin
            writeburst_done_reg <= 0;
        end
    end
    else if(number_of_store_requests == 2'b10) begin
        if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & first_store_ack) begin
            writeburst_done_reg <= 1;
        end
        else begin
            writeburst_done_reg <= 0;
        end
    end
    else if(number_of_store_requests == 2'b11) begin
        if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & third_store_header) begin
            writeburst_done_reg <= 1;
        end
        else begin
            writeburst_done_reg <= 0;
        end
    end
    else if(~rst_n) begin
        writeburst_done_reg <= 0;
    end
end
//..........................................................................

//always block to check if l15_transducer_ack has been received
always @* begin
    if(l15_transducer_ack) begin
        l15_transducer_ack_received = 1;
    end
    else if(l15_transducer_val & l15_transducer_returntype != `INV_RET) begin
        l15_transducer_ack_received = 0;
    end
    else if(~rst_n) begin
        l15_transducer_ack_received = 0;
    end
end
//..........................................................................

//always block to set _nc signal
always @(posedge clk) begin
    if((state_reg == STORE & l15_transducer_ack) | (state_reg == LOAD & l15_transducer_ack)) begin
        transducer_l15_nc_reg <= 0;
    end
    else if((transducer_l15_rqtype_reg == `STORE_RQ & state_reg == STORE & ~l15_transducer_ack & ~l15_transducer_ack_received) | (transducer_l15_rqtype_reg == `LOAD_RQ & state_reg == LOAD & ~l15_transducer_ack & ~l15_transducer_val & ~l15_transducer_ack_received & (alignment_load | (fsm_current_state_load == START_LOAD | fsm_current_state_load == WAITLOOP_LOAD & fsm_next_state_load != END_LOAD)))) begin
        transducer_l15_nc_reg <= 1;
    end
    else if(~rst_n) begin
        transducer_l15_nc_reg <= 0;
    end
end
//..........................................................................

//always block to assign transducer -> L1.5 signals for different load requests
always @(posedge clk) begin
    if(number_of_load_requests == 2'b01 & transducer_l15_rqtype_reg == `LOAD_RQ & alignment_load) begin
        transducer_l15_address_reg_load <= {8'b0, addr_reg_load};
    end
    else if(transducer_l15_rqtype_reg == `LOAD_RQ & ~alignment_load) begin
        transducer_l15_address_reg_load <= {8'd0, next_load_address};
    end
    else if(l15_transducer_returntype == `LOAD_RET & l15_transducer_val) begin
        transducer_l15_address_reg_load <= 0;
    end
    else if(~rst_n) begin
        transducer_l15_address_reg_load <= 0;
    end
end      
//..........................................................................

//always block to acknowledge different stores in unaligned requests
always @(posedge clk) begin
    if(double_store) begin
        if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & unaligned_store_req_count == 0) begin
            first_store_ack <= 0;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
            first_store_ack <= 1;
        end
    end
    else if(triple_store) begin
        if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & unaligned_store_req_count == 0) begin
            first_store_ack <= 0;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
            first_store_ack <= 1;
        end
    end
    else if(~rst_n) begin
        first_store_ack <= 0;
    end
end
//..........................................................................

//always block to set address for store requests
always @(posedge clk) begin
    if(single_store) begin
        if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack) begin
            transducer_l15_address_reg_store <= {8'b0, addr_reg_store};
        end
        else if(l15_transducer_header_ack) begin
            transducer_l15_address_reg_store <= transducer_l15_address_reg_store;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
        transducer_l15_address_reg_store <= 0;
        end
    end
    else if(double_store) begin
        if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & ~first_store_ack) begin
            transducer_l15_address_reg_store <= {{8{store_address_1[31]}}, store_address_1};
            unaligned_store_req_count <= 0;
        end
        else if(l15_transducer_header_ack) begin
            transducer_l15_address_reg_store <= transducer_l15_address_reg_store;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
            if(~second_store_ack) begin
                transducer_l15_address_reg_store <= {{8{store_address_2[31]}}, store_address_2};
                unaligned_store_req_count <= 2'b01;
            end
            else begin
                transducer_l15_address_reg_store <= 0;
                unaligned_store_req_count <= 2'b10;
            end
        end
    end
    else if(triple_store) begin
        if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & ~first_store_ack) begin
            transducer_l15_address_reg_store <= {{8{store_address_1[31]}}, store_address_1};
            third_store_header <= 0;
            unaligned_store_req_count <= 0;
        end
        else if(l15_transducer_header_ack) begin
            transducer_l15_address_reg_store <= transducer_l15_address_reg_store;
        end
        else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
            if(~second_store_ack) begin
                transducer_l15_address_reg_store <= {{8{store_address_2[31]}}, store_address_2};
                unaligned_store_req_count <= 2'b01;
            end
            else if(~third_store_ack) begin
                transducer_l15_address_reg_store <= {{8{store_address_3[31]}}, store_address_3};
                third_store_header <= 1;
                unaligned_store_req_count <= 2'b10;
            end
            else begin
                transducer_l15_address_reg_store <= 0;
                unaligned_store_req_count <= 2'b11;
            end
        end
    end
    else if(~rst_n) begin
        transducer_l15_address_reg_store <= 0;
        third_store_header <= 0;
        unaligned_store_req_count <= 0;
    end
end
//..........................................................................

//always block to flop readcode_line_reg signal                                               (verified)
always @(posedge clk) begin
    if(~rst_n) begin
        readcode_line_reg <= 0;
        readcode_partial_reg <= 0;
    end
    else if(~double_access) begin
        readcode_line_reg[(ifill_index_counter*32)+:32] <= l15_transducer_data_vector_ifill[ifill_index+(ifill_index_counter*32)+:32];
        readcode_partial_reg <= l15_transducer_data_vector_ifill[ifill_index+(ifill_index_counter*32)+:32];
    end
end
//..........................................................................

//Always block to sequentially send _readcode_partial signals one clock pulse at a time                 (verified)
always @(*) begin
    if(continue_ifill_count) begin
        case (counter_ifill_partial) 
            2'b00: begin
                ifill_index_counter = 2'b01;
                readcode_partial_done_reg = 1'b1;
            end
            2'b01: begin
                ifill_index_counter = 2'b10;
            end
            2'b10: begin
                ifill_index_counter = 2'b11;
            end
            2'b11: begin 
                readcode_done_reg = 1'b1;
                readcode_partial_done_reg = 1'b0;    
            end
        endcase
    end
    else if(~rst_n) begin
        readcode_done_reg <= 1'b0;
        readcode_partial_done_reg <= 1'b0;
        ifill_index_counter = 2'd0;
    end
    else if(reset_ifill_index_counter) begin
        ifill_index_counter = 2'b0;
    end
    else begin
        readcode_done_reg = 1'b0;
        readcode_partial_done_reg = 1'b0;
    end
end
//..........................................................................

//Always block for ifill _partial counter                                                          (verified)
always @(posedge clk) begin
    if(toggle_ifill_partial) begin
        counter_state_ifill_partial <= 2'b00;
        continue_ifill_count <= 1'b1;
    end
    else if(continue_ifill_count) begin
        case (counter_state_ifill_partial)
            2'b00: counter_state_ifill_partial <= 2'b01;
            2'b01: counter_state_ifill_partial <= 2'b10;
            2'b10: counter_state_ifill_partial <= 2'b11;
            2'b11: begin
                counter_state_ifill_partial <= 2'b00;
                continue_ifill_count <= 1'b0;
            end
        endcase
    end
    else if(~rst_n) begin
        counter_state_ifill_partial <= 2'd0;
        continue_ifill_count <= 1'b0;
    end
end
//..........................................................................

//Always block for toggle for sending _readcode_partial signals to core                          (verified)          
always @(*) begin
    if(request_readcode_done_reg & returntype_reg == `IFILL_RET) begin
        toggle_ifill_partial = 1'b1;
    end
    else begin
        toggle_ifill_partial = 1'b0;
    end
end
//..........................................................................

//always block to set flop_bus_load for load request
always @* begin
    if(ao486_transducer_load_req_readburst_do) begin
        flop_bus_load = 1'b1;
    end
    else begin
        flop_bus_load = 0;
    end
end
//..........................................................................

//always block to set flop_bus_store for store request
always @* begin
    if(ao486_transducer_store_req_writeburst_do) begin
        flop_bus_store = 1'b1;
    end
    else begin
        flop_bus_store = 0;
    end
end
//..........................................................................

//always block to set req_type
always @* begin
    if(ao486_transducer_ifill_req_readcode_do) begin
        req_type = IFILL;
    end
    else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val & (~double_access | double_access_ifill_done)) begin
        req_type = 3'b0;
    end
    if(ao486_transducer_store_req_writeburst_do) begin
        req_type_store = STORE;
    end
    else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
        req_type_store = 3'b0;
    end
    if(ao486_transducer_load_req_readburst_do) begin
        req_type_load = LOAD;
    end
    else if((l15_transducer_returntype == `LOAD_RET & l15_transducer_val & alignment_load) | load_fsm_output_done) begin
        req_type_load = 3'b0;
    end
    else if(~rst_n) begin
        req_type = 3'd0;
        req_type_load = 3'b0;
        req_type_store = 3'b0;
    end
end
//..........................................................................

//Always block to obtain request type from core and set flop_bus                                            (verified)
always @(*) begin
    if(ao486_transducer_ifill_req_readcode_do) begin
        flop_bus = 1'b1;
        ifill_response = 1'b0;
    end
    else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val) begin  
        ifill_response = 1'b1;
    end
    else begin
        flop_bus = 1'b0;    
    end
end
//..........................................................................

//Always block to set ifill_index to select instructions to be sent to core                      (verified)
always @* begin
    if(~double_access & (double_access_count == 0) & reset_ifill_index_counter) begin
        if(addr_reg[4:0] == 5'd0) begin
            ifill_index = 0;
        end
        else if(addr_reg[4:0] == 5'b00100) begin
            ifill_index = 32;
        end
        else if(addr_reg[4:0] == 5'b01000) begin
            ifill_index = 64;
        end
        else if(addr_reg[4:0] == 5'b01100) begin
            ifill_index = 96;
        end
        else if(addr_reg[4:0] == 5'b10000) begin
            ifill_index = 128;
        end
    end
    else if(double_access & double_access_count == 2'd1) begin
        if(ifill_double_access_first_address[4:0] == 5'b10100) begin
            ifill_index = 160; 
        end
        else if(ifill_double_access_first_address[4:0] == 5'b11000) begin
            ifill_index = 192;
        end
        else if(ifill_double_access_first_address[4:0] == 5'b11100) begin
            ifill_index = 224;
        end
    end
    else if(~rst_n) begin
        ifill_index = 0;
    end        
end
//..........................................................................

//Always block to convert big endian to little endian for ifill                                             (verified)
always @(posedge clk) begin
    if(~double_access) begin
        if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val == 1'b1) begin
            l15_transducer_data_vector_ifill <= {256'd0, l15_transducer_data_3[7:0], l15_transducer_data_3[15:8], l15_transducer_data_3[23:16], l15_transducer_data_3[31:24], l15_transducer_data_3[39:32], l15_transducer_data_3[47:40], l15_transducer_data_3[55:48], l15_transducer_data_3[63:56],l15_transducer_data_2[7:0], l15_transducer_data_2[15:8], l15_transducer_data_2[23:16], l15_transducer_data_2[31:24], l15_transducer_data_2[39:32], l15_transducer_data_2[47:40], l15_transducer_data_2[55:48], l15_transducer_data_2[63:56], l15_transducer_data_1[7:0], l15_transducer_data_1[15:8], l15_transducer_data_1[23:16], l15_transducer_data_1[31:24], l15_transducer_data_1[39:32], l15_transducer_data_1[47:40], l15_transducer_data_1[55:48], l15_transducer_data_1[63:56], l15_transducer_data_0[7:0], l15_transducer_data_0[15:8], l15_transducer_data_0[23:16], l15_transducer_data_0[31:24], l15_transducer_data_0[39:32], l15_transducer_data_0[47:40], l15_transducer_data_0[55:48], l15_transducer_data_0[63:56]};
            reset_ifill_index_counter <= 1;
            returntype_reg <= `IFILL_RET;
            request_readcode_done_reg <= 1'b1;
        end       
        else begin
            request_readcode_done_reg <= 1'b0;
            returntype_reg <= 1'b0;
            reset_ifill_index_counter <= 0;
        end
    end
    else if(double_access) begin
        if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val == 1'b1 & (double_access_count == 2'd0)) begin
            returntype_reg <= `IFILL_RET;
            l15_transducer_data_vector_ifill <= {256'd0, l15_transducer_data_3[7:0], l15_transducer_data_3[15:8], l15_transducer_data_3[23:16], l15_transducer_data_3[31:24], l15_transducer_data_3[39:32], l15_transducer_data_3[47:40], l15_transducer_data_3[55:48], l15_transducer_data_3[63:56],l15_transducer_data_2[7:0], l15_transducer_data_2[15:8], l15_transducer_data_2[23:16], l15_transducer_data_2[31:24], l15_transducer_data_2[39:32], l15_transducer_data_2[47:40], l15_transducer_data_2[55:48], l15_transducer_data_2[63:56], l15_transducer_data_1[7:0], l15_transducer_data_1[15:8], l15_transducer_data_1[23:16], l15_transducer_data_1[31:24], l15_transducer_data_1[39:32], l15_transducer_data_1[47:40], l15_transducer_data_1[55:48], l15_transducer_data_1[63:56], l15_transducer_data_0[7:0], l15_transducer_data_0[15:8], l15_transducer_data_0[23:16], l15_transducer_data_0[31:24], l15_transducer_data_0[39:32], l15_transducer_data_0[47:40], l15_transducer_data_0[55:48], l15_transducer_data_0[63:56]};
            first_ifill_access_done <= 1'b1;
            second_ifill_access_done <= 1'b0;
        end
        else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val == 1'b1 & (double_access_count == 2'd1)) begin
            returntype_reg <= `IFILL_RET;
            l15_transducer_data_vector_ifill <= {l15_transducer_data_3[7:0], l15_transducer_data_3[15:8], l15_transducer_data_3[23:16], l15_transducer_data_3[31:24], l15_transducer_data_3[39:32], l15_transducer_data_3[47:40], l15_transducer_data_3[55:48], l15_transducer_data_3[63:56],l15_transducer_data_2[7:0], l15_transducer_data_2[15:8], l15_transducer_data_2[23:16], l15_transducer_data_2[31:24], l15_transducer_data_2[39:32], l15_transducer_data_2[47:40], l15_transducer_data_2[55:48], l15_transducer_data_2[63:56], l15_transducer_data_1[7:0], l15_transducer_data_1[15:8], l15_transducer_data_1[23:16], l15_transducer_data_1[31:24], l15_transducer_data_1[39:32], l15_transducer_data_1[47:40], l15_transducer_data_1[55:48], l15_transducer_data_1[63:56], l15_transducer_data_0[7:0], l15_transducer_data_0[15:8], l15_transducer_data_0[23:16], l15_transducer_data_0[31:24], l15_transducer_data_0[39:32], l15_transducer_data_0[47:40], l15_transducer_data_0[55:48], l15_transducer_data_0[63:56], l15_transducer_data_vector_ifill[255:0]};
            request_readcode_done_reg <= 1'b1;
            second_ifill_access_done <= 1'b1;
            first_ifill_access_done <= 1'b0;
            reset_ifill_index_counter <= 1;
        end
        else begin
            request_readcode_done_reg <= 1'b0;
            returntype_reg <= 4'd0;
            reset_ifill_index_counter <= 0;
            second_ifill_access_done <= 1'b0;
        end
    end
    else if(~rst_n) begin
        reset_ifill_index_counter <= 0;
        returntype_reg <= 4'd0;
        request_readcode_done_reg <= 1'b0;
        l15_transducer_data_vector_ifill <= 512'd0;
        first_ifill_access_done <= 1'b0;
        second_ifill_access_done <= 1'b0;
    end
end
//..........................................................................

//Always block setting transducer_l15_req_ack high indicating response received                                     (Verified)
always @(*) begin
    if(l15_transducer_val) begin
        transducer_l15_req_ack_reg = 1'b1;
    end
    else begin
        transducer_l15_req_ack_reg = 1'b0;
    end
end
//..........................................................................

//always block to finish double access ifill response                                                 (verified)
always @(*) begin
    if(l15_transducer_val & (double_access_count == 2'd1)) begin
        double_access_ifill_done = 1'b1;
    end
    else begin
        double_access_ifill_done = 1'b0;
    end
end
//..........................................................................

//always block to set which request is being processed by TRI
always @(*) begin
    if(req_type == IFILL & (~ifill_response) & ((store_response_received & load_response_received) | interrupt_received)) begin
        state_reg = IFILL;
    end
    else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val & (~double_access | double_access_ifill_done)) begin
        state_reg = IDLE;
    end
    else if(req_type_store == STORE & ifill_response_received & load_response_received & ~l15_transducer_val & new_store_req & ~double_store_done & ~triple_store_done) begin
        state_reg = STORE;
    end
    else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & (single_store | double_store_done | triple_store_done)) begin
        state_reg = IDLE;
    end
    else if(req_type_load == LOAD & new_load_req == 1 & ifill_response_received & store_response_received & (alignment_load | ~load_fsm_output_done)) begin
        state_reg = LOAD;
    end
    else if(l15_transducer_returntype == `LOAD_RET & l15_transducer_val) begin
        state_reg = IDLE;
    end
    else if(~rst_n) begin
        state_reg = IDLE;
    end
end
//..........................................................................

//Always block to send ifill request type to L1.5                                                           (verified)
always @(posedge clk) begin
    if(req_type == IFILL & (~ifill_response) & state_reg == IFILL) begin
        transducer_l15_rqtype_reg <= `IMISS_RQ;
        ifill_response_received <= 0;
    end
    else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val & (~double_access | double_access_ifill_done)) begin       //to set request type to zero after receiving response from L1.5 for an ifill
        transducer_l15_rqtype_reg <= 5'd0;
        ifill_response_received <= 1;
    end
    else if(req_type_store == STORE & state_reg == STORE) begin
        transducer_l15_rqtype_reg <= `STORE_RQ;
        store_response_received <= 0;
    end
    else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & (single_store | double_store_done | triple_store_done)) begin
        transducer_l15_rqtype_reg <= 5'd0;
        store_response_received <= 1;
    end
    else if(req_type_load == LOAD & state_reg == LOAD) begin
        transducer_l15_rqtype_reg <= `LOAD_RQ;
        load_response_received <= 0;
    end
    else if((l15_transducer_returntype == `LOAD_RET & l15_transducer_val & alignment_load) | load_fsm_output_done) begin
        transducer_l15_rqtype_reg <= 0;
        load_response_received <= 1;
    end
    else if (~rst_n) begin
        transducer_l15_rqtype_reg <= 5'd0;
        ifill_response_received <= 0;
        store_response_received <= 0;
        load_response_received <= 1;
    end
end    
//..........................................................................

//Always block to set transducer_l15_val                                                                          (Verified)
always @(posedge clk) begin
    if(transducer_l15_rqtype_reg == `IMISS_RQ & ~l15_transducer_header_ack & (state_wire != IFILL)) begin
        transducer_l15_val_reg <= 1'b1;
    end
    else if(l15_transducer_header_ack) begin
        transducer_l15_val_reg <= 1'b0;  
    end
    else if(state_reg == STORE & transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & (next_state_store != STORE)) begin
        transducer_l15_val_reg <= 1'b1;
    end
    else if(state_reg == LOAD & transducer_l15_rqtype_reg == `LOAD_RQ & ~l15_transducer_header_ack & (next_state_load != LOAD) & (alignment_load | (fsm_current_state_load != IDLE_LOAD & fsm_next_state_load != END_LOAD & ~load_fsm_output_done))) begin
        transducer_l15_val_reg <= 1'b1;
    end
    else if(~rst_n) begin
        transducer_l15_val_reg <= 1'b0;
    end
end
//..........................................................................

//always block to keep transducer_l15_val low once load request is sent
always @(posedge clk) begin
    if(~rst_n) begin
        next_state_load <= 3'b0;
    end
    else if(l15_transducer_header_ack & transducer_l15_rqtype_reg == `LOAD_RQ) begin
        next_state_load <= LOAD;  
    end
    else if(l15_transducer_returntype == `LOAD_RET & l15_transducer_val) begin
        next_state_load <= 3'b0;
    end
end
//..........................................................................

//always block to keep transducer_l15_val low once store request is sent
always @(posedge clk) begin
    if(~rst_n) begin
        next_state_store <= 3'b0;
    end
    else if(l15_transducer_header_ack & transducer_l15_rqtype_reg == `STORE_RQ) begin
        next_state_store <= STORE;  
    end
    else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
        next_state_store <= 3'b0;
    end
end
//..........................................................................

//Always block to set address to be sent to L1.5 for instructions                               (verified)
always @(posedge clk) begin
    if(~double_access) begin       
        if(transducer_l15_rqtype_reg == `IMISS_RQ & ~l15_transducer_header_ack & (state_wire != IFILL)) begin
            transducer_l15_address_reg_ifill <= {addr_reg[31:5], 5'd0};
        end
        else if(l15_transducer_header_ack & state_reg == IFILL) begin
            transducer_l15_address_reg_ifill <= transducer_l15_address_reg_ifill;
            next_state <= IFILL;
        end
        else if(~rst_n) begin
            next_state <= 3'd0;
            transducer_l15_address_reg_ifill <= 32'd0;
        end
        else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val) begin          //to set address to zero after receiving response from L1.5 for an ifill
            transducer_l15_address_reg_ifill <= 32'd0;
            next_state <= 3'd0;
            double_access_count <= 2'd0;
        end
    end
    else if(double_access) begin
        if(transducer_l15_rqtype_reg == `IMISS_RQ & ~l15_transducer_header_ack & (state_wire != IFILL) & (~first_ifill_access_done)) begin
            transducer_l15_address_reg_ifill <= {ifill_double_access_first_address[31:5], 5'd0};
            double_access_count <= 2'd0;
        end
        else if(l15_transducer_header_ack & state_reg == IFILL) begin
            transducer_l15_address_reg_ifill <= transducer_l15_address_reg_ifill;
            next_state <= IFILL;
        end
        else if(~rst_n) begin
            next_state <= 3'd0;
            double_access_count <= 2'd0;
            transducer_l15_address_reg_ifill <= 32'd0;
        end
        else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val) begin          
            if(~second_ifill_access_done) begin
                transducer_l15_address_reg_ifill <= {ifill_double_access_second_address[31:5], 5'd0};
                double_access_count <= 2'd1;
                next_state <= 3'd0;
            end
            else if(second_ifill_access_done) begin
                next_state <= 3'd0;
                transducer_l15_address_reg_ifill <= 32'd0;
                double_access_count <= 2'd2;
            end
        end
    end       
end
//..........................................................................

//always block to flop address and length for load request
always @(posedge clk) begin
    if(~rst_n) begin
        addr_reg_load <= 32'b0;
        readburst_length_reg <= 4'b0;
        new_load_req <= 0;
    end
    else if(flop_bus_load) begin
        addr_reg_load <= ao486_transducer_load_req_readburst_address;
        readburst_length_reg <= ao486_transducer_load_req_readburst_byte_length;
        new_load_req <= 1;
    end
    else if((l15_transducer_returntype == `LOAD_RET & l15_transducer_val & alignment_load) | load_fsm_output_done) begin
        new_load_req <= 0;
        addr_reg_load <= 32'b0;
    end    
end
//..........................................................................

//always block to flip store data received from core
always @(posedge clk) begin
    if(~rst_n) begin
        aligned_store_index <= 0;
        writeburst_flipped_data_reg <= 0;
    end
    else if(new_store_req) begin
        writeburst_flipped_data_reg <= {writeburst_data_reg[7:0], writeburst_data_reg[15:8], writeburst_data_reg[23:16], writeburst_data_reg[31:24], writeburst_data_reg[39:32], writeburst_data_reg[47:40], writeburst_data_reg[55:48]};
        if(addr_reg_store[1:0] == 0) begin
            aligned_store_index <= 3'b111;
        end
        else if(addr_reg_store[1:0] == 2'b01) begin
            aligned_store_index <= 3'b110;
        end
        else if(addr_reg_store[1:0] == 2'b10) begin
            aligned_store_index <= 3'b101;
        end
        else begin
            aligned_store_index <= 3'b100;
        end
    end
end
//..........................................................................

//always block to flop address for store request
always @(posedge clk) begin
    if(~rst_n) begin
        addr_reg_store <= 32'd0;
        writeburst_data_reg <= 56'd0;
        writeburst_length_reg <= 3'd0;
        new_store_req <= 0;
    end
    else if(flop_bus_store) begin
        addr_reg_store <= ao486_transducer_store_req_writeburst_address;
        writeburst_data_reg <= ao486_transducer_store_req_writeburst_data;
        writeburst_length_reg <= ao486_transducer_store_req_writeburst_length[2:0];
        new_store_req <= 1'b1;
    end
    else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
        new_store_req <= 0;
        if(number_of_store_requests == 2'b01) begin
            addr_reg_store <= 0;
        end
    end
end
//..........................................................................

//always block to set request_size to be used in case statements for transducer_l15_size
always @(posedge clk) begin
    if(~rst_n) begin
        request_size <= 4'd0;
    end
    else if(state_reg == IFILL) begin
        request_size <= 4'b0100;
    end
    else if(state_reg == STORE) begin
        if(writeburst_length_reg == 3'b001) begin
            request_size <= 4'b0001;
        end
        else if(number_of_store_requests == 2'b01 & alignment_store == ALIGNED_STORE & writeburst_length_reg == 3'b010) begin
            request_size <= 4'b0010;
        end
        else if(number_of_store_requests == 2'b01 & alignment_store == ALIGNED_STORE & writeburst_length_reg == 3'b100) begin
            request_size <= 4'b0100;
        end
        else if(double_store) begin
            if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & ~first_store_ack) begin
                request_size <= {1'b0, store_length_1};
            end
            else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val & ~second_store_ack) begin
                request_size <= {1'b0, store_length_2};
            end
        end
        else if(triple_store) begin
            if(transducer_l15_rqtype_reg == `STORE_RQ & ~l15_transducer_header_ack & next_state_store != STORE & ~first_store_ack) begin
                request_size <= {1'b0, store_length_1};
            end
            else if(l15_transducer_returntype == `ST_ACK & l15_transducer_val) begin
                if(~second_store_ack) begin
                    request_size <= {1'b0, store_length_2};
                end
                else if(~third_store_ack) begin
                    request_size <= {1'b0, store_length_3};
                end
            end
        end
    end
    else if(state_reg == LOAD) begin
        if(readburst_length_reg == 4'b0001) begin
            request_size <= 4'b0001;
        end
        else if(number_of_load_requests == 2'b01 & alignment_load) begin
            request_size <= readburst_length_reg;
        end
        else if(~alignment_load) begin
            request_size <= unaligned_load_size;
        end
    end
end
//..........................................................................

//Always block to flop address received from core                                                                      (verified)
always @(posedge clk) begin
  if (~rst_n) begin
    addr_reg <= 32'd0;
    double_access <= 1'b0;
    ifill_double_access_first_address <= 32'd0;
    ifill_double_access_second_address <= 32'd0;
  end 
  else if (flop_bus) begin
    if(ao486_transducer_ifill_req_readcode_address[4] & (| ao486_transducer_ifill_req_readcode_address[3:2])) begin
        double_access <= 1'b1;
        ifill_double_access_first_address <= {ao486_transducer_ifill_req_readcode_address[31:5], ao486_transducer_ifill_req_readcode_address[4:0]};
        ifill_double_access_second_address <= {ao486_transducer_ifill_req_readcode_address[31:5] + 1'b1, ao486_transducer_ifill_req_readcode_address[4:0]};
    end
    else begin
        addr_reg <= ao486_transducer_ifill_req_readcode_address;
        double_access <= 1'b0;
    end
  end
  else if(l15_transducer_returntype == `IFILL_RET & l15_transducer_val == 1'b1 & (double_access_count == 2'd1)) begin
      double_access <= 1'b0;
  end
end
//..........................................................................

//Always block to set request size from TRI to L1.5                                                                   (Verified)
always @* begin
    case (request_size)
    4'b0001: begin
        transducer_l15_req_size_reg = `MSG_DATA_SIZE_1B;
    end
    4'b0010: begin
        transducer_l15_req_size_reg = `MSG_DATA_SIZE_2B;
    end
    4'b0100: begin
        transducer_l15_req_size_reg = `MSG_DATA_SIZE_4B;
    end
    4'b1000: begin
        transducer_l15_req_size_reg = `MSG_DATA_SIZE_8B;
    end
    default: begin
        transducer_l15_req_size_reg = 3'd0;
    end
    endcase
end
//..........................................................................

//Always block to release reset into ao486 core                                                                        (Verified)
always @ (posedge clk) begin                                 
    if (~rst_n) begin
        ao486_int_reg <= 1'b0;
    end
    else if (int_recv) begin
        ao486_int_reg <= 1'b1;
    end
    else if (ao486_int_reg) begin
        ao486_int_reg <= 1'b0;
    end
end
//..........................................................................

//always block to trigger first ifill request-response
always @(posedge clk) begin
    if(ao486_transducer_store_req_writeburst_do) begin
        interrupt_received <= 1'b0;
    end
    else if(l15_transducer_val & l15_transducer_returntype == `INT_RET) begin
        interrupt_received <= 1'b1;
    end
    else if(~rst_n) begin
        interrupt_received <= 1'b0;
    end
end
//..........................................................................

//Always block to obtain interrupt from interrupt controller                                                      (Verified)
always @ * begin
   if (l15_transducer_val) begin
      case(l15_transducer_returntype)
        `LOAD_RET:                        //load response
          begin
             int_recv = 1'b0;
          end
        `ST_ACK:                          //store acknowledge
          begin
             int_recv = 1'b0;
          end
        `INT_RET:                         //interrupt return
          begin
             if (l15_transducer_data_0[17:16] == 2'b01) begin
                int_recv = 1'b1;
             end
             else begin
                int_recv = 1'b0;
             end
          end
        default: begin
           int_recv = 1'b0;
        end
      endcase 
   end
   else begin
       int_recv = 1'b0;
   end
end
//..........................................................................

endmodule