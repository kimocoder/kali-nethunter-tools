// SPDX-License-Identifier: GPL-2.0
/*
 * tsconfig.c - netlink implementation of hardware timestamping
 *		configuration
 *
 * Implementation of "ethtool --get-hwtimestamp-cfg <dev>" and
 * "ethtool --set-hwtimestamp-cfg <dev> ..."
 */

#include <errno.h>
#include <inttypes.h>
#include <string.h>
#include <stdio.h>

#include "../internal.h"
#include "../common.h"
#include "netlink.h"
#include "bitset.h"
#include "parser.h"
#include "strset.h"
#include "ts.h"

/* TSCONFIG_GET */

int tsconfig_reply_cb(const struct nlmsghdr *nlhdr, void *data)
{
	const struct nlattr *tb[ETHTOOL_A_TSCONFIG_MAX + 1] = {};
	DECLARE_ATTR_TB_INFO(tb);
	struct nl_context *nlctx = data;
	bool silent;
	int err_ret;
	int ret;

	silent = nlctx->is_dump;
	err_ret = silent ? MNL_CB_OK : MNL_CB_ERROR;
	ret = mnl_attr_parse(nlhdr, GENL_HDRLEN, attr_cb, &tb_info);
	if (ret < 0)
		return err_ret;
	nlctx->devname = get_dev_name(tb[ETHTOOL_A_TSCONFIG_HEADER]);
	if (!dev_ok(nlctx))
		return err_ret;

	if (silent)
		print_nl();
	printf("Time stamping configuration for %s:\n", nlctx->devname);

	if (!tb[ETHTOOL_A_TSCONFIG_HWTSTAMP_PROVIDER])
		return MNL_CB_OK;

	ret = tsinfo_show_hwprov(tb[ETHTOOL_A_TSCONFIG_HWTSTAMP_PROVIDER]);
	if (ret < 0)
		return err_ret;

	ret = tsinfo_dump_list(nlctx, tb[ETHTOOL_A_TSCONFIG_TX_TYPES],
			       "Hardware Transmit Timestamp Mode", " none",
			       ETH_SS_TS_TX_TYPES);
	if (ret < 0)
		return err_ret;

	ret = tsinfo_dump_list(nlctx, tb[ETHTOOL_A_TSCONFIG_RX_FILTERS],
			       "Hardware Receive Filter Mode", " none",
			       ETH_SS_TS_RX_FILTERS);
	if (ret < 0)
		return err_ret;

	ret = tsinfo_dump_list(nlctx, tb[ETHTOOL_A_TSCONFIG_HWTSTAMP_FLAGS],
			       "Hardware Flags", " none",
			       ETH_SS_TS_FLAGS);
	if (ret < 0)
		return err_ret;

	return MNL_CB_OK;
}

int nl_gtsconfig(struct cmd_context *ctx)
{
	struct nl_context *nlctx = ctx->nlctx;
	struct nl_socket *nlsk = nlctx->ethnl_socket;
	int ret;

	if (netlink_cmd_check(ctx, ETHTOOL_MSG_TSINFO_GET, true))
		return -EOPNOTSUPP;
	if (ctx->argc > 0) {
		fprintf(stderr, "ethtool: unexpected parameter '%s'\n",
			*ctx->argp);
		return 1;
	}

	ret = nlsock_prep_get_request(nlsk, ETHTOOL_MSG_TSCONFIG_GET,
				      ETHTOOL_A_TSCONFIG_HEADER, 0);
	if (ret < 0)
		return ret;
	return nlsock_send_get_request(nlsk, tsconfig_reply_cb);
}

/* TSCONFIG_SET */

int tsconfig_txrx_parser(struct nl_context *nlctx, uint16_t type,
			 const void *data __maybe_unused,
			 struct nl_msg_buff *msgbuff,
			 void *dest __maybe_unused)
{
	struct nlattr *bits_attr, *bit_attr;
	const struct stringset *values;
	const char *arg = *nlctx->argp;
	unsigned int count, i;

	nlctx->argp++;
	nlctx->argc--;
	if (netlink_init_ethnl2_socket(nlctx) < 0)
		return -EIO;

	switch (type) {
	case ETHTOOL_A_TSCONFIG_TX_TYPES:
		values = global_stringset(ETH_SS_TS_TX_TYPES, nlctx->ethnl2_socket);
		break;
	case ETHTOOL_A_TSCONFIG_RX_FILTERS:
		values = global_stringset(ETH_SS_TS_RX_FILTERS, nlctx->ethnl2_socket);
		break;
	default:
		return -EINVAL;
	}

	count = get_count(values);
	for (i = 0; i < count; i++) {
		const char *name = get_string(values, i);

		if (!strcmp(name, arg))
			break;
	}

	if (i == count)
		return -EINVAL;

	if (ethnla_put_flag(msgbuff, ETHTOOL_A_BITSET_NOMASK, true))
		return -EMSGSIZE;

	bits_attr = ethnla_nest_start(msgbuff, ETHTOOL_A_BITSET_BITS);
	if (!bits_attr)
		return -EMSGSIZE;

	bit_attr = ethnla_nest_start(msgbuff, ETHTOOL_A_BITSET_BITS_BIT);
	if (!bit_attr) {
		ethnla_nest_cancel(msgbuff, bits_attr);
		return -EMSGSIZE;
	}
	if (ethnla_put_u32(msgbuff, ETHTOOL_A_BITSET_BIT_INDEX, i) ||
	    ethnla_put_flag(msgbuff, ETHTOOL_A_BITSET_BIT_VALUE, true)) {
		ethnla_nest_cancel(msgbuff, bits_attr);
		ethnla_nest_cancel(msgbuff, bit_attr);
		return -EMSGSIZE;
	}
	mnl_attr_nest_end(msgbuff->nlhdr, bit_attr);
	mnl_attr_nest_end(msgbuff->nlhdr, bits_attr);
	return 0;
}

static const struct param_parser stsconfig_params[] = {
	{
		.arg		= "index",
		.type		= ETHTOOL_A_TS_HWTSTAMP_PROVIDER_INDEX,
		.group		= ETHTOOL_A_TSCONFIG_HWTSTAMP_PROVIDER,
		.handler	= nl_parse_direct_u32,
		.min_argc	= 1,
	},
	{
		.arg		= "qualifier",
		.type		= ETHTOOL_A_TS_HWTSTAMP_PROVIDER_QUALIFIER,
		.group		= ETHTOOL_A_TSCONFIG_HWTSTAMP_PROVIDER,
		.handler	= tsinfo_qualifier_parser,
		.min_argc	= 1,
	},
	{
		.arg		= "tx",
		.type		= ETHTOOL_A_TSCONFIG_TX_TYPES,
		.handler	= tsconfig_txrx_parser,
		.group		= ETHTOOL_A_TSCONFIG_TX_TYPES,
		.min_argc	= 1,
	},
	{
		.arg		= "rx-filter",
		.type		= ETHTOOL_A_TSCONFIG_RX_FILTERS,
		.handler	= tsconfig_txrx_parser,
		.group		= ETHTOOL_A_TSCONFIG_RX_FILTERS,
		.min_argc	= 1,
	},
	{}
};

int nl_stsconfig(struct cmd_context *ctx)
{
	struct nl_context *nlctx = ctx->nlctx;
	struct nl_msg_buff *msgbuff;
	struct nl_socket *nlsk;
	int ret;

	if (netlink_cmd_check(ctx, ETHTOOL_MSG_TSCONFIG_SET, false))
		return -EOPNOTSUPP;

	nlctx->cmd = "--set-hwtstamp-cfg";
	nlctx->argp = ctx->argp;
	nlctx->argc = ctx->argc;
	nlctx->devname = ctx->devname;
	nlsk = nlctx->ethnl_socket;
	msgbuff = &nlsk->msgbuff;

	ret = msg_init(nlctx, msgbuff, ETHTOOL_MSG_TSCONFIG_SET,
		       NLM_F_REQUEST | NLM_F_ACK);
	if (ret < 0)
		return ret;
	if (ethnla_fill_header(msgbuff, ETHTOOL_A_TSCONFIG_HEADER,
			       ctx->devname, ETHTOOL_FLAG_COMPACT_BITSETS))
		return -EMSGSIZE;

	ret = nl_parser(nlctx, stsconfig_params, NULL, PARSER_GROUP_NEST, NULL);
	if (ret < 0)
		return ret;

	ret = nlsock_sendmsg(nlsk, NULL);
	if (ret < 0)
		return ret;

	ret = nlsock_process_reply(nlsk, tsconfig_reply_cb, nlctx);
	if (ret == 0)
		return 0;
	else
		return nlctx->exit_code ?: 1;
}
