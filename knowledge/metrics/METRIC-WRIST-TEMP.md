---
card_id: METRIC-WRIST-TEMP
metric_zh: 夜间腕温（睡眠腕部皮肤温度偏差）
metric_bindings:
  - HKQuantityTypeIdentifierAppleSleepingWristTemperature
what_it_is: >
  Apple Watch（Series 8 及以后 / Ultra / SE 3）在睡眠期间每 5 秒采样一次腕部皮肤温度，
  汇总为"相对个人基线的夜间偏差值"（如 +0.2°C / −0.4°C）。基线由约 5 晚睡眠数据建立，
  数值反映的是"今晚比你自己的常态高/低多少"。
what_it_is_not: >
  不是绝对体温，不是核心体温，不是医学体温计读数，不能用于诊断发热或疾病；
  Apple 官方明确该功能非医疗器械。腕部皮肤温度受环境影响远大于口腔/核心体温。
safe_claim_style: >
  只描述"相对自身基线的偏差 + 与用户自报事件的时间共现"。
  示例："你最近 5 晚腕温比基线高约 0.3°C，这与你标记的黄体期时间段重合"；
  不下生理结论，不做医疗判断，异常持续升高只建议用户留意并咨询专业人士。
avoid_claims:
  - 禁止把腕温偏差换算或表述为绝对体温 / 核心体温（如"你的体温是37.2°C"）。
  - 禁止诊断类断言：发烧、感染、怀孕、排卵日确认、甲状腺问题等。
  - 禁止把腕温升高单因归因（"升温=排卵后"），必须同时列出饮酒、室温、疾病等混杂可能。
  - 禁止用腕温做避孕/受孕决策建议（文献中假阳性率不可忽略，且Apple数据口径非为此设计）。
  - 禁止在基线未建立（<5晚有效数据）时输出任何趋势结论。
internal_priority_note: 本卡各假设按 P1(系统综述/荟萃) P2(叙述综述/观察/单RCT) P3(小样本) 标注
last_reviewed: 2026-08-28
---

# 夜间腕温（AppleSleepingWristTemperature）知识卡

## 1. 生理机制

- 远端皮肤温度（手腕、脚踝）由皮肤血管舒缩调控，是核心体温调节的"散热窗口"：入睡前后远端血管扩张、散热增加，远端皮温升高、核心体温下降。因此夜间腕温与核心体温**不是同一指标**，但两者受同一套体温调节系统驱动。
- 孕激素（黄体期）具有致热效应，会整体上调体温调定点；这一效应在夜间连续测量的皮肤温度中同样可见（Shilaih 2018）。
- 夜间连续采样（Apple 每 5 秒一次）相比晨起单点基础体温（BBT），能避开昼夜节律相位上"单点落在哪"的偶然性，对周期性温度变化更敏感（Zhu 2021）。
- Apple 的实现：睡眠专注模式下佩戴，双温度传感器（背面贴皮 + 表盘下方）用于扣除环境偏置，输出为相对个人基线的偏差值。

## 2. 已知影响因素

| 因素 | 方向与量级 | 优先级 | 出处 |
|---|---|---|---|
| 月经周期相位（黄体期） | 排卵后黄体期腕部皮温升高，文献量级约 +0.33°C（早黄体期 vs 易孕窗口） | P1 | Shilaih 2018（已核实） |
| 疾病 / 发热 | 感染性疾病期间远端皮温显著高于基线，可先于主观症状出现 | P1 | Smarr 2020（已核实） |
| 饮酒 | 酒精致外周血管扩张，饮酒夜腕部皮温倾向升高；但 Zhu 2021 报告周期相位信号对饮酒等混杂相对稳健 | P2 | Zhu 2021（已核实）；酒精—皮温专门研究待核实 |
| 环境温度 / 被子 | 室温过高、厚被子会整体抬高皮温读数；Apple 双传感器仅部分补偿 | P2 | Apple 支持文档（已核实，机制常识） |
| 时差 / 昼夜节律紊乱 | 跨时区后核心体温节律相位漂移，夜间测量窗对应的温度段改变，读数可漂移数日 | P3 | 昼夜节律生理学常识，具体量级未能在线核实 |

## 3. analysis_hypotheses（核心节）

### H1. 黄体期腕温升高，可作为周期相位标记 【P1】
- **陈述**：排卵后（黄体期）夜间腕温相对基线升高，量级参考文献约 +0.3°C；升温持续段可用于事后标注黄体期区间。
- **方向**：黄体期 > 卵泡期。
- **数据字段**：AppleSleepingWristTemperature（夜间偏差值）+ HKCategoryTypeIdentifierMenstrualFlow（月经起始，用于对齐周期）。
- **最少样本**：≥2 个完整周期、每周期 ≥70% 夜有腕温值，才做首次相位标注；≥3 个周期才谈"个人规律"。
- **出处**：Shilaih 2018（136 人 437 周期，82% 周期检出持续 3 天升温，+0.33°C）；Zhu 2021（腕温对排卵检出真阳性率 54.9%，高于 BBT 的 20.2%，但假阳性率 8.8%——所以只做"相位标记"，不做"排卵日确认"）。

### H2. 腕温异常持续升高与疾病相关 【P1】
- **陈述**：腕温连续 ≥2 晚高出个人基线明显幅度（且不在预期黄体期窗口内），与用户自报生病/不适日存在时间共现。
- **方向**：病中/病前数日 > 常态。
- **数据字段**：AppleSleepingWristTemperature + 用户主观记录（生病/症状标签）+ 静息心率（HKQuantityTypeIdentifierRestingHeartRate，作旁证）。
- **最少样本**：≥1 次自报患病事件 + 事件前后各 ≥5 晚数据；输出措辞只能是"共现提示"，并附"如持续不适请咨询医生"。
- **出处**：Smarr 2020（可穿戴设备连续测温可捕捉发热事件，部分先于症状）。

### H3. 饮酒夜腕温升高 【P2】
- **陈述**：用户标记饮酒的当晚，腕温偏差高于其非饮酒夜均值。
- **方向**：饮酒夜 > 非饮酒夜。
- **数据字段**：AppleSleepingWristTemperature + 用户饮酒标签（主观记录；或 HKQuantityTypeIdentifierNumberOfAlcoholicBeverages）。
- **最少样本**：≥5 个饮酒夜 + ≥10 个非饮酒夜（尽量同周期相位内比较，避免相位混杂）。
- **出处**：机制（酒精外周血管扩张）为生理学常识；Zhu 2021 提及饮酒是 BBT 的经典混杂。腕温—饮酒的直接定量研究**待核实**。

### H4. 腕温相位标记与主观状态的个人关联（探索性） 【P3】
- **陈述**：由 H1 标注出的黄体期区间内，用户主观记录（睡眠质量、情绪、疲劳）与卵泡期存在个人层面差异。
- **方向**：不预设，探索性双向。
- **数据字段**：H1 输出的相位标注 + 主观记录字段。
- **最少样本**：≥3 个完整周期。
- **出处**：无直接文献，属本系统内部探索假设。

## 4. confounds（混杂因素）

- **Apple 口径本身**：只提供相对基线偏差，基线是滚动建立的个人参照——换新表、长期停戴后重戴都会重建基线（约 5 晚），跨越这些断点的前后数值不可直接比较。
- **被子 / 室温 / 空调**：整体抬高或压低夜间皮温；换季、换寝具时段的趋势变化应先怀疑环境。
- **手表松紧与佩戴位置**：过松导致贴合差、读数偏低或缺失；佩戴手/位置改变也影响可比性。
- **同床者、宠物、电热毯**等局部热源。
- **相位与事件叠加**：黄体期 + 饮酒 + 微恙可能叠加出大偏差，分析时需分层或标注多重事件，不可单因归因。

## 5. 数据质量注意

- **有值条件**：需开启睡眠专注并佩戴入睡，每晚睡眠追踪 ≥4 小时；未连续佩戴的夜没有数据点（缺失不代表异常）。
- **基线建立**：约 5 晚有效睡眠后才出现偏差值；此前显示"需要更多数据"，系统不得对该阶段做任何解读。
- **设备范围**：Apple Watch Series 8 及以后、Ultra 全系、SE 3（SE 1/2 与 Series 7 及更早无此数据）。
- **每晚一个聚合值**：HealthKit 中通常为每晚一条样本（偏差值），不是连续曲线；分析粒度按"夜"计。
- **缺失处理**：周期内腕温覆盖率 <70% 时，H1 相位标注降级为"数据不足"，不输出区间。

## 6. 参考文献

1. Shilaih M, Goodale BM, Falco L, et al. Modern fertility awareness methods: wrist wearables capture the changes in temperature associated with the menstrual cycle. *Bioscience Reports*. 2018;38(6):BSR20171279. DOI: 10.1042/BSR20171279. PMID: 29175999. **【已核实：PubMed / Portland Press，2026-08-28】**
2. Zhu TY, Rothenbühler M, Hamvas G, et al. The Accuracy of Wrist Skin Temperature in Detecting Ovulation Compared to Basal Body Temperature: Prospective Comparative Diagnostic Accuracy Study. *J Med Internet Res*. 2021;23(6):e20710. DOI: 10.2196/20710. PMID: 34100763. **【已核实：jmir.org / PubMed，2026-08-28。注意：刊名为 J Med Internet Res，常被误引为 JMIR mHealth】**
3. Smarr BL, et al. Feasibility of continuous fever monitoring using wearable devices. *Scientific Reports*. 2020;10:21640. PMID: 33318528. **【已核实：nature.com / PubMed，2026-08-28】**
4. Apple Support. Track your nightly wrist temperature changes with Apple Watch. https://support.apple.com/en-au/102674 **【已核实：官方支持文档，含 5 晚基线、非医疗器械声明，2026-08-28】**
5. Apple Developer Documentation. appleSleepingWristTemperature (HKQuantityTypeIdentifier). https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingwristtemperature **【已核实：官方开发者文档，2026-08-28】**
6. 酒精与夜间远端皮肤温度的直接定量研究：**待核实**（本卡仅引用其生理机制常识，未标注具体 PMID）。
7. 时差/昼夜节律相位漂移对夜间腕温读数影响的定量研究：**未能在线核实**。
