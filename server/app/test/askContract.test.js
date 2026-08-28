import test from "node:test";
import assert from "node:assert/strict";
import { normalizeAskResponse, parseAskRequest } from "../src/contracts/askContract.js";

test("parseAskRequest trims valid input", () => {
  const result = parseAskRequest({
    message: "  聊聊今天下午  ",
    locale: "zh-CN",
    timezone: "Asia/Shanghai"
  });

  assert.equal(result.ok, true);
  assert.equal(result.value.message, "聊聊今天下午");
});

test("parseAskRequest rejects empty message", () => {
  const result = parseAskRequest({ message: "   " });

  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
});

test("normalizeAskResponse limits malformed basis items", () => {
  const result = normalizeAskResponse({
    answer: "  ok  ",
    basis: [
      { label: "今天", value: "3 场会议" },
      { label: "", value: "skip" },
      { label: "规律", value: "90 分钟以上" },
      { label: "多余", value: "会被保留到上限内" },
      { label: "第四个", value: "被截断" }
    ],
    safety_note: "  共现不代表因果  "
  });

  assert.equal(result.answer, "ok");
  assert.equal(result.basis.length, 3);
  assert.equal(result.safety_note, "共现不代表因果");
});
