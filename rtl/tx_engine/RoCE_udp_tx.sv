
`resetall `timescale 1ns / 1ps `default_nettype none

module RoCE_udp_tx  #(
    parameter DATA_WIDTH          = 256,
    // Propagate tkeep signal
    // If disabled, tkeep assumed to be 1'b1
    parameter KEEP_ENABLE = (DATA_WIDTH>8),
    // tkeep signal width (words per cycle)
    parameter KEEP_WIDTH = (DATA_WIDTH/8),
    // migration request value (hardcoded)
    parameter MIG_REQ = 1'b1,
    // Forward ECN (hardcoded) BECN not relevan for SEND or WRITE packets
    parameter FECN = 1'b1
) (
    input wire clk,
    input wire rst,

    /*
     * RoCE frame input
     */
    // BTH
    input  wire         s_roce_bth_valid,
    output wire         s_roce_bth_ready,
    input  wire [  7:0] s_roce_bth_op_code,
    input  wire [ 15:0] s_roce_bth_p_key,
    input  wire [ 23:0] s_roce_bth_psn,
    input  wire [ 23:0] s_roce_bth_dest_qp,
    input  wire         s_roce_bth_ack_req,
    // RETH
    input  wire [ 63:0] s_roce_reth_v_addr,
    input  wire [ 31:0] s_roce_reth_r_key,
    input  wire [ 31:0] s_roce_reth_length,
    // IMMD
    input  wire [ 31:0] s_roce_immdh_data,
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
     * UDP frame output
     */
    output wire         m_udp_hdr_valid,
    input  wire         m_udp_hdr_ready,
    output wire [ 47:0] m_eth_dest_mac,
    output wire [ 47:0] m_eth_src_mac,
    output wire [ 15:0] m_eth_type,
    output wire [  3:0] m_ip_version,
    output wire [  3:0] m_ip_ihl,
    output wire [  5:0] m_ip_dscp,
    output wire [  1:0] m_ip_ecn,
    output wire [ 15:0] m_ip_length,
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
    output wire [DATA_WIDTH-1   : 0] m_udp_payload_axis_tdata,
    output wire [KEEP_WIDTH-1 : 0] m_udp_payload_axis_tkeep,
    output wire         m_udp_payload_axis_tvalid,
    input  wire         m_udp_payload_axis_tready,
    output wire         m_udp_payload_axis_tlast,
    output wire         m_udp_payload_axis_tuser,
    /*
     * Status signals
     */
    output wire         busy,
    output wire         error_payload_early_termination,
    /*
     * Config
     */
    input  wire [              15:0] RoCE_udp_port
);

    parameter BYTE_LANES = KEEP_ENABLE ? KEEP_WIDTH : 1;


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

    wire         roce_immdh_bth_valid;
    wire         roce_immdh_bth_ready;
    wire [  7:0] roce_immdh_bth_op_code;
    wire [ 15:0] roce_immdh_bth_p_key;
    wire [ 23:0] roce_immdh_bth_psn;
    wire [ 23:0] roce_immdh_bth_dest_qp;
    wire         roce_immdh_bth_ack_req;

    wire [ 63:0] roce_immdh_reth_v_addr;
    wire [ 31:0] roce_immdh_reth_r_key;
    wire [ 31:0] roce_immdh_reth_length;

    wire [ 47:0] roce_immdh_eth_dest_mac;
    wire [ 47:0] roce_immdh_eth_src_mac;
    wire [ 15:0] roce_immdh_eth_type;
    wire [  3:0] roce_immdh_ip_version;
    wire [  3:0] roce_immdh_ip_ihl;
    wire [  5:0] roce_immdh_ip_dscp;
    wire [  1:0] roce_immdh_ip_ecn;
    wire [ 15:0] roce_immdh_ip_identification;
    wire [  2:0] roce_immdh_ip_flags;
    wire [ 12:0] roce_immdh_ip_fragment_offset;
    wire [  7:0] roce_immdh_ip_ttl;
    wire [  7:0] roce_immdh_ip_protocol;
    wire [ 15:0] roce_immdh_ip_header_checksum;
    wire [ 31:0] roce_immdh_ip_source_ip;
    wire [ 31:0] roce_immdh_ip_dest_ip;
    wire [ 15:0] roce_immdh_udp_source_port;
    wire [ 15:0] roce_immdh_udp_dest_port;
    wire [ 15:0] roce_immdh_udp_length;
    wire [ 15:0] roce_immdh_udp_checksum;

    wire [DATA_WIDTH-1 : 0] roce_immdh_payload_axis_tdata;
    wire [KEEP_WIDTH-1 : 0] roce_immdh_payload_axis_tkeep;
    wire                    roce_immdh_payload_axis_tvalid;
    wire                    roce_immdh_payload_axis_tready;
    wire                    roce_immdh_payload_axis_tlast;
    wire                    roce_immdh_payload_axis_tuser;

    wire         roce_reth_bth_valid;
    wire         roce_reth_bth_ready;
    wire [  7:0] roce_reth_bth_op_code;
    wire [ 15:0] roce_reth_bth_p_key;
    wire [ 23:0] roce_reth_bth_psn;
    wire [ 23:0] roce_reth_bth_dest_qp;
    wire         roce_reth_bth_ack_req;

    wire [ 47:0] roce_reth_eth_dest_mac;
    wire [ 47:0] roce_reth_eth_src_mac;
    wire [ 15:0] roce_reth_eth_type;
    wire [  3:0] roce_reth_ip_version;
    wire [  3:0] roce_reth_ip_ihl;
    wire [  5:0] roce_reth_ip_dscp;
    wire [  1:0] roce_reth_ip_ecn;
    wire [ 15:0] roce_reth_ip_identification;
    wire [  2:0] roce_reth_ip_flags;
    wire [ 12:0] roce_reth_ip_fragment_offset;
    wire [  7:0] roce_reth_ip_ttl;
    wire [  7:0] roce_reth_ip_protocol;
    wire [ 15:0] roce_reth_ip_header_checksum;
    wire [ 31:0] roce_reth_ip_source_ip;
    wire [ 31:0] roce_reth_ip_dest_ip;
    wire [ 15:0] roce_reth_udp_source_port;
    wire [ 15:0] roce_reth_udp_dest_port;
    wire [ 15:0] roce_reth_udp_length;
    wire [ 15:0] roce_reth_udp_checksum;

    wire [DATA_WIDTH-1 : 0] roce_reth_payload_axis_tdata;
    wire [KEEP_WIDTH-1 : 0] roce_reth_payload_axis_tkeep;
    wire                    roce_reth_payload_axis_tvalid;
    wire                    roce_reth_payload_axis_tready;
    wire                    roce_reth_payload_axis_tlast;
    wire                    roce_reth_payload_axis_tuser;

    RoCE_immdh_reth_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(KEEP_ENABLE),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) RoCE_immdh_reth_tx_instance (
        .clk(clk),
        .rst(rst),
        .s_roce_bth_valid    (s_roce_bth_valid),
        .s_roce_bth_ready    (s_roce_bth_ready),
        .s_roce_bth_op_code  (s_roce_bth_op_code),
        .s_roce_bth_p_key    (s_roce_bth_p_key),
        .s_roce_bth_psn      (s_roce_bth_psn),
        .s_roce_bth_dest_qp  (s_roce_bth_dest_qp),
        .s_roce_bth_ack_req  (s_roce_bth_ack_req),
        .s_roce_reth_v_addr  (s_roce_reth_v_addr),
        .s_roce_reth_r_key   (s_roce_reth_r_key),
        .s_roce_reth_length  (s_roce_reth_length),
        .s_roce_immdh_data   (s_roce_immdh_data),
        .s_eth_dest_mac      (s_eth_dest_mac),
        .s_eth_src_mac       (s_eth_src_mac),
        .s_eth_type          (s_eth_type),
        .s_ip_version        (s_ip_version),
        .s_ip_ihl            (s_ip_ihl),
        .s_ip_dscp           (s_ip_dscp),
        .s_ip_ecn            (s_ip_ecn),
        .s_ip_identification (s_ip_identification),
        .s_ip_flags          (s_ip_flags),
        .s_ip_fragment_offset(s_ip_fragment_offset),
        .s_ip_ttl            (s_ip_ttl),
        .s_ip_protocol       (s_ip_protocol),
        .s_ip_header_checksum(s_ip_header_checksum),
        .s_ip_source_ip      (s_ip_source_ip),
        .s_ip_dest_ip        (s_ip_dest_ip),
        .s_udp_source_port   (s_udp_source_port),
        .s_udp_dest_port     (s_udp_dest_port),
        .s_udp_length        (s_udp_length),
        .s_udp_checksum      (s_udp_checksum),

        .s_roce_payload_axis_tdata (s_roce_payload_axis_tdata),
        .s_roce_payload_axis_tkeep (s_roce_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid(s_roce_payload_axis_tvalid),
        .s_roce_payload_axis_tready(s_roce_payload_axis_tready),
        .s_roce_payload_axis_tlast (s_roce_payload_axis_tlast),
        .s_roce_payload_axis_tuser (s_roce_payload_axis_tuser),

        .m_roce_bth_valid   (roce_immdh_bth_valid),
        .m_roce_bth_ready   (roce_immdh_bth_ready),
        .m_roce_bth_op_code (roce_immdh_bth_op_code),
        .m_roce_bth_p_key   (roce_immdh_bth_p_key),
        .m_roce_bth_psn     (roce_immdh_bth_psn),
        .m_roce_bth_dest_qp (roce_immdh_bth_dest_qp),
        .m_roce_bth_ack_req (roce_immdh_bth_ack_req),

        .m_roce_reth_v_addr (roce_immdh_reth_v_addr),
        .m_roce_reth_r_key  (roce_immdh_reth_r_key),
        .m_roce_reth_length (roce_immdh_reth_length),

        .m_eth_dest_mac      (roce_immdh_eth_dest_mac),
        .m_eth_src_mac       (roce_immdh_eth_src_mac),
        .m_eth_type          (roce_immdh_eth_type),
        .m_ip_version        (roce_immdh_ip_version),
        .m_ip_ihl            (roce_immdh_ip_ihl),
        .m_ip_dscp           (roce_immdh_ip_dscp),
        .m_ip_ecn            (roce_immdh_ip_ecn),
        .m_ip_identification (roce_immdh_ip_identification),
        .m_ip_flags          (roce_immdh_ip_flags),
        .m_ip_fragment_offset(roce_immdh_ip_fragment_offset),
        .m_ip_ttl            (roce_immdh_ip_ttl),
        .m_ip_protocol       (roce_immdh_ip_protocol),
        .m_ip_header_checksum(roce_immdh_ip_header_checksum),
        .m_ip_source_ip      (roce_immdh_ip_source_ip),
        .m_ip_dest_ip        (roce_immdh_ip_dest_ip),
        .m_udp_source_port   (roce_immdh_udp_source_port),
        .m_udp_dest_port     (roce_immdh_udp_dest_port),
        .m_udp_length        (roce_immdh_udp_length),
        .m_udp_checksum      (roce_immdh_udp_checksum),

        .m_roce_bth_payload_axis_tdata (roce_immdh_payload_axis_tdata),
        .m_roce_bth_payload_axis_tkeep (roce_immdh_payload_axis_tkeep),
        .m_roce_bth_payload_axis_tvalid(roce_immdh_payload_axis_tvalid),
        .m_roce_bth_payload_axis_tready(roce_immdh_payload_axis_tready),
        .m_roce_bth_payload_axis_tlast (roce_immdh_payload_axis_tlast),
        .m_roce_bth_payload_axis_tuser (roce_immdh_payload_axis_tuser)
    );

    RoCE_reth_bth_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(KEEP_ENABLE),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) RoCE_reth_bth_tx_instance (
        .clk(clk),
        .rst(rst),
        .s_roce_bth_valid    (roce_immdh_bth_valid),
        .s_roce_bth_ready    (roce_immdh_bth_ready),
        .s_roce_bth_op_code  (roce_immdh_bth_op_code),
        .s_roce_bth_p_key    (roce_immdh_bth_p_key),
        .s_roce_bth_psn      (roce_immdh_bth_psn),
        .s_roce_bth_dest_qp  (roce_immdh_bth_dest_qp),
        .s_roce_bth_ack_req  (roce_immdh_bth_ack_req),
        .s_roce_reth_v_addr  (roce_immdh_reth_v_addr),
        .s_roce_reth_r_key   (roce_immdh_reth_r_key),
        .s_roce_reth_length  (roce_immdh_reth_length),
        .s_eth_src_mac       (roce_immdh_eth_src_mac),
        .s_eth_type          (roce_immdh_eth_type),
        .s_ip_version        (roce_immdh_ip_version),
        .s_ip_ihl            (roce_immdh_ip_ihl),
        .s_ip_dscp           (roce_immdh_ip_dscp),
        .s_ip_ecn            (roce_immdh_ip_ecn),
        .s_ip_identification (roce_immdh_ip_identification),
        .s_ip_flags          (roce_immdh_ip_flags),
        .s_ip_fragment_offset(roce_immdh_ip_fragment_offset),
        .s_ip_ttl            (roce_immdh_ip_ttl),
        .s_ip_protocol       (roce_immdh_ip_protocol),
        .s_ip_header_checksum(roce_immdh_ip_header_checksum),
        .s_ip_source_ip      (roce_immdh_ip_source_ip),
        .s_ip_dest_ip        (roce_immdh_ip_dest_ip),
        .s_udp_source_port   (roce_immdh_udp_source_port),
        .s_udp_dest_port     (roce_immdh_udp_dest_port),
        .s_udp_length        (roce_immdh_udp_length),
        .s_udp_checksum      (roce_immdh_udp_checksum),

        .s_roce_payload_axis_tdata (roce_immdh_payload_axis_tdata),
        .s_roce_payload_axis_tkeep (roce_immdh_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid(roce_immdh_payload_axis_tvalid),
        .s_roce_payload_axis_tready(roce_immdh_payload_axis_tready),
        .s_roce_payload_axis_tlast (roce_immdh_payload_axis_tlast),
        .s_roce_payload_axis_tuser (roce_immdh_payload_axis_tuser),

        .m_roce_bth_valid    (roce_reth_bth_valid),
        .m_roce_bth_ready    (roce_reth_bth_ready),
        .m_roce_bth_op_code  (roce_reth_bth_op_code),
        .m_roce_bth_p_key    (roce_reth_bth_p_key),
        .m_roce_bth_psn      (roce_reth_bth_psn),
        .m_roce_bth_dest_qp  (roce_reth_bth_dest_qp),
        .m_roce_bth_ack_req  (roce_reth_bth_ack_req),
        .m_eth_dest_mac      (roce_reth_eth_dest_mac),
        .m_eth_src_mac       (roce_reth_eth_src_mac),
        .m_eth_type          (roce_reth_eth_type),
        .m_ip_version        (roce_reth_ip_version),
        .m_ip_ihl            (roce_reth_ip_ihl),
        .m_ip_dscp           (roce_reth_ip_dscp),
        .m_ip_ecn            (roce_reth_ip_ecn),
        .m_ip_identification (roce_reth_ip_identification),
        .m_ip_flags          (roce_reth_ip_flags),
        .m_ip_fragment_offset(roce_reth_ip_fragment_offset),
        .m_ip_ttl            (roce_reth_ip_ttl),
        .m_ip_protocol       (roce_reth_ip_protocol),
        .m_ip_header_checksum(roce_reth_ip_header_checksum),
        .m_ip_source_ip      (roce_reth_ip_source_ip),
        .m_ip_dest_ip        (roce_reth_ip_dest_ip),
        .m_udp_source_port   (roce_reth_udp_source_port),
        .m_udp_dest_port     (roce_reth_udp_dest_port),
        .m_udp_length        (roce_reth_udp_length),
        .m_udp_checksum      (roce_reth_udp_checksum),

        .m_roce_bth_payload_axis_tdata (roce_reth_payload_axis_tdata),
        .m_roce_bth_payload_axis_tkeep (roce_reth_payload_axis_tkeep),
        .m_roce_bth_payload_axis_tvalid(roce_reth_payload_axis_tvalid),
        .m_roce_bth_payload_axis_tready(roce_reth_payload_axis_tready),
        .m_roce_bth_payload_axis_tlast (roce_reth_payload_axis_tlast),
        .m_roce_bth_payload_axis_tuser (roce_reth_payload_axis_tuser)
    );


    RoCE_bth_udp_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_ENABLE(KEEP_ENABLE),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MIG_REQ(MIG_REQ),
        .FECN(FECN)
    ) RoCE_bth_udp_tx_instance (
        .clk(clk),
        .rst(rst),
        .s_roce_bth_valid    (roce_reth_bth_valid),
        .s_roce_bth_ready    (roce_reth_bth_ready),
        .s_roce_bth_op_code  (roce_reth_bth_op_code),
        .s_roce_bth_p_key    (roce_reth_bth_p_key),
        .s_roce_bth_psn      (roce_reth_bth_psn),
        .s_roce_bth_dest_qp  (roce_reth_bth_dest_qp),
        .s_roce_bth_ack_req  (roce_reth_bth_ack_req),
        .s_eth_dest_mac      (roce_reth_eth_dest_mac),
        .s_eth_src_mac       (roce_reth_eth_src_mac),
        .s_eth_type          (roce_reth_eth_type),
        .s_ip_version        (roce_reth_ip_version),
        .s_ip_ihl            (roce_reth_ip_ihl),
        .s_ip_dscp           (roce_reth_ip_dscp),
        .s_ip_ecn            (roce_reth_ip_ecn),
        .s_ip_identification (roce_reth_ip_identification),
        .s_ip_flags          (roce_reth_ip_flags),
        .s_ip_fragment_offset(roce_reth_ip_fragment_offset),
        .s_ip_ttl            (roce_reth_ip_ttl),
        .s_ip_protocol       (roce_reth_ip_protocol),
        .s_ip_header_checksum(roce_reth_ip_header_checksum),
        .s_ip_source_ip      (roce_reth_ip_source_ip),
        .s_ip_dest_ip        (roce_reth_ip_dest_ip),
        .s_udp_source_port   (roce_reth_udp_source_port),
        .s_udp_dest_port     (roce_reth_udp_dest_port),
        .s_udp_length        (roce_reth_udp_length),
        .s_udp_checksum      (roce_reth_udp_checksum),

        .s_roce_payload_axis_tdata (roce_reth_payload_axis_tdata),
        .s_roce_payload_axis_tkeep (roce_reth_payload_axis_tkeep),
        .s_roce_payload_axis_tvalid(roce_reth_payload_axis_tvalid),
        .s_roce_payload_axis_tready(roce_reth_payload_axis_tready),
        .s_roce_payload_axis_tlast (roce_reth_payload_axis_tlast),
        .s_roce_payload_axis_tuser (roce_reth_payload_axis_tuser),

        .m_udp_hdr_valid     (m_udp_hdr_valid),
        .m_udp_hdr_ready     (m_udp_hdr_ready),
        .m_eth_dest_mac      (m_eth_dest_mac),
        .m_eth_src_mac       (m_eth_src_mac),
        .m_eth_type          (m_eth_type),
        .m_ip_version        (m_ip_version),
        .m_ip_ihl            (m_ip_ihl),
        .m_ip_dscp           (m_ip_dscp),
        .m_ip_ecn            (m_ip_ecn),
        .m_ip_length         (m_ip_length),
        .m_ip_identification (m_ip_identification),
        .m_ip_flags          (m_ip_flags),
        .m_ip_fragment_offset(m_ip_fragment_offset),
        .m_ip_ttl            (m_ip_ttl),
        .m_ip_protocol       (m_ip_protocol),
        .m_ip_header_checksum(m_ip_header_checksum),
        .m_ip_source_ip      (m_ip_source_ip),
        .m_ip_dest_ip        (m_ip_dest_ip),
        .m_udp_source_port   (m_udp_source_port),
        .m_udp_dest_port     (m_udp_dest_port),
        .m_udp_length        (m_udp_length),
        .m_udp_checksum      (m_udp_checksum),

        .m_udp_payload_axis_tdata (m_udp_payload_axis_tdata),
        .m_udp_payload_axis_tkeep (m_udp_payload_axis_tkeep),
        .m_udp_payload_axis_tvalid(m_udp_payload_axis_tvalid),
        .m_udp_payload_axis_tready(m_udp_payload_axis_tready),
        .m_udp_payload_axis_tlast (m_udp_payload_axis_tlast),
        .m_udp_payload_axis_tuser (m_udp_payload_axis_tuser),
        .RoCE_udp_port(RoCE_udp_port)
    );

endmodule

`resetall
