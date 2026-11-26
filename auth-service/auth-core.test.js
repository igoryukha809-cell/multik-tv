import test from "node:test";
import assert from "node:assert/strict";
import {
  clearSessionCookie, getVerifiedVkUserId, parseAdminIds, parseCookies,
  safeEqual, sessionCookie, sha256
} from "./auth-core.js";

test("hashing is stable and does not expose the original token", () => {
  assert.equal(sha256("abc"), sha256("abc"));
  assert.notEqual(sha256("abc"), "abc");
});

test("cookie parser handles encoded values and ignores duplicate keys", () => {
  assert.deepEqual({ ...parseCookies("a=first; session=hello%20world; session=second") }, { a: "first", session: "hello world" });
});

test("constant-time equality rejects different and empty values", () => {
  assert.equal(safeEqual("same", "same"), true);
  assert.equal(safeEqual("same", "other"), false);
  assert.equal(safeEqual("", ""), false);
});

test("admin allowlist accepts only numeric IDs", () => {
  assert.deepEqual([...parseAdminIds("123, 00456, abc, 78x,")], ["123", "00456"]);
});

test("VK user ID must come from a numeric user.user_id field", () => {
  assert.equal(getVerifiedVkUserId({ user: { user_id: 12345 } }), "12345");
  assert.throws(() => getVerifiedVkUserId({ user: { user_id: "abc" } }));
  assert.throws(() => getVerifiedVkUserId({ user_id: "12345" }));
});

test("session cookie is shared-domain, secure, and HttpOnly", () => {
  const value = sessionCookie("opaque", ".example.com");
  assert.match(value, /^__Secure-vkid_session=opaque;/);
  assert.match(value, /Domain=\.example\.com/);
  assert.match(value, /HttpOnly/);
  assert.match(value, /Secure/);
  assert.match(value, /SameSite=Lax/);
  assert.match(clearSessionCookie(".example.com"), /Max-Age=0/);
});
