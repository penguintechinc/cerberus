// SPDX-License-Identifier: GPL-2.0
// Cerberus XDP Packet Steering Program
// Steers packets to IPS, Arkime, or bypasses based on configurable rules

#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/ipv6.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/icmp.h>
#include <linux/in.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

// XDP Actions mapped to Cerberus actions
#define ACTION_PASS         0  // XDP_PASS - bypass inspection
#define ACTION_DROP         1  // XDP_DROP - block at NIC
#define ACTION_INSPECT_IPS  2  // Send to Suricata IPS
#define ACTION_CAPTURE      3  // Send to Arkime capture
#define ACTION_INSPECT_ALL  4  // Send to both IPS + Arkime

// Match types
#define MATCH_SRC_IP    0
#define MATCH_DST_IP    1
#define MATCH_SRC_NET   2
#define MATCH_DST_NET   3
#define MATCH_SRC_PORT  4
#define MATCH_DST_PORT  5
#define MATCH_PROTOCOL  6
#define MATCH_VLAN      7

// Maximum number of rules
#define MAX_RULES 1024

// Filter rule structure
struct filter_rule {
    __u32 id;
    __u32 priority;
    __u8 match_type;
    __u8 action;
    __u8 enabled;
    __u8 pad;
    __u32 match_ip;      // IP address for IP-based matches
    __u32 match_mask;    // Subnet mask for network matches
    __u16 match_port;    // Port for port-based matches
    __u16 match_proto;   // Protocol number
    __u32 match_vlan;    // VLAN ID
};

// Statistics per rule
struct rule_stats {
    __u64 packets;
    __u64 bytes;
    __u64 last_hit;
};

// Global statistics
struct global_stats {
    __u64 total_packets;
    __u64 total_bytes;
    __u64 passed_packets;
    __u64 dropped_packets;
    __u64 ips_packets;
    __u64 capture_packets;
    __u64 inspect_all_packets;
};

// BPF Maps

// Rules map - indexed by priority (lower = higher priority)
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __type(key, __u32);
    __type(value, struct filter_rule);
    __uint(max_entries, MAX_RULES);
} filter_rules SEC(".maps");

// Rule statistics
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __type(key, __u32);
    __type(value, struct rule_stats);
    __uint(max_entries, MAX_RULES);
} rule_stats SEC(".maps");

// Global statistics
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __type(key, __u32);
    __type(value, struct global_stats);
    __uint(max_entries, 1);
} global_stats SEC(".maps");

// IP whitelist (quick pass for trusted IPs)
struct {
    __uint(type, BPF_MAP_TYPE_LPM_TRIE);
    __type(key, struct lpm_key);
    __type(value, __u8);
    __uint(max_entries, 10000);
    __uint(map_flags, BPF_F_NO_PREALLOC);
} ip_whitelist SEC(".maps");

// IP blacklist (quick drop for blocked IPs)
struct {
    __uint(type, BPF_MAP_TYPE_LPM_TRIE);
    __type(key, struct lpm_key);
    __type(value, __u8);
    __uint(max_entries, 10000);
    __uint(map_flags, BPF_F_NO_PREALLOC);
} ip_blacklist SEC(".maps");

// Redirect map for XDP_REDIRECT to other interfaces
struct {
    __uint(type, BPF_MAP_TYPE_DEVMAP);
    __type(key, __u32);
    __type(value, __u32);
    __uint(max_entries, 64);
} tx_port SEC(".maps");

// LPM key structure for IP prefix matching
struct lpm_key {
    __u32 prefixlen;
    __u32 addr;
};

// Helper to update global stats
static __always_inline void update_global_stats(__u8 action, __u32 pkt_len) {
    __u32 key = 0;
    struct global_stats *stats = bpf_map_lookup_elem(&global_stats, &key);
    if (stats) {
        __sync_fetch_and_add(&stats->total_packets, 1);
        __sync_fetch_and_add(&stats->total_bytes, pkt_len);

        switch (action) {
            case ACTION_PASS:
                __sync_fetch_and_add(&stats->passed_packets, 1);
                break;
            case ACTION_DROP:
                __sync_fetch_and_add(&stats->dropped_packets, 1);
                break;
            case ACTION_INSPECT_IPS:
                __sync_fetch_and_add(&stats->ips_packets, 1);
                break;
            case ACTION_CAPTURE:
                __sync_fetch_and_add(&stats->capture_packets, 1);
                break;
            case ACTION_INSPECT_ALL:
                __sync_fetch_and_add(&stats->inspect_all_packets, 1);
                break;
        }
    }
}

// Helper to update rule stats
static __always_inline void update_rule_stats(__u32 rule_id, __u32 pkt_len) {
    struct rule_stats *stats = bpf_map_lookup_elem(&rule_stats, &rule_id);
    if (stats) {
        __sync_fetch_and_add(&stats->packets, 1);
        __sync_fetch_and_add(&stats->bytes, pkt_len);
        stats->last_hit = bpf_ktime_get_ns();
    }
}

// Check if IP matches rule
static __always_inline int match_ip(__u32 pkt_ip, __u32 rule_ip, __u32 mask) {
    return (pkt_ip & mask) == (rule_ip & mask);
}

// Main XDP packet steering program
SEC("xdp")
int xdp_packet_steering(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;
    __u32 pkt_len = data_end - data;

    // Parse Ethernet header
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) {
        return XDP_PASS;
    }

    __u16 eth_proto = bpf_ntohs(eth->h_proto);
    __u32 src_ip = 0, dst_ip = 0;
    __u8 protocol = 0;
    __u16 src_port = 0, dst_port = 0;

    // Handle VLAN tags
    if (eth_proto == ETH_P_8021Q || eth_proto == ETH_P_8021AD) {
        struct {
            __u16 tci;
            __u16 proto;
        } *vlan = (void *)(eth + 1);
        if ((void *)(vlan + 1) > data_end) {
            return XDP_PASS;
        }
        eth_proto = bpf_ntohs(vlan->proto);
    }

    // Parse IP header
    if (eth_proto == ETH_P_IP) {
        struct iphdr *iph = (void *)(eth + 1);
        if ((void *)(iph + 1) > data_end) {
            return XDP_PASS;
        }

        src_ip = iph->saddr;
        dst_ip = iph->daddr;
        protocol = iph->protocol;

        // Parse L4 headers for port info
        void *l4_hdr = (void *)iph + (iph->ihl * 4);

        if (protocol == IPPROTO_TCP) {
            struct tcphdr *tcph = l4_hdr;
            if ((void *)(tcph + 1) > data_end) {
                goto apply_default;
            }
            src_port = bpf_ntohs(tcph->source);
            dst_port = bpf_ntohs(tcph->dest);
        } else if (protocol == IPPROTO_UDP) {
            struct udphdr *udph = l4_hdr;
            if ((void *)(udph + 1) > data_end) {
                goto apply_default;
            }
            src_port = bpf_ntohs(udph->source);
            dst_port = bpf_ntohs(udph->dest);
        }
    } else if (eth_proto == ETH_P_IPV6) {
        // IPv6 support - simplified, just pass for now
        goto apply_default;
    } else {
        // Non-IP traffic, pass through
        return XDP_PASS;
    }

    // Quick whitelist check (LPM)
    struct lpm_key wl_key = { .prefixlen = 32, .addr = src_ip };
    __u8 *wl_val = bpf_map_lookup_elem(&ip_whitelist, &wl_key);
    if (wl_val) {
        update_global_stats(ACTION_PASS, pkt_len);
        return XDP_PASS;
    }

    // Quick blacklist check (LPM)
    struct lpm_key bl_key = { .prefixlen = 32, .addr = src_ip };
    __u8 *bl_val = bpf_map_lookup_elem(&ip_blacklist, &bl_key);
    if (bl_val) {
        update_global_stats(ACTION_DROP, pkt_len);
        return XDP_DROP;
    }

    // Evaluate filter rules in priority order
    #pragma unroll
    for (__u32 i = 0; i < 64; i++) {  // Check first 64 rules max
        struct filter_rule *rule = bpf_map_lookup_elem(&filter_rules, &i);
        if (!rule || !rule->enabled) {
            continue;
        }

        int matched = 0;

        switch (rule->match_type) {
            case MATCH_SRC_IP:
                matched = (src_ip == rule->match_ip);
                break;
            case MATCH_DST_IP:
                matched = (dst_ip == rule->match_ip);
                break;
            case MATCH_SRC_NET:
                matched = match_ip(src_ip, rule->match_ip, rule->match_mask);
                break;
            case MATCH_DST_NET:
                matched = match_ip(dst_ip, rule->match_ip, rule->match_mask);
                break;
            case MATCH_SRC_PORT:
                matched = (src_port == rule->match_port);
                break;
            case MATCH_DST_PORT:
                matched = (dst_port == rule->match_port);
                break;
            case MATCH_PROTOCOL:
                matched = (protocol == (__u8)rule->match_proto);
                break;
        }

        if (matched) {
            update_rule_stats(i, pkt_len);
            update_global_stats(rule->action, pkt_len);

            switch (rule->action) {
                case ACTION_PASS:
                    return XDP_PASS;
                case ACTION_DROP:
                    return XDP_DROP;
                case ACTION_INSPECT_IPS:
                case ACTION_CAPTURE:
                case ACTION_INSPECT_ALL:
                    // For inspection actions, pass to kernel for further
                    // processing by Suricata/Arkime via AF_PACKET
                    return XDP_PASS;
            }
        }
    }

apply_default:
    // Default action: inspect all traffic
    update_global_stats(ACTION_INSPECT_ALL, pkt_len);
    return XDP_PASS;
}

char LICENSE[] SEC("license") = "GPL";
