import {onRequest, onCall, CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {assertOperator} from "./invites";
import {notifyOperators} from "./notifications";

// Client ID/Secret은 코드·저장소에 두지 않는다.
// 발주처가 `firebase functions:secrets:set CAFE24_CLIENT_ID` 등으로 등록한다.
const CLIENT_ID = defineSecret("CAFE24_CLIENT_ID");
const CLIENT_SECRET = defineSecret("CAFE24_CLIENT_SECRET");

interface Cafe24Token {
  access_token: string;
  refresh_token: string;
  expires_at: string;
  refresh_token_expires_at: string;
}

/** client_id:client_secret 을 Basic 인증 헤더로 만든다. */
function basicAuth(): string {
  const raw = `${CLIENT_ID.value()}:${CLIENT_SECRET.value()}`;
  return `Basic ${Buffer.from(raw).toString("base64")}`;
}

/**
 * 운영자에게 보여줄 연동 상태를 cafe24Status/{mallId}에 남긴다.
 * 토큰 등 시크릿은 secrets(차단)에만 두고, 여기엔 노출해도 되는 요약만 쓴다.
 */
async function writeStatus(
  mallId: string, patch: Record<string, unknown>,
): Promise<void> {
  await getFirestore().collection("cafe24Status").doc(mallId).set(
    {mallId, ...patch, updatedAt: FieldValue.serverTimestamp()},
    {merge: true},
  );
}

/** 토큰 응답을 secrets/cafe24_{mallId}에 저장한다(규칙상 클라이언트 접근 불가). */
async function saveToken(mallId: string, t: Cafe24Token): Promise<void> {
  const accessExpiresAt = Timestamp.fromDate(new Date(t.expires_at));
  await getFirestore().collection("secrets").doc(`cafe24_${mallId}`).set({
    mallId,
    accessToken: t.access_token,
    refreshToken: t.refresh_token,
    accessExpiresAt,
    refreshExpiresAt: Timestamp.fromDate(new Date(t.refresh_token_expires_at)),
    updatedAt: FieldValue.serverTimestamp(),
  });
  // 연동 정상·만료 시각을 운영자 화면용 상태 문서에 반영한다.
  await writeStatus(mallId, {connected: true, accessExpiresAt});
}

const SCOPE = "mall.read_order,mall.read_product";

// 카페24에 등록한 Redirect URI와 정확히 일치해야 한다(토큰 교환 시 검증됨).
// req.hostname은 내부 Cloud Run 주소를 반환할 수 있어 동적 계산 대신 고정한다.
const REDIRECT_URI =
  "https://asia-northeast3-efodersystem.cloudfunctions.net/cafe24OAuthCallback";

/**
 * 설치 진입점 (App URL). 몰 관리자가 앱을 실행하면 카페24가 mall_id를 붙여 이 주소를 연다.
 * 여기서 카페24 인증(authorize) 페이지로 리다이렉트하고, 승인되면 Redirect URI로 돌아온다.
 */
export const cafe24Install = onRequest({secrets: [CLIENT_ID]}, (req, res) => {
  const mallId = req.query.mall_id as string | undefined;
  if (!mallId) {
    res.status(400).send("mall_id가 없습니다.");
    return;
  }
  const authorize =
    `https://${mallId}.cafe24api.com/api/v2/oauth/authorize?` +
    new URLSearchParams({
      response_type: "code",
      client_id: CLIENT_ID.value(),
      redirect_uri: REDIRECT_URI,
      scope: SCOPE,
      state: mallId,
    }).toString();
  res.redirect(authorize);
});

/**
 * OAuth 콜백 (Redirect URI). 몰 관리자가 앱 설치를 승인하면
 * 카페24가 code와 mall_id를 이 주소로 보낸다. code를 토큰으로 교환해 저장한다.
 */
export const cafe24OAuthCallback = onRequest(
  {secrets: [CLIENT_ID, CLIENT_SECRET]},
  async (req, res) => {
    const code = req.query.code as string | undefined;
    // 카페24는 콜백에 mall_id를 직접 주지 않고, authorize 때 넘긴 state로 돌려준다.
    const mallId =
      (req.query.mall_id ?? req.query.state) as string | undefined;
    if (!code || !mallId) {
      res.status(400).send("code 또는 mall_id가 없습니다.");
      return;
    }
    try {
      const body = new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: REDIRECT_URI,
      });
      const resp = await fetch(
        `https://${mallId}.cafe24api.com/api/v2/oauth/token`,
        {
          method: "POST",
          headers: {
            "Authorization": basicAuth(),
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: body.toString(),
        }
      );
      if (!resp.ok) {
        throw new Error(`토큰 교환 실패 ${resp.status}: ${await resp.text()}`);
      }
      await saveToken(mallId, (await resp.json()) as Cafe24Token);
      res.status(200).send("카페24 연동이 완료되었습니다. 이 창은 닫으셔도 됩니다.");
    } catch (e) {
      logger.error("cafe24 OAuth 콜백 실패", e);
      res.status(500).send("연동 처리 중 오류가 발생했습니다.");
    }
  }
);

/**
 * Access Token 자동 갱신 (2시간 만료). 1시간마다 만료 임박한 토큰을 refresh한다.
 * Refresh Token은 2주 만료이므로 그 안에 최소 1회 갱신되면 유지된다.
 */
export const refreshCafe24Tokens = onSchedule(
  {schedule: "every 60 minutes", secrets: [CLIENT_ID, CLIENT_SECRET]},
  async () => {
    const db = getFirestore();
    const soon = Timestamp.fromMillis(Date.now() + 30 * 60 * 1000); // 30분 내 만료
    const snap = await db
      .collection("secrets")
      .where("accessExpiresAt", "<", soon)
      .get();
    for (const doc of snap.docs) {
      const data = doc.data();
      if (!data.mallId || !data.refreshToken) continue;
      try {
        await refreshOne(data.mallId as string, data.refreshToken as string);
      } catch (e) {
        logger.error(`토큰 갱신 실패: ${data.mallId}`, e);
        // 갱신 실패(대개 refresh token 2주 만료) → 연동 끊김으로 표시해
        // 운영자 상품관리 화면에 경고가 뜨게 한다. 재인증(앱 재설치) 필요.
        await writeStatus(data.mallId as string, {connected: false});
        // [추가] 운영자에게 능동 푸시 알림 전송
        await notifyOperators(
          "카페24 연동 장애",
          `[${data.mallId}] 토큰 갱신 실패. 운영자 화면에서 재인증이 필요합니다.`,
        );
      }
    }
  }
);

async function refreshOne(
  mallId: string,
  refreshToken: string,
): Promise<Cafe24Token> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });
  const resp = await fetch(
    `https://${mallId}.cafe24api.com/api/v2/oauth/token`,
    {
      method: "POST",
      headers: {
        "Authorization": basicAuth(),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: body.toString(),
    }
  );
  if (!resp.ok) throw new Error(`refresh ${resp.status}`);
  const token = (await resp.json()) as Cafe24Token;
  await saveToken(mallId, token);
  return token;
}

// ---- 주문 폴링 (EWOS-21) ----
// 카페24는 주문 웹훅을 제공하지 않아, 스케줄러로 Admin API를 주기 조회해 적재한다.

// Admin API 요구 버전(날짜형). 카페24가 버전을 올리면 여기만 수정한다.
const API_VERSION = "2024-06-01";

// 한 번에 조회할 주문 수(카페24 orders 최대 limit).
const PAGE_SIZE = 100;

interface Cafe24Item {
  product_no?: number;
  product_name?: string;
  quantity?: number | string;
  product_price?: number | string;
}

interface Cafe24Order {
  order_id: string;
  order_date?: string;
  member_id?: string;
  billing_name?: string;
  items?: Cafe24Item[];
}

interface PartnerRef {
  id: string;
  name: string;
}

/** 저장된 토큰을 읽고, 만료 임박(5분 이내)이면 갱신해 유효한 access token을 돌려준다. */
async function ensureAccessToken(mallId: string): Promise<string | null> {
  const snap = await getFirestore()
    .collection("secrets").doc(`cafe24_${mallId}`).get();
  const data = snap.data();
  if (!data?.accessToken || !data?.refreshToken) return null;
  const exp = (data.accessExpiresAt as Timestamp | undefined)?.toMillis() ?? 0;
  if (exp - Date.now() > 5 * 60 * 1000) return data.accessToken as string;
  const refreshed = await refreshOne(mallId, data.refreshToken as string);
  return refreshed.access_token;
}

/** cafe24MemberId가 등록된 거래처를 회원ID→거래처 맵으로 만든다. */
async function loadPartnerMap(): Promise<Map<string, PartnerRef>> {
  const snap = await getFirestore()
    .collection("partners").where("cafe24MemberId", "!=", null).get();
  const map = new Map<string, PartnerRef>();
  for (const doc of snap.docs) {
    const memberId = doc.data().cafe24MemberId as string | undefined;
    if (memberId) map.set(memberId, {id: doc.id, name: doc.data().name ?? ""});
  }
  return map;
}

/** UTC ms를 카페24 조회용 KST 날짜(yyyy-mm-dd)로 변환한다. */
function kstDate(ms: number): string {
  return new Date(ms + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** 주문 한 페이지 조회. embed=items로 품목까지 함께 받는다. */
async function fetchOrdersPage(
  mallId: string, token: string,
  startDate: string, endDate: string, offset: number,
): Promise<Cafe24Order[]> {
  const qs = new URLSearchParams({
    start_date: startDate, end_date: endDate,
    limit: String(PAGE_SIZE), offset: String(offset), embed: "items",
  });
  const resp = await fetch(
    `https://${mallId}.cafe24api.com/api/v2/admin/orders?${qs.toString()}`,
    {headers: {
      "Authorization": `Bearer ${token}`,
      "X-Cafe24-Api-Version": API_VERSION,
    }},
  );
  if (!resp.ok) throw new Error(`주문 조회 ${resp.status}: ${await resp.text()}`);
  const json = (await resp.json()) as {orders?: Cafe24Order[]};
  return json.orders ?? [];
}

/** 단일 주문 상세 조회(embed=items). 없으면 null. 웹훅의 신뢰 경계 재조회에 쓴다. */
async function fetchOrder(
  mallId: string, token: string, orderId: string,
): Promise<Cafe24Order | null> {
  const resp = await fetch(
    `https://${mallId}.cafe24api.com/api/v2/admin/orders/` +
      `${encodeURIComponent(orderId)}?embed=items`,
    {headers: {
      "Authorization": `Bearer ${token}`,
      "X-Cafe24-Api-Version": API_VERSION,
    }},
  );
  if (resp.status === 404) return null;
  if (!resp.ok) throw new Error(`주문 상세 조회 ${resp.status}: ${await resp.text()}`);
  const json = (await resp.json()) as {order?: Cafe24Order};
  return json.order ?? null;
}

/** 카페24 주문을 공통 orders 스키마로 변환한다. member_id로 거래처를 매핑한다. */
function normalizeOrder(
  o: Cafe24Order, partners: Map<string, PartnerRef>,
): Record<string, unknown> {
  const items = (o.items ?? []).map((it) => {
    const qty = Number(it.quantity ?? 0);
    const unitPrice = Math.round(Number(it.product_price ?? 0));
    return {
      productId: String(it.product_no ?? ""),
      name: it.product_name ?? "",
      qty, unitPrice, amount: qty * unitPrice,
    };
  });
  const totalAmount = items.reduce((sum, it) => sum + it.amount, 0);
  const partner = o.member_id ? partners.get(o.member_id) : undefined;

  const createdDate = o.order_date ? new Date(o.order_date) : new Date();
  // 카페24 주문은 희망배송일이 없으므로 생성일 기준 '가장 빠른 평일'을 기본값으로 설정한다.
  // (목록 누락 방지 및 운영자 배송 관리 편의 목적)
  let defaultDelivery = new Date(createdDate);
  defaultDelivery.setDate(defaultDelivery.getDate() + 1); // 기본 익일
  while (defaultDelivery.getDay() === 0 || defaultDelivery.getDay() === 6) {
    defaultDelivery.setDate(defaultDelivery.getDate() + 1); // 주말 건너뜀
  }

  return {
    orderNo: o.order_id,
    source: "cafe24",
    status: "new",
    items, totalAmount,
    // 미매핑 주문은 partnerId=null → 운영자에게 "미분류"로 표시된다.
    partnerId: partner?.id ?? null,
    partnerName: partner?.name ?? o.billing_name ?? null,
    cafe24OrderId: o.order_id,
    history: [{status: "new", byUid: "system", at: Timestamp.now()}],
    createdAt: Timestamp.fromDate(createdDate),
    desiredDeliveryDate: Timestamp.fromDate(defaultDelivery),
  };
}

/** order_id 기준 결정적 문서 ID로 최초 1회만 적재한다(운영자 상태변경 보존). */
async function upsertOrders(
  mallId: string, orders: Cafe24Order[], partners: Map<string, PartnerRef>,
): Promise<number> {
  const db = getFirestore();
  let inserted = 0;
  for (const o of orders) {
    const ref = db.collection("orders").doc(`cafe24_${mallId}_${o.order_id}`);
    try {
      await ref.create(normalizeOrder(o, partners));
      inserted++;
    } catch (e) {
      // 이미 존재(ALREADY_EXISTS=6)하면 재적재 없이 건너뛴다.
      if ((e as {code?: number}).code !== 6) throw e;
    }
  }
  return inserted;
}

/** 한 몰의 신규 주문을 조회·적재하고 동기화 커서를 갱신한다. */
async function pollOrdersForMall(
  mallId: string, lastSyncMs: number, partners: Map<string, PartnerRef>,
): Promise<void> {
  const token = await ensureAccessToken(mallId);
  if (!token) return;
  const now = Date.now();
  // 마지막 동기화 하루 전부터(장애 대비 겹침) 오늘까지. 중복은 create-only로 무해.
  const startDate = kstDate((lastSyncMs || now) - 24 * 60 * 60 * 1000);
  const endDate = kstDate(now);
  let offset = 0;
  let inserted = 0;
  let errorCount = 0; // [EWOS-23] 장애 임계치 감지용
  for (;;) {
    try {
      const page = await fetchOrdersPage(mallId, token, startDate, endDate, offset);
      if (page.length === 0) break;
      inserted += await upsertOrders(mallId, page, partners);
      if (page.length < PAGE_SIZE) break;
      offset += PAGE_SIZE;
      errorCount = 0; // 성공 시 리셋
    } catch (e) {
      errorCount++;
      logger.error(`카페24 주문 페이지 조회 실패 (${errorCount}회): ${mallId}`, e);
      if (errorCount >= 3) {
        await notifyOperators(
          "주문 수집 반복 실패",
          `[${mallId}] 주문 폴링이 3회 연속 실패했습니다. 네트워크 또는 API 상태를 확인하세요.`,
        );
        break; // 임계치 초과 시 중단
      }
      // 10초 대기 후 재시도
      await new Promise((resolve) => setTimeout(resolve, 10000));
    }
  }
  await getFirestore().collection("secrets").doc(`cafe24_${mallId}`)
    .set({lastOrderSync: Timestamp.fromMillis(now)}, {merge: true});
  await writeStatus(mallId, {lastOrderSync: Timestamp.fromMillis(now)});
  if (inserted > 0) logger.info(`카페24 주문 적재: ${mallId} +${inserted}건`);
}

/**
 * 카페24 주문 폴링 (EWOS-21). 웹훅 미제공이라 10분마다 조회해 orders에 적재한다.
 * 신규 적재분은 onOrderCreated 트리거가 운영자에게 자동 푸시한다.
 */
export const pollCafe24Orders = onSchedule(
  {schedule: "every 10 minutes", secrets: [CLIENT_ID, CLIENT_SECRET]},
  async () => {
    const db = getFirestore();
    const partners = await loadPartnerMap();
    const snap = await db.collection("secrets").get();
    for (const doc of snap.docs) {
      const data = doc.data();
      if (!data.mallId) continue;
      const lastSync =
        (data.lastOrderSync as Timestamp | undefined)?.toMillis() ?? 0;
      try {
        await pollOrdersForMall(data.mallId as string, lastSync, partners);
      } catch (e) {
        logger.error(`카페24 주문 폴링 실패: ${data.mallId}`, e);
      }
    }
  }
);

// ---- 상품 동기화 (EWOS-22) ----
// 카페24 상품을 products 컬렉션으로 복제한다. 앱은 products만 읽고 카페24를 직접 부르지 않는다.

interface Cafe24Product {
  product_no?: number;
  product_name?: string;
  price?: number | string;
  list_image?: string;
}

/** 상품 한 페이지 조회. */
async function fetchProductsPage(
  mallId: string, token: string, offset: number,
): Promise<Cafe24Product[]> {
  const qs = new URLSearchParams({
    limit: String(PAGE_SIZE), offset: String(offset),
  });
  const resp = await fetch(
    `https://${mallId}.cafe24api.com/api/v2/admin/products?${qs.toString()}`,
    {headers: {
      "Authorization": `Bearer ${token}`,
      "X-Cafe24-Api-Version": API_VERSION,
    }},
  );
  if (!resp.ok) throw new Error(`상품 조회 ${resp.status}: ${await resp.text()}`);
  const json = (await resp.json()) as {products?: Cafe24Product[]};
  return json.products ?? [];
}

/**
 * product_no 기준 결정적 ID로 upsert한다. enabled(발주 가능 여부)는 운영자가 관리하므로
 * 신규 문서에만 true로 넣고, 기존 문서 동기화 시에는 절대 덮어쓰지 않는다.
 */
async function upsertProducts(
  mallId: string, products: Cafe24Product[],
): Promise<number> {
  const db = getFirestore();
  let count = 0;
  for (const p of products) {
    if (p.product_no == null) continue;
    const ref = db.collection("products").doc(`cafe24_${mallId}_${p.product_no}`);
    const fields = {
      name: p.product_name ?? "",
      price: Math.round(Number(p.price ?? 0)),
      cafe24ProductNo: String(p.product_no),
      imageUrl: p.list_image ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    };
    try {
      await ref.create({...fields, enabled: true});
    } catch (e) {
      if ((e as {code?: number}).code !== 6) throw e;
      await ref.update(fields); // 기존 문서: enabled 보존
    }
    count++;
  }
  return count;
}

/** 한 몰의 전체 상품을 페이지네이션으로 동기화하고 상태에 시각을 남긴다. */
async function syncProductsForMall(mallId: string): Promise<number> {
  const token = await ensureAccessToken(mallId);
  if (!token) return 0;
  let offset = 0;
  let total = 0;
  for (;;) {
    const page = await fetchProductsPage(mallId, token, offset);
    if (page.length === 0) break;
    total += await upsertProducts(mallId, page);
    if (page.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }
  await writeStatus(mallId, {
    lastProductSync: FieldValue.serverTimestamp(), productCount: total,
  });
  return total;
}

/**
 * 상품 수동 동기화 (EWOS-22, 운영자 전용). 등록된 모든 몰의 상품을 products로 복제한다.
 * 반환값으로 몰 수·상품 수를 돌려줘 운영자 화면이 결과를 안내한다.
 */
export const syncCafe24Products = onCall(
  {secrets: [CLIENT_ID, CLIENT_SECRET]},
  async (req: CallableRequest) => {
    await assertOperator(req);
    const db = getFirestore();
    const snap = await db.collection("secrets").get();
    let malls = 0;
    let products = 0;
    for (const doc of snap.docs) {
      const mallId = doc.data().mallId as string | undefined;
      if (!mallId) continue;
      malls++;
      products += await syncProductsForMall(mallId);
    }
    logger.info(`카페24 상품 동기화: ${malls}몰 ${products}건`);
    return {malls, products};
  }
);

/**
 * 웹훅 페이로드에서 몰·주문번호를 추출한다. 카페24 이벤트별로 위치가 달라 방어적으로 읽는다.
 */
function extractOrderRef(
  body: Record<string, unknown>,
): {mallId?: string; orderId?: string} {
  const resource = (body.resource ?? {}) as Record<string, unknown>;
  return {
    mallId: (body.mall_id ?? resource.mall_id) as string | undefined,
    orderId: (resource.order_id ?? body.order_id) as string | undefined,
  };
}

/**
 * 주문 웹훅 처리: 페이로드의 주문번호로 Admin API 상세를 재조회(신뢰 경계)해 멱등 적재한다.
 * 본문을 신뢰하지 않으므로 위조 페이로드로 가짜 주문을 넣을 수 없다. 주문 식별자가 없으면
 * 다른 이벤트(상품 등)로 보고 무시한다. 적재분은 onOrderCreated가 운영자에게 푸시한다.
 */
async function handleOrderWebhook(
  event: string, body: Record<string, unknown>,
): Promise<void> {
  const {mallId, orderId} = extractOrderRef(body);
  if (!mallId || !orderId) {
    logger.info("cafe24 웹훅 수신(주문 식별자 없음 → 무시)", {event, mallId, orderId});
    return;
  }
  const token = await ensureAccessToken(mallId);
  if (!token) throw new Error(`유효한 토큰 없음: ${mallId}`);
  const order = await fetchOrder(mallId, token, orderId);
  if (!order) {
    logger.warn("cafe24 웹훅: 주문 상세를 찾지 못함", {mallId, orderId});
    return;
  }
  const partners = await loadPartnerMap();
  const inserted = await upsertOrders(mallId, [order], partners);
  logger.info(`cafe24 웹훅 주문 적재: ${mallId}/${orderId} (+${inserted})`);
}

/**
 * 카페24 웹훅 수신 (EWOS-21). 주문 이벤트를 실시간(저지연) 경로로 적재한다.
 * 무결성은 본문이 아니라 주문번호 재조회로 보장하고, upsert는 멱등(create-only)이라
 * 폴링(pollCafe24Orders)과 중복돼도 안전하다. 처리 성공·실패와 무관하게 즉시 200을
 * 반환해 카페24 재전송 폭주를 막고, 처리 실패분은 폴링이 보정한다.
 *
 * TODO(hardening): 카페24 웹훅 HMAC 서명 스펙 확정 후 요청 서명 검증 추가.
 */
export const cafe24Webhook = onRequest(
  {secrets: [CLIENT_ID, CLIENT_SECRET]},
  async (req, res) => {
    const event = req.get("X-Cafe24-Webhook-Event") ?? "";
    try {
      await handleOrderWebhook(event, (req.body ?? {}) as Record<string, unknown>);
    } catch (e) {
      logger.error("cafe24 웹훅 처리 실패(폴링이 보정)", {event, error: String(e)});
    }
    res.status(200).send("ok");
  }
);
