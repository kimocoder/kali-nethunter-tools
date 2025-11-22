/* Copyright (c) 2025 Huawei Corporation */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include "internal.h"

#define HBG_REG_NAEM_MAX_LEN 24

struct hbg_reg_info {
	u32 type;
	u32 offset;
	u32 val;
};

struct hbg_offset_name_map {
	u32 offset;
	const char *name;
};

enum hbg_reg_dump_type {
	HBG_DUMP_REG_TYPE_SPEC = 0,
	HBG_DUMP_REG_TYPE_MDIO,
	HBG_DUMP_REG_TYPE_GMAC,
	HBG_DUMP_REG_TYPE_PCU,
	HBG_DUMP_REG_TYPE_MAX,
};

struct hbg_type_info {
	const char *type_name;
	const struct hbg_offset_name_map *reg_map;
	u32 reg_num;
};

static const struct hbg_offset_name_map hbg_spec_maps[] = {
	{0x0000, "valid"},
	{0x0004, "event_req"},
	{0x0008, "mac_id"},
	{0x000c, "phy_addr"},
	{0x0010, "mac_addr_l"},
	{0x0014, "mac_addr_h"},
	{0x0018, "uc_max_num"},
	{0x0024, "mdio_freq"},
	{0x0028, "max_mtu"},
	{0x002c, "min_mtu"},
	{0x0030, "tx_fifo_num"},
	{0x0034, "rx_fifo_num"},
	{0x0038, "vlan_layers"},
};

static const struct hbg_offset_name_map hbg_mdio_maps[] = {
	{0x0000, "command_reg"},
	{0x0004, "addr_reg"},
	{0x0008, "wdata_reg"},
	{0x000c, "rdata_reg"},
	{0x0010, "sta_reg"},
};

static const struct hbg_offset_name_map hbg_gmac_maps[] = {
	{0x0008, "duplex_type"},
	{0x000c, "fd_fc_type"},
	{0x001c, "fc_tx_timer"},
	{0x0020, "fd_fc_addr_low"},
	{0x0024, "fd_fc_addr_high"},
	{0x003c, "max_frm_size"},
	{0x0040, "port_mode"},
	{0x0044, "port_en"},
	{0x0048, "pause_en"},
	{0x0058, "an_neg_state"},
	{0x0060, "transmit_ctrl"},
	{0x0064, "rec_filt_ctrl"},
	{0x01a8, "line_loop_back"},
	{0x01b0, "cf_crc_strip"},
	{0x01b4, "mode_change_en"},
	{0x01dc, "loop_reg"},
	{0x01e0, "recv_control"},
	{0x01e8, "vlan_code"},
	{0x0200, "station_addr_low_0"},
	{0x0204, "station_addr_high_0"},
	{0x0208, "station_addr_low_1"},
	{0x020c, "station_addr_high_1"},
	{0x0210, "station_addr_low_2"},
	{0x0214, "station_addr_high_2"},
	{0x0218, "station_addr_low_3"},
	{0x021c, "station_addr_high_3"},
	{0x0220, "station_addr_low_4"},
	{0x0224, "station_addr_high_4"},
	{0x0228, "station_addr_low_5"},
	{0x022c, "station_addr_high_5"},
};

static const struct hbg_offset_name_map hbg_pcu_maps[] = {
	{0x0420, "cf_tx_fifo_thrsld"},
	{0x0424, "cf_rx_fifo_thrsld"},
	{0x0428, "cf_cfg_fifo_thrsld"},
	{0x042c, "cf_intrpt_msk"},
	{0x0434, "cf_intrpt_stat"},
	{0x0438, "cf_intrpt_clr"},
	{0x043c, "tx_bus_err_addr"},
	{0x0440, "rx_bus_err_addr"},
	{0x0444, "max_frame_len"},
	{0x0450, "debug_st_mch"},
	{0x0454, "fifo_curr_status"},
	{0x0458, "fifo_his_status"},
	{0x045c, "cf_cff_data_num"},
	{0x0470, "cf_tx_pause"},
	{0x04a0, "rx_cff_addr"},
	{0x04e4, "rx_buf_size"},
	{0x04e8, "bus_ctrl"},
	{0x04f0, "rx_ctrl"},
	{0x04f4, "rx_pkt_mode"},
	{0x05e4, "dbg_st0"},
	{0x05e8, "dbg_st1"},
	{0x05ec, "dbg_st2"},
	{0x0688, "bus_rst_en"},
	{0x0694, "cf_ind_txint_msk"},
	{0x0698, "cf_ind_txint_stat"},
	{0x069c, "cf_ind_txint_clr"},
	{0x06a0, "cf_ind_rxint_msk"},
	{0x06a4, "cf_ind_rxint_stat"},
	{0x06a8, "cf_ind_rxint_clr"},
};

static const struct hbg_type_info hbg_type_infos[] = {
	[HBG_DUMP_REG_TYPE_SPEC] = {"SPEC", hbg_spec_maps, ARRAY_SIZE(hbg_spec_maps)},
	[HBG_DUMP_REG_TYPE_MDIO] = {"MDIO", hbg_mdio_maps, ARRAY_SIZE(hbg_mdio_maps)},
	[HBG_DUMP_REG_TYPE_GMAC] = {"GMAC", hbg_gmac_maps, ARRAY_SIZE(hbg_gmac_maps)},
	[HBG_DUMP_REG_TYPE_PCU] = {"PCU", hbg_pcu_maps, ARRAY_SIZE(hbg_pcu_maps)},
	[HBG_DUMP_REG_TYPE_MAX] = {"UNKNOWN", NULL, 0},
};

static void dump_type_reg(const struct hbg_type_info *type_info,
			  const struct hbg_reg_info *reg_info)
{
	const char *reg_name = "UNKNOWN";
	u32 i = 0;

	for (i = 0; i < type_info->reg_num; i++)
		if (type_info->reg_map[i].offset == reg_info->offset) {
			reg_name = type_info->reg_map[i].name;
			break;
		}

	fprintf(stdout, "[%s]%-*s[0x%04x]: 0x%08x\n",
		type_info->type_name, HBG_REG_NAEM_MAX_LEN, reg_name,
		reg_info->offset, reg_info->val);
}

int hibmcge_dump_regs(struct ethtool_drvinfo *info __maybe_unused,
		      struct ethtool_regs *regs)
{
	struct hbg_reg_info *reg_info;
	u32 offset = 0;

	if (regs->len % sizeof(*reg_info) != 0)
		return -EINVAL;

	while (offset < regs->len) {
		reg_info = (struct hbg_reg_info *)(regs->data + offset);

		if (reg_info->type >= HBG_DUMP_REG_TYPE_MAX)
			dump_type_reg(&hbg_type_infos[HBG_DUMP_REG_TYPE_MAX],
				      reg_info);
		else
			dump_type_reg(&hbg_type_infos[reg_info->type], reg_info);

		offset += sizeof(*reg_info);
	}

	return 0;
}
