import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";

const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7일

/** 초대 코드 형식: 거래처ID 접두어 + 랜덤 4자리 (예: HANSOL-4F2K). */
function makeCode(partnerId: string): string {
  const prefix =
    partnerId.replace(/[^A-Za-z0-9]/g, "").toUpperCase().slice(0, 6) || "INV";
  const rand = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `${prefix}-${rand}`;
}

/** 호출자가 운영자인지 확인한다. role 위조를 막기 위해 서버에서 users 문서를 직접 읽는다. */
export async function assertOperator(req: CallableRequest): Promise<void> {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  const doc = await getFirestore().collection("users").doc(uid).get();
  if (doc.data()?.role !== "operator") {
    throw new HttpsError("permission-denied", "운영자만 사용할 수 있습니다.");
  }
}

/**
 * 초대 코드 발급 (운영자 전용). 1회용·만료 7일.
 * 재발급 시 기존 코드를 무효화하고 새 코드를 partners.inviteCode에 기록한다.
 */
export const issueInvite = onCall(async (req: CallableRequest) => {
  await assertOperator(req);
  const partnerId = (req.data?.partnerId ?? "") as string;
  const db = getFirestore();
  const partnerRef = db.collection("partners").doc(partnerId);
  const partnerSnap = await partnerRef.get();
  if (!partnerSnap.exists) {
    throw new HttpsError("not-found", "거래처를 찾을 수 없습니다.");
  }
  const partnerName = (partnerSnap.data()?.name ?? "") as string;
  const code = makeCode(partnerId);
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_TTL_MS);

  const batch = db.batch();
  const prev = partnerSnap.data()?.inviteCode as string | undefined;
  if (prev) batch.delete(db.collection("inviteCodes").doc(prev));
  batch.set(db.collection("inviteCodes").doc(code), {
    partnerId,
    partnerName,
    expiresAt,
    usedAt: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.update(partnerRef, {inviteCode: code, inviteExpiresAt: expiresAt});
  await batch.commit();
  return {code, expiresAt: expiresAt.toMillis(), partnerName};
});

/**
 * 초대 코드로 거래처 가입 (미인증 호출 허용).
 * 코드 검증 → Auth 계정 생성 → users 문서(role='partner') → 코드 소진.
 * validateOnly가 true이면 검증만 하고 가입은 진행하지 않는다.
 */
export const redeemInvite = onCall(async (req: CallableRequest) => {
  const code = (req.data?.code ?? "") as string;
  const email = (req.data?.email ?? "") as string;
  const password = (req.data?.password ?? "") as string;
  const validateOnly = (req.data?.validateOnly ?? false) as boolean;

  if (!code) {
    throw new HttpsError("invalid-argument", "코드가 필요합니다.");
  }
  if (!validateOnly && (!email || !password)) {
    throw new HttpsError("invalid-argument", "이메일과 비밀번호가 필요합니다.");
  }

  const db = getFirestore();
  const ref = db.collection("inviteCodes").doc(code);

  // 동시 가입 시도를 트랜잭션으로 방어: 코드 소진을 원자적으로 선점한다.
  const info = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "존재하지 않는 코드입니다.");
    const data = snap.data()!;
    if (data.usedAt) throw new HttpsError("already-exists", "이미 사용된 코드입니다.");
    if ((data.expiresAt as Timestamp).toMillis() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "만료된 코드입니다.");
    }

    // 검증만 하는 경우에는 DB를 업데이트하지 않는다.
    if (!validateOnly) {
      tx.update(ref, {usedAt: FieldValue.serverTimestamp(), usedEmail: email});
    }
    return {partnerId: data.partnerId as string, partnerName: data.partnerName as string};
  });

  // 검증만 하는 경우 여기서 종료
  if (validateOnly) {
    return {partnerName: info.partnerName};
  }

  let uid: string;
  try {
    const user = await getAuth().createUser({email, password});
    uid = user.uid;
  } catch (e) {
    // 계정 생성 실패 시 코드 소진을 되돌려 재시도할 수 있게 한다.
    await ref.update({usedAt: null, usedEmail: null});
    throw new HttpsError(
      "already-exists", "이미 가입된 이메일이거나 비밀번호가 약합니다.");
  }
  await db.collection("users").doc(uid).set({
    role: "partner",
    partnerId: info.partnerId,
    email,
    fcmTokens: [],
    createdAt: FieldValue.serverTimestamp(),
  });
  return {partnerName: info.partnerName};
});
