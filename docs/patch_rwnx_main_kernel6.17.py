#!/usr/bin/env python3
# Runs ON the BC250. Patches rwnx_main.c cfg80211 ops for kernel 6.17 API.
import sys, os, shutil
F = os.path.expanduser("~/aic8800d80/drivers/aic8800/aic8800_fdrv/rwnx_main.c")
shutil.copyfile(F, F + ".orig")
with open(F) as fh:
    lines = fh.read().split("\n")

GUARD = "#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)"

def find_one(pred, what):
    idxs = [i for i, l in enumerate(lines) if pred(i, l)]
    if len(idxs) != 1:
        print(f"FAIL: expected 1 match for [{what}], got {len(idxs)}: {idxs}")
        sys.exit(1)
    return idxs[0]

# ---- Patch 1: set_monitor_channel def -- add 'struct net_device *dev,' before chandef
i = find_one(lambda i, l: l.strip() == "struct cfg80211_chan_def *chandef) {"
             and "set_monitor_channel" in lines[i-1],
             "set_monitor_channel chandef line")
indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
lines[i:i] = [GUARD,
              indent + "struct net_device *dev,",
              "#endif"]

# ---- Patch 1b: caller rwnx_cfg80211_set_monitor_channel(wiphy, NULL);
i = find_one(lambda i, l: l.strip() == "rwnx_cfg80211_set_monitor_channel(wiphy, NULL);",
             "set_monitor_channel caller")
ind = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
lines[i:i+1] = [GUARD,
                ind + "rwnx_cfg80211_set_monitor_channel(wiphy, NULL, NULL);",
                "#else",
                ind + "rwnx_cfg80211_set_monitor_channel(wiphy, NULL);",
                "#endif"]

# ---- Patch 2: set_wiphy_params -- add int radio_idx
i = find_one(lambda i, l: l.strip() == "static int rwnx_cfg80211_set_wiphy_params(struct wiphy *wiphy, u32 changed) {",
             "set_wiphy_params def")
lines[i:i+1] = ["static int rwnx_cfg80211_set_wiphy_params(struct wiphy *wiphy,",
                GUARD,
                "                                          int radio_idx,",
                "#endif",
                "                                          u32 changed) {"]

# ---- Patch 3: set_tx_power -- add int radio_idx before the type param
i = find_one(lambda i, l: l.strip() == "enum nl80211_tx_power_setting type,",
             "set_tx_power type line")
indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
lines[i:i] = [GUARD,
              indent + "int radio_idx,",
              "#endif"]

# ---- Patch 4: start_radar_detection -- add trailing , int link_id
j = find_one(lambda i, l: l.strip() == "u32 cac_time_ms", "start_radar_detection cac_time_ms")
# find the ') {' that closes the param list, after j
k = next(idx for idx in range(j, len(lines)) if lines[idx].strip() == ") {")
indent = "                                               "
lines[k:k] = [GUARD,
              indent + ", int link_id",
              "#endif"]

with open(F, "w") as fh:
    fh.write("\n".join(lines))
print("PATCH OK: all 5 edits applied")
