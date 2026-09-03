// EWOS-52 createPaidOrder 로직 테스트 (PortOne 목킹 + Firestore 에뮬레이터).
// 실행: firebase emulators:exec --only firestore "node --test functions/test" (루트에서)
//  - PortOne HTTP(fetch)를 목으로 대체해 결제 상태/금액을 제어한다.
//  - 검증: 결제완료+금액일치→주문생성 / 금액불일치→환불+주문없음 / 미결제→거부 / 멱등.
import {test, before, beforeEach, after} from "node:test";
import assert from "node:assert/strict";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import ftest from "firebase-functions-test";

process.env.PORTONE_API_SECRET = "test-secret";
process.env.GCLOUD_PROJECT = "demo-ewos";

initializeApp({projectId: "demo-ewos"});
const db = getFirestore();
const fft = ftest({projectId: "demo-ewos"});

// PortOne fetch 목: mockPayment로 GET 응답을 제어하고, cancel 호출을 기록한다.
let mockPayment = {status: "PAID", currency: "KRW", amount: {total: 2000}};
let cancelCalls = [];
globalThis.fetch = async (url, opts) => {
  if (String(url).includes("/cancel")) {
    cancelCalls.push(JSON.parse(opts.body));
    return {ok: true, json: async () => ({})};
  }
  return {ok: true, json: async () => mockPayment};
};

const {createPaidOrder} = await import("../lib/payments.js");
const wrapped = fft.wrap(createPaidOrder);

const call = (paymentId, qtys = {prod1: 2}) =>
  wrapped({data: {paymentId, qtys}, auth: {uid: "p1"}});
const ordersByPayment = async (paymentId) =>
  (await db.collection("orders").where("paymentId", "==", paymentId).get()).docs;

before(async () => {
  await db.doc("users/p1").set({role: "partner", partnerId: "PA"});
  await db.doc("partners/PA").set({active: true, name: "테스트상사"});
  await db.doc("products/prod1").set({enabled: true, price: 1000, name: "사과"});
});
beforeEach(() => {
  mockPayment = {status: "PAID", currency: "KRW", amount: {total: 2000}};
  cancelCalls = [];
});
after(() => fft.cleanup());

test("결제완료+금액일치 → 주문 생성(paid), 환불 없음", async () => {
  const res = await call("pay_ok");
  assert.ok(res.orderNo);
  const docs = await ordersByPayment("pay_ok");
  assert.equal(docs.length, 1);
  assert.equal(docs[0].data().paymentStatus, "paid");
  assert.equal(docs[0].data().totalAmount, 2000);
  assert.equal(cancelCalls.length, 0);
});

test("결제금액≠주문금액 → 자동 환불 + 주문 미생성", async () => {
  mockPayment = {status: "PAID", currency: "KRW", amount: {total: 999}};
  await assert.rejects(() => call("pay_mismatch"));
  assert.equal((await ordersByPayment("pay_mismatch")).length, 0);
  assert.equal(cancelCalls.length, 1);
});

test("미결제(status≠PAID) → 거부, 환불 없음", async () => {
  mockPayment = {status: "READY", currency: "KRW", amount: {total: 2000}};
  await assert.rejects(() => call("pay_ready"));
  assert.equal((await ordersByPayment("pay_ready")).length, 0);
  assert.equal(cancelCalls.length, 0);
});

test("발주 중지 품목 → 자동 환불 + 주문 미생성", async () => {
  await db.doc("products/prod2").set({enabled: false, price: 500, name: "배"});
  await assert.rejects(() => call("pay_disabled", {prod2: 1}));
  assert.equal((await ordersByPayment("pay_disabled")).length, 0);
  assert.equal(cancelCalls.length, 1);
});

test("같은 paymentId 재호출 → 멱등(주문 1건, 중복 생성 없음)", async () => {
  const a = await call("pay_idem");
  const b = await call("pay_idem");
  assert.equal(a.orderNo, b.orderNo);
  assert.equal(b.duplicated, true);
  assert.equal((await ordersByPayment("pay_idem")).length, 1);
});

// EWOS-53: 일반 사용자(customer)도 partnerId 없이 주문 생성(customerId 기록).
test("customer(구글 가입) 주문 → customerId로 생성, partnerId 없음", async () => {
  await db.doc("users/c1").set({role: "customer", email: "c@x.com"});
  const res = await wrapped({
    data: {
      paymentId: "pay_cust", qtys: {prod1: 2},
      customerName: "홍길동", phone: "01011112222", shippingAddress: "서울시",
    },
    auth: {uid: "c1"},
  });
  assert.ok(res.orderNo);
  const docs = await ordersByPayment("pay_cust");
  assert.equal(docs.length, 1);
  assert.equal(docs[0].data().customerId, "c1");
  assert.equal(docs[0].data().partnerId, null);
  assert.equal(docs[0].data().customerName, "홍길동");
});
