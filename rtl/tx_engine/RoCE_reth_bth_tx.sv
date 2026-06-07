
`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_reth_bth_tx  #(
    parameter DATA_WIDTH          = 256,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8)
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE frame input
     */
    // BTH
    input  wire         s_roce_bth_valid,
    output wire         s_roce_bth_ready,
    // BTH pass trhough
    input  wire [  7:0] s_roce_bth_op_code,
    input  wire [ 15:0] s_roce_bth_p_key,
    input  wire [ 23:0] s_roce_bth_psn,
    input  wire [ 23:0] s_roce_bth_dest_qp,
    input  wire         s_roce_bth_ack_req,
    //RETH
    input  wire [ 63:0] s_roce_reth_v_addr,
    input  wire [ 31:0] s_roce_reth_r_key,
    input  wire [ 31:0] s_roce_reth_length,

    // udp, ip, eth
    input  wire [ 47:0] s_eth_dest_mac,
    input  wire [ 47:0] s_eth_src_mac,
    input  wire [ 15:0] s_eth_type,
    input  wire [  3:0] s_ip_version,
    input  wire [  3:0] s_ip_ihl,
    input  wire [  5:0] s_ip_dscp,
    input  wire [  1:0] s_ip_ecn,
    input  wire [ 15:0] s_ip_identification,
    input  wire [  2:0] s_ip_flags,
    input  wire [ 12:0] s_ip_fragment_offset,
    input  wire [  7:0] s_ip_ttl,
    input  wire [  7:0] s_ip_protocol,
    input  wire [ 15:0] s_ip_header_checksum,
    input  wire [ 31:0] s_ip_source_ip,
    input  wire [ 31:0] s_ip_dest_ip,
    input  wire [ 15:0] s_udp_source_port,
    input  wire [ 15:0] s_udp_dest_port,
    input  wire [ 15:0] s_udp_length,
    input  wire [ 15:0] s_udp_checksum,
    // payload
    input  wire [DATA_WIDTH-1   : 0] s_roce_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1 : 0] s_roce_payload_axis_tkeep,
    input  wire         s_roce_payload_axis_tvalid,
    output wire         s_roce_payload_axis_tready,
    input  wire         s_roce_payload_axis_tlast,
    input  wire         s_roce_payload_axis_tuser,
    /*
     * BTH frame output
     */
    output  wire         m_roce_bth_valid,
    input wire           m_roce_bth_ready,
    output  wire [  7:0] m_roce_bth_op_code,
    output  wire [ 15:0] m_roce_bth_p_key,
    output  wire [ 23:0] m_roce_bth_psn,
    output  wire [ 23:0] m_roce_bth_dest_qp,
    output  wire         m_roce_bth_ack_req,
    output wire [ 47:0] m_eth_dest_mac,
    output wire [ 47:0] m_eth_src_mac,
    output wire [ 15:0] m_eth_type,
    output wire [  3:0] m_ip_version,
    output wire [  3:0] m_ip_ihl,
    output wire [  5:0] m_ip_dscp,
    output wire [  1:0] m_ip_ecn,
    output wire [ 15:0] m_ip_identification,
    output wire [  2:0] m_ip_flags,
    output wire [ 12:0] m_ip_fragment_offset,
    output wire [  7:0] m_ip_ttl,
    output wire [  7:0] m_ip_protocol,
    output wire [ 15:0] m_ip_header_checksum,
    output wire [ 31:0] m_ip_source_ip,
    output wire [ 31:0] m_ip_dest_ip,
    output wire [ 15:0] m_udp_source_port,
    output wire [ 15:0] m_udp_dest_port,
    output wire [ 15:0] m_udp_length,
    output wire [ 15:0] m_udp_checksum,
    output wire [DATA_WIDTH-1 : 0] m_roce_bth_payload_axis_tdata,
    output wire [KEEP_WIDTH-1 : 0] m_roce_bth_payload_axis_tkeep,
    output wire                    m_roce_bth_payload_axis_tvalid,
    input  wire                    m_roce_bth_payload_axis_tready,
    output wire                    m_roce_bth_payload_axis_tlast,
    output wire                    m_roce_bth_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire         busy,

    input  wire [15:0] RoCE_udp_port
);

    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;

    parameter HDR_RETH_SIZE = 16;

    parameter CYCLE_RETH_COUNT = (HDR_RETH_SIZE+BYTE_LANES-1)/BYTE_LANES;

    parameter PTR_WIDTH = $clog2(CYCLE_RETH_COUNT);

    parameter OFFSET_RETH = HDR_RETH_SIZE % BYTE_LANES;


    // bus width assertions
    initial begin
        if (BYTE_LANES * 8 != DATA_WIDTH) begin
            $error("Error: AXI stream interface requires byte (8-bit) granularity (instance %m)");
            $finish;
        end
    end


    /*

RoCE RDMA WRITE Frame.

+--------------------------------------+
|                BTH                   |
+--------------------------------------+
 Field                       Length
 OP code                     1 octet
 Solicited Event             1 bit
 Mig request                 1 bit
 Pad count                   2 bits
 Header version              4 bits
 Partition key               2 octets
 FECN                        1 bit
 BECN                        1 bit
 Reserved                    6 bits
 Queue Pair Number           3 octets
 Ack request                 1 bit
 Reserved                    7 bits
 Packet Sequence Number      3 octets
+--------------------------------------+
|               RETH                   |
+--------------------------------------+
 Field                       Length
 Remote Address              8 octets
 R key                       4 octets
 DMA length                  4 octets
+--------------------------------------+
|               IMMD                   |
+--------------------------------------+
 Field                       Length
 Immediate data              4 octets
+--------------------------------------+
|               AETH                   |
+--------------------------------------+
 Field                       Length
 Syndrome                    1 octet
 Message Sequence Number     3 octets
 
 payload                     length octets
+--------------------------------------+
|               ICRC                   |
+--------------------------------------+
 Field                       Length
 ICRC field                  4 octets

This module receives a RoCEv2 frame with headers fields along side the
payload as AXI streams, combines the headers with the payload, passes through
the UDP headers, and transmits the complete UDP payload as AXI stream interface.

*/

    import RoCE_params::*; // Imports RoCE parameters

    // bus width assertions
    initial begin
        if (DATA_WIDTH > 2048) begin
            $error("Error: AXIS data width must be smaller than 2048 (instance %m)");
            $finish;
        end
    end

    // datapath control signals
    reg store_roce_hdrs;
    
    reg send_roce_header_reg = 1'b0, send_roce_header_next;
    // 0 --> dont send
    // 1 --> pass through payload
    // 2 --> send reth shifted payload
    reg [1:0] send_roce_payload_reg = 2'd0, send_roce_payload_next; // 0 = don't send, 1 = send payload as is, 2 = send payload shifted for RETH;
    reg [PTR_WIDTH-1:0] ptr_reg = 0, ptr_next;

    reg flush_save;
    reg transfer_in_save;

    //reg [15:0] word_count_reg = 16'd0, word_count_next;

    reg [DATA_WIDTH-1   : 0] last_word_data_reg = 0;
    reg [KEEP_WIDTH-1 : 0] last_word_keep_reg = 0;

    reg [ 63:0] roce_reth_v_addr_reg = 64'd0;
    reg [ 31:0] roce_reth_r_key_reg = 32'd0;
    reg [ 31:0] roce_reth_length_reg = 32'd0;

    reg [15:0] udp_source_port_reg = 16'd0;
    reg [15:0] udp_dest_port_reg   = 16'd0;
    reg [15:0] udp_length_reg      = 16'd0;
    reg [15:0] udp_checksum_reg    = 16'd0;

    reg s_roce_bth_ready_reg = 1'b0, s_roce_bth_ready_next;
    reg s_roce_payload_axis_tready_reg = 1'b0, s_roce_payload_axis_tready_next;

    //reg s_udp_hdr_ready_reg = 1'b0, s_udp_hdr_ready_next;
    //reg s_udp_payload_axis_tready_reg = 1'b0, s_udp_payload_axis_tready_next;

    reg m_roce_bth_valid_reg = 1'b0, m_roce_bth_valid_next;
    reg [ 7:0] m_roce_bth_op_code_reg = 8'd0;
    reg [15:0] m_roce_bth_p_key_reg = 16'd0;
    reg [23:0] m_roce_bth_psn_reg = 24'd0;
    reg [23:0] m_roce_bth_dest_qp_reg = 24'd0;
    reg        m_roce_bth_ack_req_reg = 1'd0;
    reg [47:0] m_eth_dest_mac_reg = 48'd0;
    reg [47:0] m_eth_src_mac_reg = 48'd0;
    reg [15:0] m_eth_type_reg = 16'd0;
    reg [ 3:0] m_ip_version_reg = 4'd0;
    reg [ 3:0] m_ip_ihl_reg = 4'd0;
    reg [ 5:0] m_ip_dscp_reg = 6'd0;
    reg [ 1:0] m_ip_ecn_reg = 2'd0;
    reg [15:0] m_ip_identification_reg = 16'd0;
    reg [ 2:0] m_ip_flags_reg = 3'd0;
    reg [12:0] m_ip_fragment_offset_reg = 13'd0;
    reg [ 7:0] m_ip_ttl_reg = 8'd0;
    reg [ 7:0] m_ip_protocol_reg = 8'd0;
    reg [15:0] m_ip_header_checksum_reg = 16'd0;
    reg [31:0] m_ip_source_ip_reg = 32'd0;
    reg [31:0] m_ip_dest_ip_reg = 32'd0;
    reg [15:0] m_udp_source_port_reg = 16'd0;
    reg [15:0] m_udp_dest_port_reg = 16'd0;
    reg [15:0] m_udp_length_reg = 16'd0;
    reg [15:0] m_udp_checksum_reg = 16'd0;

    reg        busy_reg = 1'b0;

    reg [DATA_WIDTH-1 : 0] save_roce_payload_axis_tdata_reg = 0;
    reg [KEEP_WIDTH-1 : 0] save_roce_payload_axis_tkeep_reg = 0;
    reg         save_roce_payload_axis_tlast_reg = 1'b0;
    reg         save_roce_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH-1 : 0] shift_roce_payload_128_axis_tdata;
    reg [KEEP_WIDTH-1 : 0] shift_roce_payload_128_axis_tkeep;
    reg                    shift_roce_payload_128_axis_tvalid;
    reg                    shift_roce_payload_128_axis_tlast;
    reg                    shift_roce_payload_128_axis_tuser;
    reg                    shift_roce_payload_128_axis_input_tready;
    reg                    shift_roce_payload_128_extra_cycle_reg = 1'b0;

    // internal datapath
    reg  [DATA_WIDTH-1 : 0] m_roce_bth_payload_axis_tdata_int;
    reg  [KEEP_WIDTH-1 : 0] m_roce_bth_payload_axis_tkeep_int;
    reg          m_roce_bth_payload_axis_tvalid_int;
    reg          m_roce_bth_payload_axis_tready_int_reg = 1'b0;
    reg          m_roce_bth_payload_axis_tlast_int;
    reg          m_roce_bth_payload_axis_tuser_int;
    wire         m_roce_bth_payload_axis_tready_int_early;

    wire append_reth = s_roce_bth_op_code == RC_RDMA_WRITE_FIRST
    || s_roce_bth_op_code == RC_RDMA_WRITE_ONLY
    || s_roce_bth_op_code == RC_RDMA_WRITE_ONLY_IMD;

    assign s_roce_bth_ready                = s_roce_bth_ready_reg;
    assign s_roce_payload_axis_tready      = s_roce_payload_axis_tready_reg;


    assign m_roce_bth_valid                = m_roce_bth_valid_reg;
    assign m_roce_bth_op_code              = m_roce_bth_op_code_reg;
    assign m_roce_bth_p_key                = m_roce_bth_p_key_reg;
    assign m_roce_bth_psn                  = m_roce_bth_psn_reg;
    assign m_roce_bth_dest_qp              = m_roce_bth_dest_qp_reg;
    assign m_roce_bth_ack_req              = m_roce_bth_ack_req_reg;
    assign m_eth_dest_mac                  = m_eth_dest_mac_reg;
    assign m_eth_src_mac                   = m_eth_src_mac_reg;
    assign m_eth_type                      = m_eth_type_reg;
    assign m_ip_version                    = m_ip_version_reg;
    assign m_ip_ihl                        = m_ip_ihl_reg;
    assign m_ip_dscp                       = m_ip_dscp_reg;
    assign m_ip_ecn                        = m_ip_ecn_reg;
    assign m_ip_identification             = m_ip_identification_reg;
    assign m_ip_flags                      = m_ip_flags_reg;
    assign m_ip_fragment_offset            = m_ip_fragment_offset_reg;
    assign m_ip_ttl                        = m_ip_ttl_reg;
    assign m_ip_protocol                   = m_ip_protocol_reg;
    assign m_ip_header_checksum            = m_ip_header_checksum_reg;
    assign m_ip_source_ip                  = m_ip_source_ip_reg;
    assign m_ip_dest_ip                    = m_ip_dest_ip_reg;

    assign m_udp_source_port               = m_udp_source_port_reg;
    assign m_udp_dest_port                 = m_udp_dest_port_reg;
    assign m_udp_length                    = m_udp_length_reg;
    assign m_udp_checksum                  = m_udp_checksum_reg;

    assign busy                            = busy_reg;



    // RETH
    always @* begin
        if (OFFSET_RETH == 0) begin
            // passthrough if no overlap
            shift_roce_payload_128_axis_tdata  = s_roce_payload_axis_tdata;
            shift_roce_payload_128_axis_tkeep  = s_roce_payload_axis_tkeep;
            shift_roce_payload_128_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_128_axis_tlast  = s_roce_payload_axis_tlast;
            shift_roce_payload_128_axis_tuser  = s_roce_payload_axis_tuser;
            shift_roce_payload_128_axis_input_tready = 1'b1;
        end else if (shift_roce_payload_128_extra_cycle_reg) begin
            shift_roce_payload_128_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_RETH)*8);
            shift_roce_payload_128_axis_tkeep = {{KEEP_WIDTH{1'b0}}       , save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_RETH);
            shift_roce_payload_128_axis_tvalid = 1'b1;
            shift_roce_payload_128_axis_tlast = save_roce_payload_axis_tlast_reg;
            shift_roce_payload_128_axis_tuser = save_roce_payload_axis_tuser_reg;
            shift_roce_payload_128_axis_input_tready = flush_save;
        end else begin
            shift_roce_payload_128_axis_tdata = {s_roce_payload_axis_tdata, save_roce_payload_axis_tdata_reg} >> ((KEEP_WIDTH-OFFSET_RETH)*8);
            shift_roce_payload_128_axis_tkeep = {s_roce_payload_axis_tkeep, save_roce_payload_axis_tkeep_reg} >> (KEEP_WIDTH-OFFSET_RETH);
            shift_roce_payload_128_axis_tvalid = s_roce_payload_axis_tvalid;
            shift_roce_payload_128_axis_tlast = (s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_RETH))) == 0));
            shift_roce_payload_128_axis_tuser = (s_roce_payload_axis_tuser && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_RETH))) == 0));
            shift_roce_payload_128_axis_input_tready = !(s_roce_payload_axis_tlast && s_roce_payload_axis_tready && s_roce_payload_axis_tvalid);
        end
    end


    always @* begin
        send_roce_header_next = send_roce_header_reg;
        send_roce_payload_next = send_roce_payload_reg;
        ptr_next = ptr_reg;

        s_roce_bth_ready_next = 1'b0;
        s_roce_payload_axis_tready_next = 1'b0;

        m_roce_bth_valid_next = m_roce_bth_valid_reg && !m_roce_bth_ready;

        store_roce_hdrs = 1'b0;

        flush_save = 1'b0;
        transfer_in_save = 1'b0;

        m_roce_bth_payload_axis_tdata_int = {DATA_WIDTH{1'b0}};
        m_roce_bth_payload_axis_tkeep_int = {KEEP_WIDTH{1'b0}};
        m_roce_bth_payload_axis_tvalid_int = 1'b0;
        m_roce_bth_payload_axis_tlast_int = 1'b0;
        m_roce_bth_payload_axis_tuser_int = 1'b0;


        if (s_roce_bth_ready && s_roce_bth_valid ) begin
            store_roce_hdrs = 1'b1;
            ptr_next = 0;
            if (append_reth) begin
                m_roce_bth_valid_next = 1'b1;
                send_roce_header_next = 1'b1;
                send_roce_payload_next = (OFFSET_RETH != 0) && (CYCLE_RETH_COUNT == 1) ? 2'd2 : 2'd0;
                s_roce_payload_axis_tready_next = (send_roce_payload_next) && m_roce_bth_payload_axis_tready_int_early;

            end else begin // pass through payload if no RETH
                m_roce_bth_valid_next = 1'b1;
                send_roce_payload_next =  2'd1;
                s_roce_payload_axis_tready_next =  m_roce_bth_payload_axis_tready_int_early;
            end
        end

        if (send_roce_payload_reg == 2'd1) begin // pass through payload
            s_roce_payload_axis_tready_next = m_roce_bth_payload_axis_tready_int_early;

            m_roce_bth_payload_axis_tdata_int = s_roce_payload_axis_tdata;
            m_roce_bth_payload_axis_tkeep_int = s_roce_payload_axis_tkeep;
            m_roce_bth_payload_axis_tlast_int = s_roce_payload_axis_tlast;
            m_roce_bth_payload_axis_tuser_int = s_roce_payload_axis_tuser;

            if (s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) begin
                transfer_in_save = 1'b1;

                m_roce_bth_payload_axis_tvalid_int = 1'b1;

                if (s_roce_payload_axis_tlast) begin
                    flush_save = 1'b1;
                    s_roce_payload_axis_tready_next = 1'b0;
                    ptr_next = 0;
                    send_roce_payload_next = 2'd0;
                end
            end
        end else if (send_roce_payload_reg == 2'd2) begin // send RETH shifted payload
            s_roce_payload_axis_tready_next = m_roce_bth_payload_axis_tready_int_early && shift_roce_payload_128_axis_input_tready;

            m_roce_bth_payload_axis_tdata_int = shift_roce_payload_128_axis_tdata;
            m_roce_bth_payload_axis_tkeep_int = shift_roce_payload_128_axis_tkeep;
            m_roce_bth_payload_axis_tlast_int = shift_roce_payload_128_axis_tlast;
            m_roce_bth_payload_axis_tuser_int = shift_roce_payload_128_axis_tuser;

            if ((s_roce_payload_axis_tready && s_roce_payload_axis_tvalid) || (m_roce_bth_payload_axis_tready_int_reg && shift_roce_payload_128_extra_cycle_reg)) begin
                transfer_in_save = 1'b1;

                m_roce_bth_payload_axis_tvalid_int = 1'b1;

                if (shift_roce_payload_128_axis_tlast) begin
                    flush_save = 1'b1;
                    s_roce_payload_axis_tready_next = 1'b0;
                    ptr_next = 0;
                    send_roce_payload_next = 2'd0;
                end
            end
        end

        if (m_roce_bth_payload_axis_tready_int_reg && (!OFFSET_RETH || (send_roce_payload_reg == 2'd0) || m_roce_bth_payload_axis_tvalid_int)) begin
            if (send_roce_header_reg) begin
                ptr_next = ptr_reg + 1;

                if ((OFFSET_RETH != 0) && (CYCLE_RETH_COUNT == 1 || ptr_next == CYCLE_RETH_COUNT-1) && (send_roce_payload_reg == 2'd0)) begin
                    send_roce_payload_next = 2'd2;
                    s_roce_payload_axis_tready_next = m_roce_bth_payload_axis_tready_int_early && shift_roce_payload_128_axis_input_tready;
                end

                m_roce_bth_payload_axis_tvalid_int = 1'b1;
    
                `define _HEADER_RETH_FIELD_(offset, field) \
                    if (ptr_reg == offset/BYTE_LANES) begin \
                        m_roce_bth_payload_axis_tdata_int[(offset%BYTE_LANES)*8 +: 8] = field; \
                        m_roce_bth_payload_axis_tkeep_int[offset%BYTE_LANES] = 1'b1; \
                    end

                `_HEADER_RETH_FIELD_(0, roce_reth_v_addr_reg[7*8 +: 8])
                `_HEADER_RETH_FIELD_(1, roce_reth_v_addr_reg[6*8 +: 8])
                `_HEADER_RETH_FIELD_(2, roce_reth_v_addr_reg[5*8 +: 8])
                `_HEADER_RETH_FIELD_(3, roce_reth_v_addr_reg[4*8 +: 8])
                `_HEADER_RETH_FIELD_(4, roce_reth_v_addr_reg[3*8 +: 8])
                `_HEADER_RETH_FIELD_(5, roce_reth_v_addr_reg[2*8 +: 8])
                `_HEADER_RETH_FIELD_(6, roce_reth_v_addr_reg[1*8 +: 8])
                `_HEADER_RETH_FIELD_(7, roce_reth_v_addr_reg[0*8 +: 8])
                `_HEADER_RETH_FIELD_(8, roce_reth_r_key_reg[3*8 +: 8])
                `_HEADER_RETH_FIELD_(9, roce_reth_r_key_reg[2*8 +: 8])
                `_HEADER_RETH_FIELD_(10, roce_reth_r_key_reg[1*8 +: 8])
                `_HEADER_RETH_FIELD_(11, roce_reth_r_key_reg[0*8 +: 8])
                `_HEADER_RETH_FIELD_(12, roce_reth_length_reg[3*8 +: 8])
                `_HEADER_RETH_FIELD_(13, roce_reth_length_reg[2*8 +: 8])
                `_HEADER_RETH_FIELD_(14, roce_reth_length_reg[1*8 +: 8])
                `_HEADER_RETH_FIELD_(15, roce_reth_length_reg[0*8 +: 8])

                if (ptr_reg == (HDR_RETH_SIZE-1)/BYTE_LANES) begin
                    if (send_roce_payload_reg == 2'd0) begin
                        s_roce_payload_axis_tready_next = m_roce_bth_payload_axis_tready_int_early;
                        send_roce_payload_next = 2'd2;
                    end
                    send_roce_header_next = 1'b0;
                end
    
                `undef _HEADER_RETH_FIELD_
            end
        end

        s_roce_bth_ready_next = !m_roce_bth_valid_next && !((send_roce_header_next != 1'b0) || (send_roce_payload_next != 2'd0));
    end

    always @(posedge clk) begin
        send_roce_header_reg <= send_roce_header_next;
        send_roce_payload_reg <= send_roce_payload_next;
        ptr_reg <= ptr_next;

        s_roce_bth_ready_reg <= s_roce_bth_ready_next;
        s_roce_payload_axis_tready_reg <= s_roce_payload_axis_tready_next;

        m_roce_bth_valid_reg <= m_roce_bth_valid_next;

        busy_reg <= (send_roce_header_next != 1'b0) || (send_roce_payload_next != 2'd0);

        if (store_roce_hdrs) begin
            m_roce_bth_op_code_reg <= s_roce_bth_op_code;
            m_roce_bth_p_key_reg   <= s_roce_bth_p_key;
            m_roce_bth_psn_reg     <= s_roce_bth_psn;
            m_roce_bth_dest_qp_reg <= s_roce_bth_dest_qp;
            m_roce_bth_ack_req_reg <= s_roce_bth_ack_req;

            m_eth_dest_mac_reg <= s_eth_dest_mac;
            m_eth_src_mac_reg <= s_eth_src_mac;
            m_eth_type_reg <= s_eth_type;
            m_ip_version_reg <= s_ip_version;
            m_ip_ihl_reg <= s_ip_ihl;
            m_ip_dscp_reg <= s_ip_dscp;
            m_ip_ecn_reg <= s_ip_ecn;
            m_ip_identification_reg <= s_ip_identification;
            m_ip_flags_reg <= s_ip_flags;
            m_ip_fragment_offset_reg <= s_ip_fragment_offset;
            m_ip_ttl_reg <= s_ip_ttl;
            m_ip_protocol_reg <= s_ip_protocol;
            m_ip_header_checksum_reg <= s_ip_header_checksum;
            m_ip_source_ip_reg <= s_ip_source_ip;
            m_ip_dest_ip_reg <= s_ip_dest_ip;
            m_udp_source_port_reg <= s_udp_source_port;
            m_udp_dest_port_reg <= RoCE_udp_port;
            m_udp_length_reg <= s_udp_length;
            m_udp_checksum_reg <= 16'h0000;


            if (s_roce_bth_valid && append_reth) begin
                roce_reth_v_addr_reg = s_roce_reth_v_addr;
                roce_reth_r_key_reg  = s_roce_reth_r_key;
                roce_reth_length_reg = s_roce_reth_length;
            end
        end

        if (transfer_in_save) begin
            save_roce_payload_axis_tdata_reg <= s_roce_payload_axis_tdata;
            save_roce_payload_axis_tkeep_reg <= s_roce_payload_axis_tkeep;
            save_roce_payload_axis_tuser_reg <= s_roce_payload_axis_tuser;
        end

        if (flush_save) begin
            save_roce_payload_axis_tlast_reg <= 1'b0;
            shift_roce_payload_128_extra_cycle_reg <= 1'b0;
        end else if (transfer_in_save) begin
            save_roce_payload_axis_tlast_reg <= s_roce_payload_axis_tlast;
            shift_roce_payload_128_extra_cycle_reg <= OFFSET_RETH ? s_roce_payload_axis_tlast && ((s_roce_payload_axis_tkeep & ({KEEP_WIDTH{1'b1}} << (KEEP_WIDTH-OFFSET_RETH))) != 0) : 1'b0;
        end

        if (rst) begin
            send_roce_header_reg <= 1'b0;
            send_roce_payload_reg <= 2'd0;
            ptr_reg <= 0;
            s_roce_bth_ready_reg <= 1'b0;
            s_roce_payload_axis_tready_reg <= 1'b0;
            m_roce_bth_valid_reg <= 1'b0;
            busy_reg <= 1'b0;
        end
    end

    // output datapath logic
    reg [DATA_WIDTH   - 1 :0] m_roce_bth_payload_axis_tdata_reg = 0;
    reg [KEEP_WIDTH - 1 :0] m_roce_bth_payload_axis_tkeep_reg = 0;
    reg m_roce_bth_payload_axis_tvalid_reg = 1'b0, m_roce_bth_payload_axis_tvalid_next;
    reg         m_roce_bth_payload_axis_tlast_reg = 1'b0;
    reg         m_roce_bth_payload_axis_tuser_reg = 1'b0;

    reg [DATA_WIDTH   - 1 :0] temp_m_roce_bth_payload_axis_tdata_reg = 0;
    reg [KEEP_WIDTH - 1 :0] temp_m_roce_bth_payload_axis_tkeep_reg = 0;
    reg temp_m_roce_bth_payload_axis_tvalid_reg = 1'b0, temp_m_roce_bth_payload_axis_tvalid_next;
    reg temp_m_roce_bth_payload_axis_tlast_reg = 1'b0;
    reg temp_m_roce_bth_payload_axis_tuser_reg = 1'b0;

    // datapath control
    reg store_udp_payload_int_to_output;
    reg store_udp_payload_int_to_temp;
    reg store_udp_payload_axis_temp_to_output;

    assign m_roce_bth_payload_axis_tdata = m_roce_bth_payload_axis_tdata_reg;
    assign m_roce_bth_payload_axis_tkeep = m_roce_bth_payload_axis_tkeep_reg;
    assign m_roce_bth_payload_axis_tvalid = m_roce_bth_payload_axis_tvalid_reg;
    assign m_roce_bth_payload_axis_tlast = m_roce_bth_payload_axis_tlast_reg;
    assign m_roce_bth_payload_axis_tuser = m_roce_bth_payload_axis_tuser_reg;

    // enable ready input next cycle if output is ready or if both output registers are empty
    assign m_roce_bth_payload_axis_tready_int_early = m_roce_bth_payload_axis_tready || (!temp_m_roce_bth_payload_axis_tvalid_reg && !m_roce_bth_payload_axis_tvalid_reg);

    always @* begin
        // transfer sink ready state to source
        m_roce_bth_payload_axis_tvalid_next = m_roce_bth_payload_axis_tvalid_reg;
        temp_m_roce_bth_payload_axis_tvalid_next = temp_m_roce_bth_payload_axis_tvalid_reg;

        store_udp_payload_int_to_output = 1'b0;
        store_udp_payload_int_to_temp = 1'b0;
        store_udp_payload_axis_temp_to_output = 1'b0;

        if (m_roce_bth_payload_axis_tready_int_reg) begin
            // input is ready
            if (m_roce_bth_payload_axis_tready | !m_roce_bth_payload_axis_tvalid_reg) begin
                // output is ready or currently not valid, transfer data to output
                m_roce_bth_payload_axis_tvalid_next  = m_roce_bth_payload_axis_tvalid_int;
                store_udp_payload_int_to_output = 1'b1;
            end else begin
                // output is not ready, store input in temp
                temp_m_roce_bth_payload_axis_tvalid_next = m_roce_bth_payload_axis_tvalid_int;
                store_udp_payload_int_to_temp = 1'b1;
            end
        end else if (m_roce_bth_payload_axis_tready) begin
            // input is not ready, but output is ready
            m_roce_bth_payload_axis_tvalid_next = temp_m_roce_bth_payload_axis_tvalid_reg;
            temp_m_roce_bth_payload_axis_tvalid_next = 1'b0;
            store_udp_payload_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk) begin
        m_roce_bth_payload_axis_tvalid_reg <= m_roce_bth_payload_axis_tvalid_next;
        m_roce_bth_payload_axis_tready_int_reg <= m_roce_bth_payload_axis_tready_int_early;
        temp_m_roce_bth_payload_axis_tvalid_reg <= temp_m_roce_bth_payload_axis_tvalid_next;

        // datapath
        if (store_udp_payload_int_to_output) begin
            m_roce_bth_payload_axis_tdata_reg <= m_roce_bth_payload_axis_tdata_int;
            m_roce_bth_payload_axis_tkeep_reg <= m_roce_bth_payload_axis_tkeep_int;
            m_roce_bth_payload_axis_tlast_reg <= m_roce_bth_payload_axis_tlast_int;
            m_roce_bth_payload_axis_tuser_reg <= m_roce_bth_payload_axis_tuser_int;
        end else if (store_udp_payload_axis_temp_to_output) begin
            m_roce_bth_payload_axis_tdata_reg <= temp_m_roce_bth_payload_axis_tdata_reg;
            m_roce_bth_payload_axis_tkeep_reg <= temp_m_roce_bth_payload_axis_tkeep_reg;
            m_roce_bth_payload_axis_tlast_reg <= temp_m_roce_bth_payload_axis_tlast_reg;
            m_roce_bth_payload_axis_tuser_reg <= temp_m_roce_bth_payload_axis_tuser_reg;
        end

        if (store_udp_payload_int_to_temp) begin
            temp_m_roce_bth_payload_axis_tdata_reg <= m_roce_bth_payload_axis_tdata_int;
            temp_m_roce_bth_payload_axis_tkeep_reg <= m_roce_bth_payload_axis_tkeep_int;
            temp_m_roce_bth_payload_axis_tlast_reg <= m_roce_bth_payload_axis_tlast_int;
            temp_m_roce_bth_payload_axis_tuser_reg <= m_roce_bth_payload_axis_tuser_int;
        end

        if (rst) begin
            m_roce_bth_payload_axis_tvalid_reg <= 1'b0;
            m_roce_bth_payload_axis_tready_int_reg <= 1'b0;
            temp_m_roce_bth_payload_axis_tvalid_reg <= 1'b0;
        end
    end

endmodule

`resetall
