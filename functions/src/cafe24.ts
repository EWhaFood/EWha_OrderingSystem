import {onRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

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

/** 토큰 응답을 secrets/cafe24_{mallId}에 저장한다(규칙상 클라이언트 접근 불가). */
async function saveToken(mallId: string, t: Cafe24Token): Promise<void> {
  await getFirestore().collection("secrets").doc(`cafe24_${mallId}`).set({
    mallId,
    accessToken: t.access_token,
    refreshToken: t.refresh_token,
    accessExpiresAt: Timestamp.fromDate(new Date(t.expires_at)),
    refreshExpiresAt: Timestamp.fromDate(new Date(t.refresh_token_expires_at)),
    updatedAt: FieldValue.serverTimestamp(),
  });
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
      }
    }
  }
);

async function refreshOne(mallId: string, refreshToken: string): Promise<void> {
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
  await saveToken(mallId, (await resp.json()) as Cafe24Token);
}

/**
 * 웹훅 수신 (주문 접수/상품 수정). 지금은 수신·로깅만 하고,
 * 주문 정규화 → orders 적재는 EWOS-21/22에서 구현한다.
 */
export const cafe24Webhook = onRequest(async (req, res) => {
  logger.info("cafe24 webhook 수신", {
    event: req.get("X-Cafe24-Webhook-Event"),
    body: req.body,
  });
  // TODO(EWOS-21): HMAC 서명 검증 + 주문 상세 조회 + 공통 스키마 정규화 → orders
  res.status(200).send("ok");
});
