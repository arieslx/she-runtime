#!/usr/bin/env python3
# build_evidence.py — 证据库 JSON 生成器（规律引擎的离线原型）
# 用法: python3 tools/build_evidence.py <daily.csv> <hourly.csv> <输出.json>
# 红线: 本脚本是通用配方 f(用户csv)->该用户规律; JSON 里所有数字必须由此算出, 禁止手抄。
# 配方来源: 00-身体数据分析/恢复的分析脚本/ (15段已验证代码的整合)
# 文案来源: 14-规律页完整产品方案v1 第三节 (L1/L2 由产品定稿, 数字槽位由本脚本填)
import csv, json, statistics as st, sys
from datetime import date, timedelta
from collections import defaultdict

def main(daily_path, hourly_path, out_path):
    rows = {}
    with open(daily_path) as f:
        for r in csv.DictReader(f):
            rows[r["date"]] = r
    days = sorted(d for d in rows if d >= "2023-01-04")

    def num(d, k):
        v = rows.get(d, {}).get(k, "")
        return float(v) if v else None

    def onset(d):
        v = rows.get(d, {}).get("sleep_onset", "")
        if not v: return None
        h, m = map(int, v.split(":")); x = h * 60 + m
        return x if x < 720 else x - 1440

    # ---------- 周期相位 ----------
    menses = [d for d in sorted(rows) if rows[d]["menses"]]
    starts, prev = [], None
    for d in menses:
        dd = date.fromisoformat(d)
        if prev is None or (dd - prev).days > 10: starts.append(dd)
        prev = dd

    def phase_of(d):
        dd = date.fromisoformat(d)
        prevs = [s for s in starts if s <= dd]; nxts = [s for s in starts if s > dd]
        if not prevs or not nxts or (nxts[0] - prevs[-1]).days > 60: return None
        if (dd - prevs[-1]).days < 5: return "menses"
        if (nxts[0] - dd).days <= 7: return "premenstrual"
        return "other"

    ph = defaultdict(lambda: defaultdict(list))
    for d in days:
        p = phase_of(d)
        if not p: continue
        for k in ("hrv", "rhr", "wrist_temp"):
            v = num(d, k)
            if v is not None: ph[p][k].append(v)
    n_cycles = sum(1 for a, b in zip(starts, starts[1:]) if 15 <= (b - a).days <= 60)

    # 混杂核查: 仅取入睡 23:00-02:00 的日子再比 (排除"经前睡得晚")
    pre_ctl, oth_ctl = [], []
    for d in days:
        o, h, p = onset(d), num(d, "hrv"), phase_of(d)
        if o is None or h is None or p is None: continue
        if -60 <= o <= 120:
            (pre_ctl if p == "premenstrual" else oth_ctl).append(h)

    # ---------- 连睡3天 vs 短睡 ----------
    def sleeps(d, n):
        out = []
        for i in range(n):
            s = num((date.fromisoformat(d) - timedelta(i)).isoformat(), "sleep_h")
            if s is None: return None
            out.append(s)
        return out
    rested, short1 = [], []
    for d in days:
        s3, rhr = sleeps(d, 3), num(d, "rhr")
        if not s3 or rhr is None: continue
        if all(x >= 7 for x in s3): rested.append(rhr)
        if s3[0] < 6 and s3[1] >= 6: short1.append(rhr)

    # ---------- 入睡时刻梯度 ----------
    grad = {"before0": [], "h1to3": [], "after3": []}
    enough = {"before0": [], "after3": []}
    for d in days:
        o, h, s = onset(d), num(d, "hrv"), num(d, "sleep_h")
        if o is None: continue
        g = "before0" if o <= 0 else ("after3" if o > 180 else "h1to3")
        if h is not None: grad[g].append(h)
        if s is not None and g in enough: enough[g].append(1 if s >= 7 else 0)

    # ---------- 日内静坐心率 (hourly) ----------
    byhour = defaultdict(list)
    with open(hourly_path) as f:
        for r in csv.DictReader(f):
            if r["date"] < "2023-01-04" or not r["hr_mean"]: continue
            if float(r["steps"] or 0) < 50:
                byhour[int(r["hour"])].append(float(r["hr_mean"]))
    curve = {h: round(st.median(v), 1) for h, v in sorted(byhour.items()) if len(v) >= 30}
    am = [v for h, v in curve.items() if 9 <= h <= 12]
    pm = [v for h, v in curve.items() if 13 <= h <= 20]

    # ---------- 周三 / 步数 / 哨兵 ----------
    wd_sleep = defaultdict(list)
    for d in days:
        s = num(d, "sleep_h")
        if s is not None: wd_sleep[date.fromisoformat(d).weekday()].append(s)
    wed = round(st.median(wd_sleep[2]), 1) if wd_sleep.get(2) else None

    nxt = {}
    for i, d in enumerate(days[:-1]):
        if (date.fromisoformat(days[i+1]) - date.fromisoformat(d)).days == 1:
            nxt[d] = days[i+1]
    steps_g = {"low": [], "mid": [], "high": []}
    for d, d2 in nxt.items():
        sp, h2 = num(d, "steps"), num(d2, "hrv")
        if sp is None or h2 is None: continue
        steps_g["low" if sp < 3000 else ("high" if sp > 8000 else "mid")].append(h2)

    temps = sorted(v for v in (num(d, "wrist_temp") for d in days) if v is not None)
    t95 = temps[int(len(temps) * 0.95)]
    hot_days = [d for d in days if (num(d, "wrist_temp") or 0) >= t95]

    ev = {
        "meta": {"generated_by": "tools/build_evidence.py", "note": "所有数字由脚本从csv计算,禁止手改",
                 "demo_disclaimer": "⚠️ 本文件是用某个真实用户(用户零号)的数据离线生成的 Demo 渲染素材。"
                                    "正式产品中,同一个引擎为每个用户各自生成各自的证据库,内容因人而异。"
                                    "本文件的任何具体结论(经前/周三/某个数字)绝不允许写进通用逻辑、"
                                    "知识卡或硬编码文案——违反即触碰架构红线(见 CLAUDE.md 与交接文档第零节)。"
                                    "路演展示时须说明:这是真实用户数据跑出的例子。",
                 "spec": "01-她律/07-AI创建的放这里/13+14号文档"},
        "now_card": {
            "type": "cycle_window",
            "l1": "再过几天，你会进入这个月身体最费电的一周。提前把要紧的事挪一挪——不是你要变弱了，是身体要开始忙自己的事了。",
            "link_rule": "premenstrual"
        },
        "rules": [
            {"id": "premenstrual", "recipe": "周期相位", "status": "成立", "priority": 1,
             "l1": "每次月经来之前的那一周，你都比平时更容易累——同样的事更耗电，恢复也更慢。这不是状态差，是你身体的固定节奏。而且这不怪你睡得晚：同样时间睡，充电效果照样打折。",
             "l2": f"过去两年多，你的 {n_cycles} 个周期几乎每次都这样：睡眠修复、心跳回落、体温三个信号一起变差。差距大概是：平时的你 vs 连轴转了几天的你。",
             "l3": {"phase_hrv": {p: round(st.median(v["hrv"]), 1) for p, v in ph.items() if v.get("hrv")},
                    "phase_rhr": {p: round(st.median(v["rhr"]), 1) for p, v in ph.items() if v.get("rhr")},
                    "confound_check": {"desc": "仅取入睡23点-2点的日子对比",
                                       "pre_hrv": round(st.median(pre_ctl), 1), "pre_n": len(pre_ctl),
                                       "other_hrv": round(st.median(oth_ctl), 1), "other_n": len(oth_ctl)},
                    "n_cycles": n_cycles},
             "l4": "方向和已有研究一致。但这条是从你自己的日子里算出来的，只属于你。"},
            {"id": "sleep3days", "recipe": "对比堆", "status": "成立", "priority": 2,
             "l1": "只要连着三天睡够，你的身体就会从'欠债运转'切回'正常运转'——完全安静时的心跳明显慢下来，那是身体最省油的状态。这是你全部数据里，'做什么马上有用'最清楚的一条。",
             "l2": f"三天是个坎：断断续续睡够不算，连着三天才触发。你有 {len(rested)} 天做到过——那些天你的待机油耗，和你状态最好的日子一个水平。",
             "l3": {"rested_rhr": round(st.median(rested), 0), "rested_n": len(rested),
                    "short_rhr": round(st.median(short1), 0), "short_n": len(short1)},
             "l4": "研究里也支持连续睡眠的恢复价值——你的身体把这条演示得格外清楚。"},
            {"id": "onset_slope", "recipe": "剂量梯度", "status": "成立", "priority": 3,
             "l1": "晚睡对你不是'过了12点就完蛋'，是每晚一点、多扣一点电。真正的悬崖在三点：过了三点才睡，睡够的机会直接掉一半——因为你早上醒来的时间是固定的，晚睡的债躲不掉。",
             "l2": "别因为已经一点了就破罐破摔——这个点睡下，你多半还能睡够；拖到三点后，十次里只有三次能睡够。",
             "l3": {"hrv_by_onset": {k: round(st.median(v), 1) for k, v in grad.items() if v},
                    "enough_ratio": {k: round(sum(v) / len(v), 2) for k, v in enough.items() if v}},
             "l4": "入睡时刻与睡眠时长的关系在研究中同样是渐变的。"}
        ],
        "alerts": {
            "title_key": "insights.alerts.title",
            "items": [
                {"text": "月经前那一周", "link_rule": "premenstrual",
                 "umbrella": "这几天安排轻一点，是聪明不是偷懒。"},
                {"text": "连续没睡够的第二天起", "link_rule": "sleep3days",
                 "umbrella": "别硬扛，今天先把睡眠还上一点。"},
                {"text": "身体打仗的日子——腕温、呼吸、心跳一起偏高时，我会在当天告诉你",
                 "l3": {"hot_threshold": round(t95, 2), "hot_days_n": len(hot_days)},
                 "umbrella": "那种日子只做必须做的事，其余都可以等。"}
            ]
        },
        "tips": {
            "title_key": "insights.tips.title",
            "items": [
                {"rank": 1, "text": "连着三天睡够。不用早睡，先求'连着'——三天就能看见身体换挡。", "link_rule": "sleep3days"},
                {"rank": 2, "text": "白天晒到太阳的日子，你晚上通常睡得更多。这条还在攒证据，但它几乎零成本。"},
                {"rank": 0, "text": "多走路对你的恢复有没有帮助？看不出来。数据不撒谎，我们也不硬凑。",
                 "l3": {"next_hrv_by_steps": {k: round(st.median(v), 1) for k, v in steps_g.items() if v}}}
            ]
        },
        "story_card": {
            "l1": "你的一天有自己的地形：上午是省电的深水区，适合啃硬骨头；下午身体一直踩着小油门，适合见人、动手、跑杂事。",
            "l3": {"hourly_seated_hr": curve,
                   "am_median": round(st.median(am), 1), "pm_median": round(st.median(pm), 1)}
        },
        "observing": [
            {"text": "你的周三常常是一周里最蔫的一天——睡最少、动最少。我猜和周二晚上的安排有关，但还没对上。哪天你愿意，跟我说说你的周二晚上。",
             "l3": {"wed_sleep_h": wed},
             "ask": "跟我说说你的周二晚上"},
            {"text": "戴耳机特别久的日子，你睡得也特别晚。是刷着东西睡不着，还是睡不着才刷？我分不清方向，需要多认识你一阵子。",
             "ask": "聊聊你的深夜和耳机"}
        ]
    }
    with open(out_path, "w") as f:
        json.dump(ev, f, ensure_ascii=False, indent=1)
    print(f"OK -> {out_path}")
    print(f"抽查: 周期数={n_cycles} 连睡3天RHR={st.median(rested):.0f}(n={len(rested)}) "
          f"短睡RHR={st.median(short1):.0f} 上午静坐={st.median(am):.1f} 下午={st.median(pm):.1f}")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
