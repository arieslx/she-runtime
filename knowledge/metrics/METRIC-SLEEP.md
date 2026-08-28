---
card_id: METRIC-SLEEP
metric_zh: 睡眠
metric_bindings: [HKCategoryTypeIdentifierSleepAnalysis]
what_it_is: Apple Health 记录的卧床/入睡时间段数据，含 inBed、asleepCore、asleepDeep、asleepREM、awake 等子状态，可推导总睡眠时长、入睡时刻、醒来时刻、夜间清醒次数与阶段占比。
what_it_is_not: 不是多导睡眠图（PSG）级别的临床睡眠数据；阶段划分是算法估计；不能诊断失眠、呼吸暂停等睡眠障碍；单晚数据不代表睡眠质量的全部。
safe_claim_style: "过去两周里，你睡眠不足 6.5 小时的夜晚，次日 HRV 偏低的情况可能同时出现，值得继续观察——这只是你个人数据里的共现模式，不是因果结论。"
avoid_claims:
  - "睡少一定会发胖 / 一定会生病"
  - "你的深睡只有 X 分钟，说明睡眠质量差"（阶段是算法估计，无诊断意义）
  - "昨晚睡眠不好导致了你今天情绪差"（单日因果归因）
  - "补觉可以完全抵消工作日欠下的睡眠债"
  - "HRV 低就是没睡好"（HRV 受饮酒、疾病、月经周期等多因素影响）
internal_priority_note: 本卡各假设按 P1(系统综述/荟萃) P2(叙述综述/观察/单RCT) P3(小样本) 标注
last_reviewed: 2026-08-28
---

# 睡眠（SleepAnalysis）指标知识卡

## 1. 生理机制（人话版）

睡眠由两股力量共同调度：醒得越久越困的"睡眠压力"（腺苷累积），和约 24 小时一轮的生物钟（受光照校准）。夜里大脑在核心睡眠、深睡、REM 之间循环，深睡偏重身体修复与激素分泌，REM 偏重情绪与记忆整理。睡眠时副交感神经占主导，所以静息心率下降、HRV 上升——这也是"夜间恢复指标"能反映睡眠的原因。睡不够或睡得乱，等于修复流程被打断、生物钟被拉扯。

## 2. 已知影响因素

- **睡眠剥夺/不足 → 自主神经**：RMSSD（HRV 时域指标）显著下降、LF/HF 上升，提示交感偏亢、迷走抑制。P1（11 项 RCT 荟萃，Frontiers in Neurology 2025，DOI 10.3389/fneur.2025.1556784）
- **连续限睡的累积效应**：每晚 4–6h 连续 14 天，认知损伤随天数线性累积，且主观困倦感"适应"了、客观损伤没有。P2（经典单 RCT，Van Dongen 2003，PMID 12683469）
- **作息规律性**：睡眠规律指数（SRI）比时长更强地预测全因死亡率（UK Biobank，6 万人加速度计数据）。P1-P2（大型前瞻队列，Windred 2023，PMID 37738616）
- **睡眠不足 → 情绪**：正性情绪下降、焦虑症状上升，效应在实验研究中稳定。P1（154 项实验、5715 人荟萃，Palmer 2024（epub 2023），PMID 38127505）
- **周末补觉**：可部分缓解困倦，但对代谢紊乱的修复有限，且周一重回短睡后损伤复现。P2（单 RCT，Depner 2019，PMID 30827911，已核实）
- **常见干扰因素**：酒精（压 REM、压 HRV）、咖啡因（延迟入睡）、晚间强光/屏幕（推迟生物钟）、月经周期（黄体期核心体温升高、部分人主观睡眠变差）。P2-P3（叙述综述层级，凭知识，待核）

## 3. analysis_hypotheses 可检验假设清单（核心节）

| # | 假设陈述 | 预期方向 | 需要的数据字段 | 最少样本量建议 | 出处 | 优先级 |
|---|---|---|---|---|---|---|
| H1 | 睡眠时长与次日晨间 HRV 正相关 | 短睡夜（<6.5h）→ 次日 HRV 偏低 | SleepAnalysis 时长；HeartRateVariabilitySDNN（晨间/夜间） | ≥30 晚，含 ≥8 个短睡夜 | Frontiers Neurol 2025 荟萃（P1） | 高 |
| H2 | 睡眠时长与次日静息心率负相关 | 短睡夜 → 次日 RestingHeartRate 偏高 | SleepAnalysis 时长；RestingHeartRate | ≥30 晚 | 同 H1 外推（P2） | 高 |
| H3 | 睡眠时长与次日主观精力正相关 | 短睡 → 主观精力评分低 | SleepAnalysis 时长；主观记录"精力"1–5 分 | ≥21 天连续主观记录 | Palmer 2024（epub 2023）（P1，情绪外推） | 高 |
| H4 | 入睡时刻标准差（周内）与该周平均 HRV/主观状态负相关 | 入睡时刻越飘 → HRV 越低、状态越差 | 每晚入睡时刻 → 按周算 SD；HRV 周均值；主观周均值 | ≥6 周（每周 ≥5 晚有数据） | Windred 2023（P1-P2） | 高 |
| H5 | 连续 ≥3 晚短睡（<6.5h）的次日损伤大于单晚短睡（累积效应） | 连续短睡段末尾的 HRV 降幅/精力降幅 > 单晚短睡 | 睡眠时长序列（识别连续段）；HRV；主观精力 | ≥60 晚，含 ≥3 个连续短睡段 | Van Dongen 2003（P2） | 高 |
| H6 | 周末补觉（周末均长 − 工作日均长 >1h）后，周一至周二指标只部分回升 | 补觉周的周一 HRV/精力 ≈ 部分恢复、非完全恢复 | 按星期几分组的睡眠时长；HRV；主观精力 | ≥8 周 | Depner 2019（P2，已核实） | 中 |
| H7 | 睡眠时长/夜间清醒次数与次日情绪相关 | 短睡或多醒 → 次日主观情绪评分低、焦虑感高 | SleepAnalysis 时长与 awake 段数；主观"情绪"评分 | ≥21 天连续记录 | Palmer 2024（epub 2023）（P1） | 中 |
| H8 | 主观精力与"总睡眠时长"的相关性强于与"深睡时长"的相关性 | 时长信号 > 阶段信号（阶段噪声大） | 总时长、深睡时长、主观精力 | ≥30 天 | 由第 5 节精度证据推出（P3） | 低 |

分析约定：一律做个人内（within-person）相关，先看共现、不下因果结论；报告措辞用 safe_claim_style。

## 4. confounds 混杂坑

- **缺失不随机**：忘戴手表/没电的夜晚常恰好是熬夜、出差、喝酒的夜晚——缺失本身与短睡相关，直接删缺失会低估短睡频率。分析前先统计缺失夜的星期分布。
- **阶段数据是算法估计**：深睡/REM 分钟数不是金标准，个体间不可比，个体内的小波动也可能纯属噪声。假设检验优先用总时长和入睡时刻。
- **反向因果——报复性熬夜**：压力大/情绪差的日子更可能主动熬夜，于是"短睡与次日情绪差"的相关里混着"情绪差导致熬夜"。需要用主观记录里的当日压力做分层。
- **共同原因**：疾病、饮酒、经前期可同时导致短睡+HRV 低+情绪差，三者相关不代表睡眠是原因。
- **卧床≠睡着**：inBed 与 asleep 差值大的夜晚（躺着刷手机），若误用 inBed 当时长会系统性高估。
- **午睡未计**：夜间短睡但白天补了午睡，"次日损伤"会被稀释。

## 5. 数据质量注意（Apple Watch 睡眠追踪）

- 睡/醒二分类灵敏度高（>90–95% 睡眠期被正确识别），但清醒特异度低（约 30–52%）——**夜间短暂清醒普遍被漏记，总睡眠时长倾向高估**。（六设备 PSG 对照研究，SLEEP Advances 2025，已核实）
- 四阶段分类与 PSG 仅中等一致（Apple Watch S8 κ≈0.53，为受测消费级设备中最高；REM 检出率约 69%），且**倾向高估浅睡、低估深睡**（Apple Watch 高估浅睡约 45 分钟、低估深睡约 43 分钟）。（同上 + Sensors 2024 三设备研究，已核实）
- 结论：适合看**个人长期趋势**，不适合逐夜解读阶段分钟数；单晚数据不作任何判断。
- 需佩戴入睡且开启睡眠定时/专注模式，否则可能整夜无记录；手动补录的数据无阶段信息，应与自动记录分开处理。
- 第三方 App 写入的睡眠数据与 Watch 原生数据可能重复，按 sourceName 去重。

## 6. 参考文献

1. Effects of sleep deprivation on heart rate variability: a systematic review and meta-analysis. Front Neurol. 2025. DOI: 10.3389/fneur.2025.1556784（PMC12394884）。【已在线核实】
2. Van Dongen HPA, et al. The cumulative cost of additional wakefulness… Sleep. 2003;26(2):117-26. PMID: 12683469, DOI: 10.1093/sleep/26.2.117。【已在线核实】
3. Windred DP, et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration. Sleep. 2024;47(1):zsad253. PMID: 37738616, DOI: 10.1093/sleep/zsad253。【已在线核实】
4. Palmer CA, et al. Sleep loss and emotion: a systematic review and meta-analysis of over 50 years of experimental research. Psychol Bull. 2024;150(4):440-463（epub 2023）. PMID: 38127505, DOI: 10.1037/bul0000410。【已在线核实】
5. A performance validation of six commercial wrist-worn wearable sleep-tracking devices for sleep stage scoring compared to polysomnography. SLEEP Advances. 2025;6(2):zpaf021（PMC12038347）。【已在线核实】
6. Accuracy of three commercial wearable devices for sleep tracking in healthy adults（Oura/Fitbit/Apple Watch vs PSG）. Sensors. 2024（PMC11511193，注意：ŌURA 资助）。【已在线核实（检索页）】
7. Depner CM, et al. Ad libitum weekend recovery sleep fails to prevent metabolic dysregulation… Curr Biol. 2019. PMID: 30827911, DOI: 10.1016/j.cub.2019.01.069。【已在线核实】
8. 酒精/咖啡因/光照/月经周期对睡眠影响的综述层级证据。【凭知识，待核】
