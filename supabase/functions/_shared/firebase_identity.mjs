export class FirebaseIdentityError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// Firebase Web API keys identify the public client project. They are not
// privileged server credentials; the Firebase ID token carries the identity.
export const FIREBASE_WEB_API_KEY = "AIzaSyAv-Iwp6wylUC1aK-y4Ba--7cLjnKoveZQ";

export async function verifyFirebaseToken(token, fetchImpl = fetch, firebaseApiKey = FIREBASE_WEB_API_KEY) {
  let response;
  try {
    response = await fetchImpl(
      `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(firebaseApiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: AbortSignal.timeout(10000),
        body: JSON.stringify({ idToken: token }),
      },
    );
  } catch (_) {
    throw new FirebaseIdentityError(503, "Could not verify your session. Try again.");
  }
  if (!response.ok) throw new FirebaseIdentityError(401, "Sign in again to continue.");
  const result = await response.json();
  const user = result.users?.[0];
  if (!user?.localId || user.disabled) {
    throw new FirebaseIdentityError(401, "Sign in again to continue.");
  }
  return user.localId;
}
