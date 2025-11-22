// SPDX-License-Identifier: GPL-2.0-only OR MIT
/* Code to dump registers and ALE table for the CPSW instances on K3 SoCs that are configured using
 * the am65-cpsw-nuss device-driver in Linux.
 *
 * Copyright (C) 2025 Texas Instruments
 * Author: Chintan Vankar <c-vankar@ti.com>
 */

#include <stdio.h>
#include <string.h>

#include "internal.h"

#define ALE_ENTRY_BITS          74
#define ALE_ENTRY_WORDS         DIV_ROUND_UP(ALE_ENTRY_BITS, 32)

#define ALE_ENTRY_FREE		0x0
#define ALE_ENTRY_ADDR		0x1
#define ALE_ENTRY_VLAN		0x2
#define ALE_ENTRY_VLAN_ADDR	0x3

#define BIT(nr)			(1 << (nr))
#define BITMASK(bits)		(BIT(bits) - 1)

/* ALE word specifiers */
#define NUM_ALE_WORDS	2
#define ALE_WORD_LEN	32

/* MAC address specifiers */
#define MAC_START_BIT	40
#define MAC_OCTET_LEN	8
#define NUM_MAC_OCTET	6

/* RTL version specifiers */
#define RTL_VERSION_MASK	0xF800
#define CPSW2G_RTL_VERSION	0x3800
#define CPSW3G_RTL_VERSION	0x0

/* OUI address uses format xx:xx:xx, use OUI shift as 16 bits and MASK as 0xFF to parse the same*/
#define OUI_ADDR_SHIFT		16
#define OUI_ADDR_MASK		0xFF

/* VLAN entry specifiers */
#define VLAN_INNER_ENTRY	0x0
#define VLAN_OUTER_ENTRY	0x2
#define VLAN_ETHERTYPE_ENTRY	0x4
#define VLAN_IPV4_ENTRY		0x6
#define VLAN_IPV6_ENTRY_MASK	0x1

/* VLAN Inner/Outer table entry MASKs and SHIFTs*/
#define NOLEARN_FLAG_SHIFT		2
#define NOLEARN_FLAG_MASK		0x1FF
#define INGRESS_CHECK_SHIFT		1
#define INGRESS_CHECK_MASK		0x1
#define VLAN_ID_SHIFT			16
#define VLAN_ID_MASK			0xFFF
#define NOFRAG_FLAG_SHIFT_2G		12
#define NOFRAG_FLAG_MASK_2G		0x1
#define NOFRAG_FLAG_SHIFT		15
#define NOFRAG_FLAG_MASK		0x1
#define REG_MASK_SHIFT			4
#define REG_MASK_MASK			0x1FF
#define PKT_EGRESS_W1_MASK		0x1
#define PKT_EGRESS_W1_OFFSET		512
#define PKT_EGRESS_SHIFT		24
#define PKT_EGRESS_MASK_2G		0x3
#define PKT_EGRESS_MASK			0x1FF
#define UNREG_MASK_SHIFT_2G		20
#define UNREG_MASK_MASK_2G		0x7
#define UNREG_MASK_SHIFT		12
#define UNREG_MASK_MASK			0x1FF
#define NXT_HDR_CTRL_SHIFT_2G		19
#define NXT_HDR_CTRL_MASK_2G		0x1
#define NXT_HDR_CTRL_SHIFT		23
#define NXT_HDR_CTRL_MASK		0x1
#define VLAN_MEMBER_LIST_MASK_2G	0x3
#define VLAN_MEMBER_LIST_MASK		0x1FF

/* VLAN IPv4 entry MASKs and SHIFTs*/
#define IPV4_ADDR_OCT1_SHIFT	24
#define IPV4_ADDR_OCT2_SHIFT	16
#define IPV4_ADDR_OCT3_SHIFT	8
#define IPV4_ADDR_MASK		0xFF

/* VLAN IPv6 entry MASKs and SHIFTs*/
#define IPV6_HIGH_ENTRY_FLAG	0x40
#define IPV6_IGNMCBITS_MASK	0xFF
#define IPV6_HADDR_W1_SHIFT	12
#define IPV6_HADDR_W1_MASK_1	0xFFFF
#define IPV6_HADDR_W1_MASK_2	0xFFF
#define IPV6_HADDR_W0_SHIFT_1	28
#define IPV6_HADDR_W0_MASK_1	0xF
#define IPV6_HADDR_W0_SHIFT_2	12
#define IPV6_HADDR_W0_MASK_2	0xFFFF
#define IPV6_LADDR_W2_SHIFT	4
#define IPV6_LADDR_W2_MAKS	0xF
#define IPV6_LADDR_W1_SHIFT	16
#define IPV6_LADDR_W1_MASK_1	0xFFF
#define IPV6_LADDR_W1_MASK	0xFFFF
#define IPV6_LADDR_W0_SHIFT	16
#define IPV6_LADDR_W0_MASK	0xFFFF

/**
 * Since there are different instances of CPSW (namely cpsw2g, cpsw3g, cpsw5g and cpsw9g)
 * some register offsets differ to get some parameters for ALE table, parse rtl_version
 * from ALE_MOD_VER register to determine which instance is being used.
 */
u32 rtl_version;

static inline int cpsw_ale_get_field(u32 *ale_entry, u32 start, u32 bits)
{
	int idx;

	idx    = start / ALE_WORD_LEN;
	start -= idx * ALE_WORD_LEN;

	/**
	 * ALE words are stored in order word2, word1 and word0, flip the word to parse in numeric
	 * order
	 */
	idx    = NUM_ALE_WORDS - idx; /* flip */
	return (ale_entry[idx] >> start) & BITMASK(bits);
}

#define DEFINE_ALE_FIELD(name, start, bits)				\
static inline int cpsw_ale_get_##name(u32 *ale_entry)			\
{									\
	return cpsw_ale_get_field(ale_entry, start, bits);		\
}

DEFINE_ALE_FIELD(entry_type,		60,	2)
DEFINE_ALE_FIELD(vlan_id,		48,	12)
DEFINE_ALE_FIELD(mcast_state,		62,	2)
DEFINE_ALE_FIELD(port_mask,		66,	9)
DEFINE_ALE_FIELD(super,			65,	1)
DEFINE_ALE_FIELD(agable,		62,	1)
DEFINE_ALE_FIELD(touched,		63,	1)
DEFINE_ALE_FIELD(ucast_type,		62,	2)
DEFINE_ALE_FIELD(port_num,		66,	4)
DEFINE_ALE_FIELD(port_num_2g,		66,	1)
DEFINE_ALE_FIELD(port_num_3g,		66,	2)
DEFINE_ALE_FIELD(blocked,		65,	1)
DEFINE_ALE_FIELD(secure,		64,	1)
DEFINE_ALE_FIELD(oui_entry,		62,	2)
DEFINE_ALE_FIELD(oui_addr,		4,	24)
DEFINE_ALE_FIELD(mcast,			40,	1)
DEFINE_ALE_FIELD(vlan_entry_type,	62,	3)
DEFINE_ALE_FIELD(ethertype,		0,	16)
DEFINE_ALE_FIELD(ipv4_addr,		0,	32)
DEFINE_ALE_FIELD(ingress_bits,		65,	5)
DEFINE_ALE_FIELD(ipv6_addr_low,		0,	60)
DEFINE_ALE_FIELD(ipv6_addr_mid,		63,	8)
DEFINE_ALE_FIELD(ipv6_addr_high,	0,	60)
DEFINE_ALE_FIELD(entry_word0,		0,	32)
DEFINE_ALE_FIELD(entry_word1,		32,	32)
DEFINE_ALE_FIELD(entry_word2,		64,	12)

static inline void cpsw_ale_get_addr(u32 *ale_entry, u8 *addr)
{
	int i;

	for (i = 0; i < NUM_MAC_OCTET; i++)
		addr[i] = cpsw_ale_get_field(ale_entry, MAC_START_BIT - MAC_OCTET_LEN * i,
					     MAC_OCTET_LEN);
}

struct k3_cpsw_regdump_hdr {
	u32 module_id;
	u32 len;
};

enum {
	K3_CPSW_REGDUMP_MOD_NUSS = 1,
	K3_CPSW_REGDUMP_MOD_RGMII_STATUS = 2,
	K3_CPSW_REGDUMP_MOD_MDIO = 3,
	K3_CPSW_REGDUMP_MOD_CPSW = 4,
	K3_CPSW_REGDUMP_MOD_CPSW_P0 = 5,
	K3_CPSW_REGDUMP_MOD_CPSW_PN = 6,
	K3_CPSW_REGDUMP_MOD_CPSW_CPTS = 7,
	K3_CPSW_REGDUMP_MOD_CPSW_ALE = 8,
	K3_CPSW_REGDUMP_MOD_CPSW_ALE_TBL = 9,
	K3_CPSW_REGDUMP_MOD_LAST,
};

static const char *mod_names[K3_CPSW_REGDUMP_MOD_LAST] = {
	[K3_CPSW_REGDUMP_MOD_NUSS] = "cpsw-nuss",
	[K3_CPSW_REGDUMP_MOD_RGMII_STATUS] = "cpsw-nuss-rgmii-status",
	[K3_CPSW_REGDUMP_MOD_MDIO] = "cpsw-nuss-mdio",
	[K3_CPSW_REGDUMP_MOD_CPSW] = "cpsw-nu",
	[K3_CPSW_REGDUMP_MOD_CPSW_P0] = "cpsw-nu-p0",
	[K3_CPSW_REGDUMP_MOD_CPSW_PN] = "cpsw-nu-pn",
	[K3_CPSW_REGDUMP_MOD_CPSW_CPTS] = "cpsw-nu-cpts",
	[K3_CPSW_REGDUMP_MOD_CPSW_ALE] = "cpsw-nu-ale",
	[K3_CPSW_REGDUMP_MOD_CPSW_ALE_TBL] = "cpsw-nu-ale-tbl",
};

static void cpsw_ale_dump_oui_entry(int index, u32 *ale_entry)
{
	u32 oui_addr;

	oui_addr = cpsw_ale_get_oui_addr(ale_entry);

	fprintf(stdout, "%d: Type: OUI Unicast\n, \tOUI = %02x:%02x:%02x\n",
		index, (oui_addr >> OUI_ADDR_SHIFT) & OUI_ADDR_MASK,
		(oui_addr >> OUI_ADDR_SHIFT) & OUI_ADDR_MASK, oui_addr & OUI_ADDR_MASK);
}

static void cpsw_ale_dump_addr(int index, u32 *ale_entry)
{
	u8 addr[NUM_MAC_OCTET];

	cpsw_ale_get_addr(ale_entry, addr);

	if (cpsw_ale_get_mcast(ale_entry)) {
		static const char * const str_mcast_state[] = {"Forwarding",
							       "Blocking/Forwarding/Learning",
							       "Learning/Forwarding",
							       "Forwarding"};
		u16 port_mask = cpsw_ale_get_port_mask(ale_entry);
		u8 state = cpsw_ale_get_mcast_state(ale_entry);
		u8 super = cpsw_ale_get_super(ale_entry);

		fprintf(stdout, "%d: Type: Multicast\n \tAddress = %02x:%02x:%02x:%02x:%02x:%02x, Multicast_State = %s, %sSuper, port_mask = 0x%x\n",
			index, addr[0], addr[1], addr[2], addr[3], addr[4], addr[5],
			str_mcast_state[state], super ? "" : "No ", port_mask);
	} else {
		static const char * const s_ucast_type[] = {"Persistent", "Untouched", "OUI",
							    "Touched"};
		u8 ucast_type = cpsw_ale_get_ucast_type(ale_entry);
		u8 port_num = cpsw_ale_get_port_num(ale_entry);
		u8 blocked = cpsw_ale_get_blocked(ale_entry);
		u8 touched = cpsw_ale_get_touched(ale_entry);
		u8 secure = cpsw_ale_get_secure(ale_entry);
		u8 agable = cpsw_ale_get_agable(ale_entry);

		fprintf(stdout, "%d: Type: Unicast\n \tUpdated Address = %02x:%02x:%02x:%02x:%02x:%02x, Unicast Type = %s, Port_num = 0x%x, Secure: %d, Blocked: %d, Touch = %d, Agable = %d\n",
			index, addr[0], addr[1], addr[2], addr[3], addr[4], addr[5],
			s_ucast_type[ucast_type], port_num, secure, blocked, touched, agable);
	}
}

static void cpsw_ale_dump_inner_vlan_entry(int index, u32 *ale_entry)
{
	u32 vlan_entry_word0 = cpsw_ale_get_entry_word0(ale_entry);
	u32 vlan_entry_word1 = cpsw_ale_get_entry_word1(ale_entry);
	u16 vlan_entry_word2 = cpsw_ale_get_entry_word2(ale_entry);

	fprintf(stdout, "%d: Type: Inner VLAN\n \tNolearn Mask = 0x%x, Ingress Check = %d\n",
		index, (vlan_entry_word2 >> NOLEARN_FLAG_SHIFT) & NOLEARN_FLAG_MASK,
		(vlan_entry_word2 >> INGRESS_CHECK_SHIFT) & INGRESS_CHECK_MASK);

	if (rtl_version == CPSW2G_RTL_VERSION) {
		fprintf(stdout, "\tVLAN ID = %d, No Frag = %d, Registered Mask = 0x%x\n",
			(vlan_entry_word1 >> VLAN_ID_SHIFT) & VLAN_ID_MASK,
			(vlan_entry_word1 >> NOFRAG_FLAG_SHIFT_2G) & NOFRAG_FLAG_MASK_2G,
			(vlan_entry_word1 >> REG_MASK_SHIFT) & REG_MASK_MASK);

		fprintf(stdout, "\tForce Untagged Packet Egress = 0x%x, Unregistered Mask = 0x%x, Limit Next Header Control = %d, Members = 0x%x\n",
			(vlan_entry_word0 >> PKT_EGRESS_SHIFT) & PKT_EGRESS_MASK_2G,
			(vlan_entry_word0 >> UNREG_MASK_SHIFT_2G) & UNREG_MASK_MASK_2G,
			(vlan_entry_word0 >> NXT_HDR_CTRL_SHIFT_2G) & NXT_HDR_CTRL_MASK_2G,
			(vlan_entry_word0 & VLAN_MEMBER_LIST_MASK_2G));
	} else {
		fprintf(stdout, "\tVLAN ID = %d, Registered Mask = 0x%x, No Frag = %d\n",
			(vlan_entry_word1 >> VLAN_ID_SHIFT) & VLAN_ID_MASK,
			(vlan_entry_word1 >> REG_MASK_SHIFT) & REG_MASK_MASK,
			(vlan_entry_word1 >> NOFRAG_FLAG_SHIFT) & NOFRAG_FLAG_MASK);

		fprintf(stdout, "\tForce Untagged Packet Egress = 0x%x, Limit Next Header Control = %d, Unregistered Mask = 0x%x, Members = 0x%x\n",
			(vlan_entry_word1 & PKT_EGRESS_W1_MASK) * PKT_EGRESS_W1_OFFSET +
			((vlan_entry_word0 >> PKT_EGRESS_SHIFT) & PKT_EGRESS_MASK),
			(vlan_entry_word0 >> NXT_HDR_CTRL_SHIFT) & NXT_HDR_CTRL_MASK,
			(vlan_entry_word0 >> UNREG_MASK_SHIFT) & UNREG_MASK_MASK,
			(vlan_entry_word0 & VLAN_MEMBER_LIST_MASK));
	}
}

static void cpsw_ale_dump_outer_vlan_entry(int index, u32 *ale_entry)
{
	u32 vlan_entry_word0 = cpsw_ale_get_entry_word0(ale_entry);
	u32 vlan_entry_word1 = cpsw_ale_get_entry_word1(ale_entry);
	u16 vlan_entry_word2 = cpsw_ale_get_entry_word2(ale_entry);

	fprintf(stdout, "%d: Type: Outer VLAN\n \tNolearn Mask = 0x%x, Ingress Check = %d\n",
		index, (vlan_entry_word2 >> NOLEARN_FLAG_SHIFT) & NOLEARN_FLAG_MASK,
		(vlan_entry_word2 >> INGRESS_CHECK_SHIFT) & INGRESS_CHECK_MASK);

	if (rtl_version == CPSW2G_RTL_VERSION) {
		fprintf(stdout, "\tVLAN ID = %d, No Frag = %d, Registered Mask = 0x%x\n",
			(vlan_entry_word1 >> VLAN_ID_SHIFT) & VLAN_ID_MASK,
			(vlan_entry_word1 >> NOFRAG_FLAG_SHIFT_2G) & NOFRAG_FLAG_MASK_2G,
			(vlan_entry_word1 >> REG_MASK_SHIFT) & REG_MASK_MASK);

		fprintf(stdout, "\tForce Untagged Packet Egress = 0x%x, Unregistered Mask = 0x%x, Limit Next Header Control = %d, Members = 0x%x\n",
			(vlan_entry_word0 >> PKT_EGRESS_SHIFT) & PKT_EGRESS_MASK_2G,
			(vlan_entry_word0 >> UNREG_MASK_SHIFT_2G) & UNREG_MASK_MASK_2G,
			(vlan_entry_word0 >> NXT_HDR_CTRL_SHIFT_2G) & NXT_HDR_CTRL_MASK_2G,
			(vlan_entry_word0 & VLAN_MEMBER_LIST_MASK_2G));
	} else {
		fprintf(stdout, "\tVLAN ID = %d, No Frag = %d, Registered Mask = 0x%x\n",
			(vlan_entry_word1 >> VLAN_ID_SHIFT) & VLAN_ID_MASK,
			(vlan_entry_word1 >> NOFRAG_FLAG_SHIFT) & NOFRAG_FLAG_MASK,
			(vlan_entry_word1 >> REG_MASK_SHIFT) & REG_MASK_MASK);

		fprintf(stdout, "\tForce Untagged Packet Egress = 0x%x, Limit Next Header Control = %d, Unregistered Mask = 0x%x Members = 0x%x\n",
			(vlan_entry_word1 & PKT_EGRESS_W1_MASK) * PKT_EGRESS_W1_OFFSET +
			((vlan_entry_word0 >> PKT_EGRESS_SHIFT) & PKT_EGRESS_MASK),
			(vlan_entry_word0 >> NXT_HDR_CTRL_SHIFT) & NXT_HDR_CTRL_MASK,
			(vlan_entry_word0 >> UNREG_MASK_SHIFT) & UNREG_MASK_MASK,
			(vlan_entry_word0 & VLAN_MEMBER_LIST_MASK));
	}
}

static void cpsw_ale_dump_ethertype_entry(int index, u32 *ale_entry)
{
	u16 ethertype = cpsw_ale_get_ethertype(ale_entry);

	fprintf(stdout, "%d: Type: VLAN Ethertype\n \tEthertype = 0x%x\n", index, ethertype);
}

static void cpsw_ale_dump_ipv4_entry(int index, u32 *ale_entry)
{
	u8 ingress_bits = cpsw_ale_get_ingress_bits(ale_entry);
	u32 ipv4_addr = cpsw_ale_get_ipv4_addr(ale_entry);

	fprintf(stdout, "%d: Type: VLAN IPv4\n \tIngress Bits: 0x%x IPv4 Address = %u.%u.%u.%u\n",
		index, ingress_bits, ipv4_addr >> IPV4_ADDR_OCT1_SHIFT & IPV4_ADDR_MASK,
		ipv4_addr >> IPV4_ADDR_OCT2_SHIFT & IPV4_ADDR_MASK,
		ipv4_addr >> IPV4_ADDR_OCT3_SHIFT & IPV4_ADDR_MASK, ipv4_addr & IPV4_ADDR_MASK);
}

static void cpsw_ale_dump_ipv6_entry(int index, u32 *ale_entry)
{
	u32 vlan_entry_word0 = cpsw_ale_get_entry_word0(ale_entry);
	u32 vlan_entry_word1 = cpsw_ale_get_entry_word1(ale_entry);
	u16 vlan_entry_word2 = cpsw_ale_get_entry_word2(ale_entry);

	if (index & IPV6_HIGH_ENTRY_FLAG) {
		fprintf(stdout, "%d: Type: VLAN IPv6 Higher Entry (Lower Bit entry at %04u)\n \tIgnored Multicast bits: 0x%x, IPv6 Address (Bits [127:68]) = %04x:%03x%01x:%04x:%03x\n",
			index, (index & (~IPV6_HIGH_ENTRY_FLAG)),
			vlan_entry_word2 & IPV6_IGNMCBITS_MASK,
			(vlan_entry_word1 >> IPV6_HADDR_W1_SHIFT) & IPV6_HADDR_W1_MASK_1,
			vlan_entry_word1 & IPV6_HADDR_W1_MASK_2,
			(vlan_entry_word0 >> IPV6_HADDR_W0_SHIFT_1) & IPV6_HADDR_W0_MASK_1,
			(vlan_entry_word0 >> IPV6_HADDR_W0_SHIFT_2) & IPV6_HADDR_W0_MASK_2,
			vlan_entry_word0 & IPV6_HADDR_W0_MASK_2);
	} else {
		fprintf(stdout, "%d: Type: VLAN IPv6 Lower Entry (Higher Bit entry at %04u)\n \tIPv6 Address (Bits [127:68]) = %01x:%01x%03x:%04x:%04x:%04x\n",
			index, (index | IPV6_HIGH_ENTRY_FLAG),
			(vlan_entry_word2 >> IPV6_LADDR_W2_SHIFT) & IPV6_LADDR_W2_MAKS,
			vlan_entry_word2 & IPV6_LADDR_W2_MAKS,
			(vlan_entry_word1 >> IPV6_LADDR_W1_SHIFT) & IPV6_LADDR_W1_MASK_1,
			vlan_entry_word1 & IPV6_LADDR_W1_MASK,
			(vlan_entry_word0 >> IPV6_LADDR_W0_SHIFT) & IPV6_LADDR_W0_MASK,
			vlan_entry_word0 & IPV6_LADDR_W0_MASK);
	}
}

static void cpsw_ale_dump_vlan_addr(int index, u32 *ale_entry)
{
	u8 addr[NUM_MAC_OCTET];
	int vlan = cpsw_ale_get_vlan_id(ale_entry);

	cpsw_ale_get_addr(ale_entry, addr);
	if (cpsw_ale_get_mcast(ale_entry)) {
		static const char * const str_mcast_state[] = {"Forwarding",
							       "Blocking/Forwarding/Learning",
							       "Learning/Forwarding",
							       "Forwarding"};
		u16 port_mask = cpsw_ale_get_port_mask(ale_entry);
		u8 state = cpsw_ale_get_mcast_state(ale_entry);
		u8 super = cpsw_ale_get_super(ale_entry);

		fprintf(stdout, "%d: Type: Multicast\n \tVID = %d, Address = %02x:%02x:%02x:%02x:%02x:%02x, Multicast_state = %s, %s Super, port_mask = 0x%x\n",
			index, vlan, addr[0], addr[1], addr[2], addr[3], addr[4], addr[5],
			str_mcast_state[state], super ? "" : "No ", port_mask);
	} else {
		static const char * const s_ucast_type[] = {"Persistent", "Untouched", "OUI",
							    "Touched"};
		u8 ucast_type = cpsw_ale_get_ucast_type(ale_entry);
		u8 blocked = cpsw_ale_get_blocked(ale_entry);
		u8 touched = cpsw_ale_get_touched(ale_entry);
		u8 secure = cpsw_ale_get_secure(ale_entry);
		u8 agable = cpsw_ale_get_agable(ale_entry);

		int port_num;

		if (rtl_version == CPSW2G_RTL_VERSION)
			port_num = cpsw_ale_get_port_num_2g(ale_entry);
		else if (rtl_version == CPSW3G_RTL_VERSION)
			port_num = cpsw_ale_get_port_num_3g(ale_entry);
		else
			port_num = cpsw_ale_get_port_num(ale_entry);

		fprintf(stdout, "%d: Type: Unicast\n \tVID = %d, Address = %02x:%02x:%02x:%02x:%02x:%02x, Unicast_type = %s, port_num = 0x%x, Secure = %d, Blocked = %d, Touch = %d, Agable = %d\n",
			index, vlan, addr[0], addr[1], addr[2], addr[3], addr[4], addr[5],
			s_ucast_type[ucast_type], port_num, secure, blocked, touched, agable);
	}
}

void cpsw_dump_ale(struct k3_cpsw_regdump_hdr *ale_hdr, u32 *ale_pos)
{
	int i, ale_entries;

	if (!ale_hdr)
		return;

	ale_entries = (ale_hdr->len - sizeof(struct k3_cpsw_regdump_hdr)) /
		      ALE_ENTRY_WORDS / sizeof(u32);

	printf("Number of ALE entries: %d\n", ale_entries);
	ale_pos += 2;
	for (i = 0; i < ale_entries; i++) {
		int type;

		type = cpsw_ale_get_entry_type(ale_pos);

		switch (type) {
		case ALE_ENTRY_FREE:
			break;

		case ALE_ENTRY_ADDR:
			u32 oui_entry = cpsw_ale_get_oui_addr(ale_pos);

			if (oui_entry == 0x2)
				cpsw_ale_dump_oui_entry(i, ale_pos);
			else
				cpsw_ale_dump_addr(i, ale_pos);
			break;

		case ALE_ENTRY_VLAN:
			u32 vlan_entry_type = cpsw_ale_get_vlan_entry_type(ale_pos);

			if (vlan_entry_type == VLAN_INNER_ENTRY)
				cpsw_ale_dump_inner_vlan_entry(i, ale_pos);
			else if (vlan_entry_type == VLAN_OUTER_ENTRY)
				cpsw_ale_dump_outer_vlan_entry(i, ale_pos);
			else if (vlan_entry_type == VLAN_ETHERTYPE_ENTRY)
				cpsw_ale_dump_ethertype_entry(i, ale_pos);
			else if (vlan_entry_type == VLAN_IPV4_ENTRY)
				cpsw_ale_dump_ipv4_entry(i, ale_pos);
			else if (vlan_entry_type & VLAN_IPV6_ENTRY_MASK)
				cpsw_ale_dump_ipv6_entry(i, ale_pos);
			break;

		case ALE_ENTRY_VLAN_ADDR:
			cpsw_ale_dump_vlan_addr(i, ale_pos);
			break;

		default:
			break;
		}

		ale_pos += ALE_ENTRY_WORDS;
	}
}

int am65_cpsw_dump_regs(struct  ethtool_drvinfo *info __maybe_unused,
			struct ethtool_regs *regs)
{
	struct k3_cpsw_regdump_hdr *dump_hdr, *ale_hdr = NULL;
	u32 *reg = (u32 *)regs->data, *ale_pos;
	u32 mod_id;
	int i, regdump_len = info->regdump_len;

	fprintf(stdout, "K3 CPSW dump version: %d, len: %d\n",
		regs->version, info->regdump_len);
	fprintf(stdout, "(Missing registers in memory space can be considered as zero valued)\n");

	/* Line break before register dump */
	fprintf(stdout, "--------------------------------------------------------------------\n");
	i = 0;
	do {
		u32 *tmp, j;
		u32 num_items;

		dump_hdr = (struct k3_cpsw_regdump_hdr *)reg;
		mod_id = dump_hdr->module_id;

		num_items = dump_hdr->len / sizeof(u32);

		if (mod_id == K3_CPSW_REGDUMP_MOD_CPSW_ALE)
			rtl_version = reg[3] & RTL_VERSION_MASK;

		if (mod_id == K3_CPSW_REGDUMP_MOD_CPSW_ALE_TBL) {
			ale_hdr = dump_hdr;
			ale_pos = reg;
			break;
		}

		fprintf(stdout, "%s regdump: number of Registers:(%d)\n",
			mod_names[mod_id], num_items - 2);
		tmp = reg;
		/* Values are stored in pair as reg_offset-reg_val, hence parse the same way*/
		for (j = 2; j < num_items; j += 2) {
			if (tmp[j + 1] != 0x0)
				fprintf(stdout, "%08x:reg(%08X)\n", tmp[j], tmp[j + 1]);
		}

		reg += num_items;
		i += dump_hdr->len;
	} while (i < regdump_len);

	/* Adding a boundary in between Register dump and ALE table */
	fprintf(stdout, "--------------------------\n");

	cpsw_dump_ale(ale_hdr, ale_pos);

	return 0;
};
