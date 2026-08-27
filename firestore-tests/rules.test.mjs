// EWOS-29 Firestore 보안 규칙 테스트 (에뮬레이터).
// 실행: firebase-tools + Java 필요 →  npm --prefix firestore-tests test
// 완료 기준 체크리스트 7개를 자동화한다. 역할 격리·위조·비활성 거래처 차단을 검증한다.
import {readFileSync} from 'node:fs';
import {test, before, after, beforeEach} from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc} from 'firebase/firestore';

const PROJECT_ID = 'ewos-rules-test';
const RULES = readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8');

/** 규칙 우회 컨텍스트로 시드 데이터를 심는다(운영자/거래처/주문/시크릿). */
async function seed(env) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/op1'), {role: 'operator'});
    await setDoc(doc(db, 'users/p1'), {role: 'partner', partnerId: 'PA'});
    await setDoc(doc(db, 'users/p2'), {role: 'partner', partnerId: 'PB'});
    await setDoc(doc(db, 'users/pc'), {role: 'partner', partnerId: 'PC'});
    await setDoc(doc(db, 'partners/PA'), {name: 'A', active: true, addresses: []});
    await setDoc(doc(db, 'partners/PB'), {name: 'B', active: true, addresses: []});
    await setDoc(doc(db, 'partners/PC'), {name: 'C', active: false, addresses: []});
    await setDoc(doc(db, 'orders/oA'), _order('PA'));
    await setDoc(doc(db, 'orders/oB'), _order('PB'));
    await setDoc(doc(db, 'secrets/cafe24'), {accessToken: 'x'});
    await setDoc(doc(db, 'products/prod1'), {name: '사과', price: 1000, enabled: true});
  });
}

function _order(partnerId) {
  return {
    source: 'app', status: 'new', partnerId, orderNo: '20260826-1',
    partnerName: '테스트', items: [{name: '사과', qty: 1}], totalAmount: 1000,
    paymentStatus: 'unpaid', history: [], updatedAt: new Date(),
  };
}

let env;
const asOp = () => env.authenticatedContext('op1').firestore();
const asP1 = () => env.authenticatedContext('p1').firestore();
const asP2 = () => env.authenticatedContext('p2').firestore();
const asInactive = () => env.authenticatedContext('pc').firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: RULES},
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); await seed(env); });

// ① 거래처 A는 거래처 B의 주문을 조회할 수 없다 / 자기 주문은 조회할 수 있다.
test('거래처는 타 거래처 주문 read 거부, 자기 주문 read 허용', async () => {
  await assertFails(getDoc(doc(asP1(), 'orders/oB')));
  await assertSucceeds(getDoc(doc(asP1(), 'orders/oA')));
});

// ② 거래처는 주문 상태를 임의 변경할 수 없다(취소 외). 운영자는 가능.
test('거래처의 status 변경은 취소만 허용, 그 외 거부 / 운영자는 허용', async () => {
  await assertFails(updateDoc(doc(asP1(), 'orders/oA'),
    {status: 'processing', updatedAt: new Date()}));
  await assertSucceeds(updateDoc(doc(asP1(), 'orders/oA'),
    {status: 'canceled', history: [], updatedAt: new Date()}));
  await assertSucceeds(updateDoc(doc(asOp(), 'orders/oB'),
    {status: 'processing'}));
});

// ③ 거래처는 타 partnerId·조작된 형태로 주문을 생성할 수 없다. 자기 정상 주문은 허용.
test('타 partnerId 주문 create 거부 / 자기 정상 주문 허용', async () => {
  await assertFails(setDoc(doc(asP1(), 'orders/new1'), _order('PB')));
  await assertSucceeds(setDoc(doc(asP1(), 'orders/new2'), _order('PA')));
});

// ④ items/금액이 조작된 주문은 거부(스키마 유효성).
test('items 비어있거나 음수 금액 주문 create 거부', async () => {
  const bad1 = {..._order('PA'), items: []};
  const bad2 = {..._order('PA'), totalAmount: -5};
  await assertFails(setDoc(doc(asP1(), 'orders/bad1'), bad1));
  await assertFails(setDoc(doc(asP1(), 'orders/bad2'), bad2));
});

// ⑤ 클라이언트는 users.role·partnerId를 수정할 수 없다. fcmTokens만 허용.
test('role/partnerId 수정 거부, fcmTokens 갱신 허용', async () => {
  await assertFails(updateDoc(doc(asP1(), 'users/p1'), {role: 'operator'}));
  await assertFails(updateDoc(doc(asP1(), 'users/p1'), {partnerId: 'PB'}));
  await assertSucceeds(updateDoc(doc(asP1(), 'users/p1'), {fcmTokens: ['t1']}));
});

// ⑥ 카페24 토큰 등 시크릿 컬렉션은 클라이언트가 읽거나 쓸 수 없다.
test('secrets 컬렉션 클라이언트 접근 전면 거부', async () => {
  await assertFails(getDoc(doc(asP1(), 'secrets/cafe24')));
  await assertFails(getDoc(doc(asOp(), 'secrets/cafe24')));
  await assertFails(setDoc(doc(asOp(), 'secrets/x'), {a: 1}));
});

// ⑦ 비활성(active=false) 거래처는 자기 주문에도 접근할 수 없다(EWOS-29 신규).
test('비활성 거래처는 자기 데이터 접근 거부', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'orders/oC'), _order('PC'));
  });
  await assertFails(getDoc(doc(asInactive(), 'orders/oC')));
  await assertFails(setDoc(doc(asInactive(), 'orders/newC'), _order('PC')));
  // 단, 자기 partners 문서 read는 '비활성 안내' 표시를 위해 허용돼야 한다.
  await assertSucceeds(getDoc(doc(asInactive(), 'partners/PC')));
});

// ⑧ EWOS-42: settings/appConfig는 미로그인도 read 가능(시작 게이트), write는 운영자만.
test('appConfig는 공개 read / 운영자만 write', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'settings/appConfig'),
      {minVersion: '1.0.0', maintenance: false});
  });
  const anon = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(anon, 'settings/appConfig')));
  await assertFails(setDoc(doc(asP1(), 'settings/appConfig'), {maintenance: true}));
  await assertSucceeds(setDoc(doc(asOp(), 'settings/appConfig'), {maintenance: true}));
});

// ⑨ EWOS-52: 결제완료(paid) 주문은 클라이언트가 만들 수 없다(Functions 전용).
test('paid 주문은 클라이언트 생성 불가 / unpaid는 허용', async () => {
  const paid = {..._order('PA'), paymentStatus: 'paid'};
  await assertFails(setDoc(doc(asP1(), 'orders/paid1'), paid));
  await assertSucceeds(setDoc(doc(asP1(), 'orders/unpaid1'), _order('PA')));
});
